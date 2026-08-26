import Foundation
import Testing

@testable import Wraith

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
        #expect(model.lastLoaded == "a")
    }
}
