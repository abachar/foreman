import Foundation
import Testing

@testable import Foreman

/// The persisted part of the explorer (explorer R5, R11).
@MainActor
struct ExplorerModelTests {
    private let model = ExplorerModel(root: URL(filePath: "/tmp/ExplorerModelTests"))

    @Test func roundtripsExpandedFoldersAndTheToggle() throws {
        model.setExpanded("src", true)
        model.setExpanded("src/app", true)
        model.setExpanded("docs", true)
        model.setExpanded("docs", false)
        model.hidesExcluded = true

        let data = try JSONEncoder().encode(model.persisted)
        let restored = ExplorerModel(root: model.root)
        restored.restore(try JSONDecoder().decode(ExplorerState.self, from: data))

        #expect(restored.expanded == ["src", "src/app"])
        #expect(restored.hidesExcluded)
        #expect(restored.persisted == model.persisted)
    }

    @Test func neverRestoresAGreyedOrUnreadableFolderExpanded() {
        model.restore(ExplorerState(expanded: ["src", "node_modules", "locked", "file.txt"], hidesExcluded: false))
        let folder = FileNode(relativePath: "src", kind: .directory, isExcluded: false, isUnreadable: false)
        let greyed = FileNode(relativePath: "node_modules", kind: .directory, isExcluded: true, isUnreadable: false)
        let locked = FileNode(relativePath: "locked", kind: .directory, isExcluded: false, isUnreadable: true)
        let file = FileNode(relativePath: "file.txt", kind: .file, isExcluded: false, isUnreadable: false)
        let other = FileNode(relativePath: "other", kind: .directory, isExcluded: false, isUnreadable: false)

        #expect(model.isRestoredExpanded(folder))
        #expect(!model.isRestoredExpanded(greyed))
        #expect(!model.isRestoredExpanded(locked))
        #expect(!model.isRestoredExpanded(file))
        #expect(!model.isRestoredExpanded(other))
    }

    @Test func forgettingACollapsedFolderDropsItsLevelOnly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ExplorerModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "a"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExplorerModel(root: root)
        await model.load("")
        await model.load("a")
        #expect(model.children(of: "")?.map(\.name) == ["a"])
        #expect(model.children(of: "a") == [])

        model.forget("a")

