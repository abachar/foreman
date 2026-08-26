import Foundation
import Testing

@testable import Wraith

/// editor R17, R18: the path index and the contract expected from FuzzyMatch.
struct QuickOpenIndexTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "QuickOpenIndexTests-\(UUID().uuidString)")
        for folder in ["src/main/java/app", "node_modules/x", ".git/objects", "docs", ".wraith"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for file in [
            "src/main/java/app/UserController.java", "src/main/java/app/UserService.java", "docs/user-guide.md",
            "node_modules/x/index.js", ".git/objects/ab", ".wraith/state.json", "README.md",
        ] {
            try Data().write(to: root.appending(path: file))
        }
    }

    @Test func indexesFilesAndSkipsExcludedFolders() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let index = QuickOpenIndex(root: root)
        await index.build()
        #expect(await index.count == 4)
        let hit = await index.search("nodemodules", limit: 10)
        #expect(hit.paths.isEmpty)
        #expect(!hit.isIndexTruncated)
    }

    @Test func ranksTheFileNameMatchFirst() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let index = QuickOpenIndex(root: root)
        await index.build()
        let search = await index.search("usrctrl", limit: 5)
        #expect(search.paths.first == "src/main/java/app/UserController.java")
    }

    @Test func followsAdditionsAndRemovals() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let index = QuickOpenIndex(root: root)
        await index.build()
        let added = root.appending(path: "docs/new.md")
        try Data().write(to: added)
        try FileManager.default.removeItem(at: root.appending(path: "src"))
        await index.apply([added, root.appending(path: "src"), root.appending(path: "node_modules/x/y.js")])
        #expect(await index.count == 3)
        #expect(await index.search("new", limit: 5).paths == ["docs/new.md"])
    }

    @Test func skipsWhatIsNotAFileToOpen() {
        #expect(QuickOpenIndex.isSkipped(".git", rootIsHome: false))
        #expect(QuickOpenIndex.isSkipped("a/.wraith", rootIsHome: false))
        #expect(QuickOpenIndex.isSkipped("node_modules", rootIsHome: false))
        #expect(!QuickOpenIndex.isSkipped("src", rootIsHome: false))
    }
}
