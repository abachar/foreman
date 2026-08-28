import Foundation
import Testing

@testable import Foreman

/// editor R14: link and image resolution, and the block model.
struct MarkdownTests {
    private let root = URL(filePath: "/ws")
    private let file = URL(filePath: "/ws/docs/guide/README.md")

    @Test func resolvesLinksAgainstTheFileAndTheRoot() {
        #expect(
            MarkdownLinks.resolve("../specs/a.md", from: file, root: root)
                == .file(URL(filePath: "/ws/docs/specs/a.md")))
        #expect(
            MarkdownLinks.resolve("/src/main.swift#l3", from: file, root: root)
                == .file(URL(filePath: "/ws/src/main.swift")))
        #expect(
            MarkdownLinks.resolve("https://example.com/x", from: file, root: root)
                == .external(URL(string: "https://example.com/x")!))
        #expect(
            MarkdownLinks.resolve("mailto:a@b.c", from: file, root: root) == .external(URL(string: "mailto:a@b.c")!))
    }

    @Test(arguments: ["#anchor", "", "../../../etc/passwd", "ftp://x/y", "file:///etc/hosts"])
    func ignoresWhatMustNotOpen(destination: String) {
        #expect(MarkdownLinks.resolve(destination, from: file, root: root) == .ignored)
    }

    @Test func imagesAreLocalOnly() {
        #expect(MarkdownLinks.image("logo.png", from: file, root: root) == URL(filePath: "/ws/docs/guide/logo.png"))
        #expect(MarkdownLinks.image("https://cdn/x.png", from: file, root: root) == nil)
        #expect(MarkdownLinks.image("../../../x.png", from: file, root: root) == nil)
    }

    @Test func buildsBlocksFromTheAST() async {
        let text = """
            # Title

            Some *emphasis* and a [link](../a.md).

            ```swift
            let x = 1
            ```

            - [x] done
            - todo

            | a | b |
            |---|---|
            | 1 | 2 |

            ![logo](logo.png)
            """
        let blocks = await MarkdownBlocks.make(text, file: file, root: root)
        #expect(blocks.count == 6)
        guard case .heading(let level, let title) = blocks[0] else {
            Issue.record("no heading")
            return
        }
        #expect(level == 1 && String(title.characters) == "Title")
        guard case .paragraph(let paragraph) = blocks[1] else {
            Issue.record("no paragraph")
            return
        }
        #expect(paragraph.runs.contains { $0.link == URL(filePath: "/ws/docs/a.md") })
        #expect(blocks[2] == .code(language: "swift", "let x = 1"))
        guard case .list(let ordered, _, let items) = blocks[3] else {
            Issue.record("no list")
            return
        }
        #expect(!ordered && items.map(\.checked) == [true, nil])
        guard case .table(let header, let rows) = blocks[4] else {
            Issue.record("no table")
            return
        }
        #expect(header.count == 2 && rows.count == 1)
        #expect(blocks[5] == .image(URL(filePath: "/ws/docs/guide/logo.png"), alt: "logo"))
    }
}
