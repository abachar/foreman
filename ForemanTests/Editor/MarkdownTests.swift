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

    /// editor R14, security: a destination leaving the workspace through an in-workspace symlink
    /// is outside, wherever its unresolved path seems to sit.
    @Test func aSymlinkOutOfTheWorkspaceIsIgnored() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "MarkdownTests-\(UUID().uuidString)")
        let workspace = base.appending(path: "ws")
        let outside = base.appending(path: "outside")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("secret".utf8).write(to: outside.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: workspace.appending(path: "link"), withDestinationURL: outside)
        let readme = workspace.appending(path: "README.md")

        #expect(MarkdownLinks.resolve("link/secret.txt", from: readme, root: workspace) == .ignored)
        #expect(MarkdownLinks.image("link/secret.txt", from: readme, root: workspace) == nil)
        // A workspace root that itself sits behind a symlink still contains its own files.
        #expect(
            MarkdownLinks.resolve("notes.md", from: readme, root: workspace)
                == .file(workspace.appending(path: "notes.md").standardizedFileURL))
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

/// design R6 (amended 2026-08-30): what M16 16.4 took from GitHub — the depth markers and the
/// spacing derived from the reading size.
struct MarkdownGitHubTests {
    @Test func bulletsCycleByDepthAsCSSDoes() {
        #expect(MarkdownBlocks.bullet(depth: 0) == "\u{25CF}")
        #expect(MarkdownBlocks.bullet(depth: 1) == "\u{25CB}")
        #expect(MarkdownBlocks.bullet(depth: 2) == "\u{25AA}")
        // CSS restarts the cycle past the third level, and so do we.
        #expect(MarkdownBlocks.bullet(depth: 3) == MarkdownBlocks.bullet(depth: 0))
        #expect(MarkdownBlocks.bullet(depth: -1) == MarkdownBlocks.bullet(depth: 0))
    }

    @Test func orderedMarkersAreDecimalThenRomanThenAlpha() {
        #expect(MarkdownBlocks.number(4, depth: 0) == "4")
        #expect(MarkdownBlocks.number(4, depth: 1) == "iv")
        #expect(MarkdownBlocks.number(4, depth: 2) == "d")
        #expect(MarkdownBlocks.number(4, depth: 3) == "4")
    }

    @Test(arguments: [(1, "i"), (4, "iv"), (9, "ix"), (14, "xiv"), (40, "xl"), (2026, "mmxxvi")])
    func romanNumerals(value: Int, expected: String) {
        #expect(MarkdownBlocks.roman(value) == expected)
    }

    @Test(arguments: [(1, "a"), (26, "z"), (27, "aa"), (52, "az"), (53, "ba")])
    func alphaCounters(value: Int, expected: String) {
        #expect(MarkdownBlocks.alpha(value) == expected)
    }

    /// Neither counter can write these; the decimal is kept rather than an empty marker.
    @Test func countersOutsideTheirRangeKeepTheDecimal() {
        #expect(MarkdownBlocks.roman(0) == "0")
        #expect(MarkdownBlocks.roman(4000) == "4000")
        #expect(MarkdownBlocks.alpha(0) == "0")
    }

    /// design R6: GitHub's numbers at the default reading size of 16.
    @Test func metricsMatchGitHubAtTheDefaultReadingSize() {
        let metrics = MarkdownMetrics(readingFontSize: 16)
        #expect(metrics.blockSpacing == 16)
        // 24 in total above a heading, of which the stack already gives `blockSpacing`.
        #expect(metrics.headingTop + metrics.blockSpacing == 24)
        #expect(metrics.listIndent == 32)
        #expect(metrics.itemSpacing == 4)
        #expect(metrics.itemBlockSpacing == 16)
        #expect(metrics.codePadding == 16)
        #expect(metrics.quoteGap == 16)
        #expect(metrics.cellPadding == (vertical: 6, horizontal: 13))
        // `.3em` of the heading's own size, so the rule sits further from a bigger heading.
        #expect(metrics.headingRuleGap(size: 32) == 10)
        #expect(metrics.headingRuleGap(size: 24) == 7)
    }

    /// The whole layout follows the reading size: nothing is a constant in points.
    @Test func metricsScaleWithTheReadingSize() {
        let metrics = MarkdownMetrics(readingFontSize: 24)
        #expect(metrics.blockSpacing == 24)
        #expect(metrics.listIndent == 48)
        #expect(metrics.itemSpacing == 6)
        #expect(metrics.codePadding == 24)
    }
}
