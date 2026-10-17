import Foundation
import Testing

@testable import Foreman

/// editor R17, R18: the path index and the contract expected from FuzzyMatch.
struct QuickOpenIndexTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "QuickOpenIndexTests-\(UUID().uuidString)")
        for folder in ["src/main/java/app", "node_modules/x", ".git/objects", "docs", ".foreman"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for file in [
            "src/main/java/app/UserController.java", "src/main/java/app/UserService.java", "docs/user-guide.md",
            "node_modules/x/index.js", ".git/objects/ab", ".foreman/state.json", "README.md",
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

    /// editor R18: the palette cancels its search at each keystroke; that must not reach the
    /// shared walk, which the next search finds complete.
    @Test func aCancelledCallerDoesNotEmptyTheIndex() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManyFiles(in: "docs")
        let index = QuickOpenIndex(root: root)
        let first = Task { await index.search("f1", limit: 5) }
        await waitUntilTheWalkIsUnderway(index)
        first.cancel()
        let second = await index.search("f1", limit: 5)
        #expect(await index.count == 1204)
        #expect(!second.paths.isEmpty)
        _ = await first.value
        #expect(await index.count == 1204)
    }

    /// editor R18: a search arriving during the walk waits for it instead of scoring half an index.
    @Test func twoOverlappingSearchesSeeTheFullIndex() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManyFiles(in: "docs")
        let index = QuickOpenIndex(root: root)
        let first = Task { await index.search("f1", limit: 5) }
        await waitUntilTheWalkIsUnderway(index)
        let second = await index.search("f2", limit: 5)
        #expect(await index.count == 1204)
        #expect(!second.paths.isEmpty)
        #expect(await !first.value.paths.isEmpty)
    }

    /// editor R18: a new ignored set abandons the walk in progress, which then leaves alone the
    /// index the next build fills with the new set.
    @Test func setIgnoredDuringABuildRestartsIt() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManyFiles(in: "src")
        let index = QuickOpenIndex(root: root)
        let building = Task { await index.build() }
        await waitUntilTheWalkIsUnderway(index)
        await index.setIgnored(["docs"])
        await index.build()
        #expect(await index.count == 1203)
        #expect(await index.search("userguide", limit: 5).paths.isEmpty)
        await building.value
        #expect(await index.count == 1203)
    }

    @Test func subsequencePrefilterIsCaseInsensitiveAndOrdered() {
        let needle = QuickOpenIndex.lowered("WSV")
        #expect(QuickOpenIndex.isSubsequence(needle, of: QuickOpenIndex.lowered("Foreman/App/WorkspaceView.swift")))
        #expect(QuickOpenIndex.isSubsequence(needle, of: QuickOpenIndex.lowered("w-s-v")))
        #expect(!QuickOpenIndex.isSubsequence(needle, of: QuickOpenIndex.lowered("vsw")))
        #expect(!QuickOpenIndex.isSubsequence(needle, of: QuickOpenIndex.lowered("ws")))
        #expect(QuickOpenIndex.isSubsequence([], of: QuickOpenIndex.lowered("anything")))
        #expect(QuickOpenIndex.lowered("Élan") == Array("élan".utf8))
    }

    @Test func skipsWhatIsNotAFileToOpen() {
        #expect(QuickOpenIndex.isSkipped(".git", rootIsHome: false))
        #expect(QuickOpenIndex.isSkipped("a/.foreman", rootIsHome: false))
        #expect(QuickOpenIndex.isSkipped("node_modules", rootIsHome: false))
        #expect(!QuickOpenIndex.isSkipped("src", rootIsHome: false))
    }

    /// Returns at the walk's first yield (every 512 entries): the only moment another call can
    /// reach the actor while the index is half built.
    private func waitUntilTheWalkIsUnderway(_ index: QuickOpenIndex) async {
        while await index.count == 0 {
            await Task.yield()
        }
    }

    private func writeManyFiles(in folder: String) throws {
        for number in 0..<1200 {
            try Data().write(to: root.appending(path: "\(folder)/f\(number).txt"))
        }
    }
}