        #expect(model.children(of: "a") == nil)
        #expect(model.children(of: "") != nil)
        #expect(model.journal.last?.change == .folder("a"))
    }

    // MARK: - The journal the outline replays (explorer R9, R15; M23 23.5)

    private func status(_ statuses: [String: GitFileStatus]) -> GitStatusChange {
        GitStatusChange(repo: GitRepo(id: ".", url: model.root), statuses: statuses)
    }

    private func temporaryRoot(files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ExplorerModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return root
    }

    @Test func anIdenticalStatusBumpsNothing() {
        model.applyGitStatus(status(["src/app/a.swift": .modified]))
        model.applyGitStatus(status(["src/app/a.swift": .modified]))

        #expect(model.version == 1)
        // The file, and the folders its dot propagates onto.
        #expect(model.journal == [.init(version: 1, change: .rows(["src/app/a.swift", "src/app", "src"]))])
    }

    @Test func aStatusChangingOneFileReloadsItsRowsOnly() {
        model.applyGitStatus(status(["src/a.swift": .modified]))
        model.applyGitStatus(status(["src/a.swift": .modified, "src/b.swift": .modified]))

        // `src` already carried a modified dot and still does: only the new file's row moves.
        #expect(model.version == 2)
        #expect(model.journal.last == .init(version: 2, change: .rows(["src/b.swift"])))
    }

    @Test func aFolderNewlyIgnoredReloadsTheRowsShownBelowIt() async throws {
        let root = try temporaryRoot(files: ["build/out.o", "README.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExplorerModel(root: root)
        await model.load("")
        await model.load("build")

        model.applyGitStatus(GitStatusChange(repo: GitRepo(id: ".", url: root), statuses: ["build/": .ignored]))

        #expect(model.journal.last?.change == .rows(["build", "build/out.o"]))
    }

    @Test func loadingAFolderJournalsIt() async throws {
        let root = try temporaryRoot(files: ["a/x.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExplorerModel(root: root)

        await model.load("")
        await model.load("a")
        #expect(model.journal == [.init(version: 1, change: .folder("")), .init(version: 2, change: .folder("a"))])

        model.forget("a")
        #expect(model.journal.last == .init(version: 3, change: .folder("a")))
    }
}

/// explorer R9: which loaded folders a batch of FSEvents paths makes the explorer read again.
struct ExplorerReloadTests {
    private let root = URL(filePath: "/ws")

    private func reload(_ paths: [String], loaded: Set<String>) -> Set<String> {
        ExplorerModel.foldersToReload(paths.map { root.appending(path: $0) }, root: root, loaded: loaded)
    }

    @Test func reloadsTheParentOfEachChangedPathOnce() {
        #expect(reload(["src/a.swift", "src/b.swift", "README.md"], loaded: ["", "src"]) == ["", "src"])
    }

    @Test func ignoresFoldersNotReadYet() {
        #expect(reload(["src/deep/x.swift"], loaded: ["", "src"]) == [])
        #expect(reload(["src/deep"], loaded: ["", "src"]) == ["src"])
    }

    @Test func reloadsAChangedFolderItselfWhenItIsLoaded() {
        #expect(reload(["src"], loaded: ["", "src"]) == ["", "src"])
    }

    @Test func ignoresPathsOutsideTheRoot() {
        let outside = ExplorerModel.foldersToReload([URL(filePath: "/elsewhere/x")], root: root, loaded: [""])
        #expect(outside == [])
    }

    // MARK: - What the outline replays (M23 23.5)

    private func journal(_ changes: [ExplorerModel.Change], from first: Int = 1) -> [ExplorerModel.JournalEntry] {
        changes.enumerated().map { .init(version: first + $0.offset, change: $0.element) }
    }

    @Test func theSameVersionReloadsNothing() {
        let plan = ExplorerModel.reloadPlan(from: 2, to: 2, journal: journal([.folder("a"), .folder("b")]))
        #expect(plan == .partial(folders: [], rows: []))
    }

    @Test func aGapBeyondTheJournalReloadsEverything() {
        let entries = journal([.folder("a"), .rows(["b"])], from: 5)

        #expect(ExplorerModel.reloadPlan(from: 3, to: 6, journal: entries) == .everything)
        #expect(ExplorerModel.reloadPlan(from: -1, to: 0, journal: []) == .everything)
    }

    @Test func unionsTheFoldersAndTheRowsBetweenTwoVersions() {
        let entries = journal([.folder("old"), .folder("a"), .rows(["b.txt"]), .rows(["c/d.txt", "c"])])

        let plan = ExplorerModel.reloadPlan(from: 1, to: 4, journal: entries)

        #expect(plan == .partial(folders: ["a"], rows: ["b.txt", "c/d.txt", "c"]))
    }

    @Test func dropsTheRowsAReloadedFolderRebuilds() {
        let entries = journal([.rows(["src", "src/app/a.swift", "README.md"]), .folder("src"), .folder("doc")])

        // `reloadItem(src, reloadChildren: true)` redraws `src` itself and its whole subtree.
        #expect(
            ExplorerModel.reloadPlan(from: 0, to: 3, journal: entries)
                == .partial(folders: ["src", "doc"], rows: ["README.md"]))
        #expect(
            ExplorerModel.reloadPlan(from: 0, to: 2, journal: journal([.rows(["a", "b/c"]), .folder("")]))
                == .partial(folders: [""], rows: []))
    }
}

/// explorer R14: which folders open to reach the active tab's file.
struct ExplorerRevealTests {
    @Test func listsAncestorsRootFirst() {
        #expect(ExplorerModel.foldersToExpand(toReach: "src/app/Main.swift") == ["src", "src/app"])
        #expect(ExplorerModel.foldersToExpand(toReach: "README.md") == [])
    }

    @Test func ignoresFilesOutsideTheRoot() {
        #expect(ExplorerModel.foldersToExpand(toReach: "/etc/hosts") == nil)
        #expect(ExplorerModel.foldersToExpand(toReach: "") == nil)
    }

    @Test func decodesAStateWithoutTheFollowToggle() throws {
        let data = Data(#"{"expanded":["a"],"hidesExcluded":true}"#.utf8)
        let state = try JSONDecoder().decode(ExplorerState.self, from: data)
        #expect(state.followsActiveTab)
        #expect(state.hidesExcluded)
    }
}

/// explorer R23: the single-child chain a folded row shows, and how it is persisted (R11).
@MainActor
struct ExplorerFoldedChainTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ExplorerFoldedChainTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func make(directories: [String] = [], files: [String] = []) throws {
        for directory in directories {
            try FileManager.default.createDirectory(
                at: root.appending(path: directory), withIntermediateDirectories: true)
        }
        for file in files {
            try Data().write(to: root.appending(path: file))
        }
    }

    private func node(_ path: String, kind: FileNode.Kind = .directory, isExcluded: Bool = false) -> FileNode {
        FileNode(relativePath: path, kind: kind, isExcluded: isExcluded, isUnreadable: false)
    }

    // MARK: - Where the chain stops (pure)

    @Test func foldsIntoTheSingleFolderOfALevel() {
        #expect(ExplorerModel.foldTarget([node("src/main")], isGreyed: { _ in false })?.relativePath == "src/main")
    }

    @Test func stopsAtTwoChildren() {
        let nodes = [node("src/main"), node("src/test")]

        #expect(ExplorerModel.foldTarget(nodes, isGreyed: { _ in false }) == nil)
    }

    @Test func stopsAtAFileAndAtALink() {
        #expect(ExplorerModel.foldTarget([node("src/a.swift", kind: .file)], isGreyed: { _ in false }) == nil)
        #expect(
            ExplorerModel.foldTarget([node("src/link", kind: .symlink(toDirectory: true))], isGreyed: { _ in false })
                == nil)
    }

    @Test func stopsAtAGreyedFolder() {
        let excluded = [node("src/node_modules", isExcluded: true)]

        #expect(ExplorerModel.foldTarget(excluded, isGreyed: { $0.isExcluded }) == nil)
        #expect(ExplorerModel.foldTarget([node("src/build")], isGreyed: { $0.relativePath == "src/build" }) == nil)
    }

    @Test func stopsAtAnEmptyFolder() {
        #expect(ExplorerModel.foldTarget([], isGreyed: { _ in false }) == nil)
    }

    // MARK: - The chain on a real folder (explorer R7: read at the expansion)

    @Test func readsTheWholeChainAtTheExpansionAndListsItsLastSegment() async throws {
        try make(directories: ["src/main/java"], files: ["src/main/java/Foo.java", "README.md"])
        let model = ExplorerModel(root: root)

        await model.load("")
        #expect(model.chain(of: "src") == "src")

        await model.load("src")
        #expect(model.chain(of: "src") == "src/main/java")
        #expect(model.children(of: model.chain(of: "src"))?.map(\.name) == ["Foo.java"])
    }

    @Test func aCollapsedRowReadsItsOwnNameAgain() async throws {
        try make(directories: ["src/main/java"], files: ["src/main/java/Foo.java"])
        let model = ExplorerModel(root: root)
        await model.load("")
        await model.load("src")

        model.forget("src")

        #expect(model.chain(of: "src") == "src")
        #expect(model.level("src") == nil)
        #expect(model.level("src/main") == nil)
    }

    @Test func aSecondChildAppearingBreaksTheChain() async throws {
        try make(directories: ["src/main/java"], files: ["src/main/java/Foo.java"])
        let model = ExplorerModel(root: root)
        await model.load("")
        await model.load("src")
        #expect(model.chain(of: "src") == "src/main/java")

        try make(directories: ["src/main/kotlin"])
        await model.load("src/main")

        #expect(model.chain(of: "src") == "src/main")
    }

    @Test func aFoldedRowIsPersistedUnderItsOwnPath() async throws {
        try make(directories: ["src/main/java"], files: ["src/main/java/Foo.java"])
        let model = ExplorerModel(root: root)
        await model.load("")
        await model.load("src")

        model.setExpanded("src", true)

        #expect(model.persisted.expanded == ["src"])
        #expect(model.isRestoredExpanded(try #require(model.node(at: "src"))))
    }

    @Test func namesTheRowAfterTheChainItShows() {
        let row = node("src")

        #expect(ExplorerOutlineView.Coordinator.label(of: row, chain: "src/main/java") == "src/main/java")
        #expect(ExplorerOutlineView.Coordinator.label(of: row, chain: "src") == "src")
    }

    @Test func namesTheSegmentsAChainCrosses() {
        #expect(ExplorerModel.chainSegments(from: "src", to: "src/main/java") == ["src/main", "src/main/java"])
        #expect(ExplorerModel.chainSegments(from: "src", to: "src").isEmpty)
    }

    @Test func recomputesTheRowsWhoseChainCrossesARefreshedFolder() {
        let chains = ["src": "src/main/java", "docs": "docs/specs"]

        #expect(ExplorerModel.rowsFolding(through: "src/main", in: chains) == ["src"])
        #expect(ExplorerModel.rowsFolding(through: "src", in: chains) == ["src"])
        #expect(ExplorerModel.rowsFolding(through: "elsewhere", in: chains).isEmpty)
    }
}
