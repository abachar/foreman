import Foundation
import Testing

@testable import Foreman

/// editor R34: the file behind an untitled tab — where it lives, how it is numbered, what git and
/// the tree see of it.
struct ScratchTests {
    @Test func numbersTitlesFromTheFirstFreeOne() {
        #expect(Scratch.nextTitle(taken: []) == "Untitled")
        #expect(Scratch.nextTitle(taken: ["Untitled"]) == "Untitled 2")
        #expect(Scratch.nextTitle(taken: ["Untitled", "Untitled 2"]) == "Untitled 3")
        // A gap is filled before the list is continued.
        #expect(Scratch.nextTitle(taken: ["Untitled", "Untitled 3"]) == "Untitled 2")
        // The `.gitignore` sitting next to them is not a title.
        #expect(Scratch.nextTitle(taken: [".gitignore"]) == "Untitled")
    }

    @Test func recognisesTheScratchesOfTheWorkspaceOnly() {
        #expect(Scratch.isScratch(path: ".foreman/scratches/Untitled"))
        #expect(Scratch.isScratch(path: ".foreman/scratches/Untitled 2"))
        #expect(!Scratch.isScratch(path: ".foreman/state.json"))
        #expect(!Scratch.isScratch(path: ".foreman/scratches"))
        // A file of the same name elsewhere, and an absolute path (config R10), are ordinary files.
        #expect(!Scratch.isScratch(path: "src/.foreman/scratches/Untitled"))
        #expect(!Scratch.isScratch(path: "/tmp/x/.foreman/scratches/Untitled"))
        #expect(!Scratch.isScratch(path: ".foreman/scratches/deep/Untitled"))
    }

    @Test func createsTheFolderItsGitignoreAndNumberedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScratchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try await Scratch.create(root: root)
        #expect(Workspace.persistedPath(for: first, root: root) == ".foreman/scratches/Untitled")
        #expect(try String(contentsOf: first, encoding: .utf8).isEmpty)
        // git R6: the folder ignores itself, so no draft reaches the Changes panel.
        let ignore = Scratch.folder(root: root).appending(path: ".gitignore")
        #expect(try String(contentsOf: ignore, encoding: .utf8) == "*\n")

        let second = try await Scratch.create(root: root)
        #expect(Workspace.persistedPath(for: second, root: root) == ".foreman/scratches/Untitled 2")

        await Scratch.remove(first)
        #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        let third = try await Scratch.create(root: root)
        #expect(third == first)
    }

    /// explorer R3: the drafts are not files of the workspace, so the tree never shows them.
    @Test func keepsScratchesOutOfTheTree() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScratchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await Scratch.create(root: root)
        try Data("{}".utf8).write(to: root.appending(path: ".foreman/state.json"))
        try Data("{}".utf8).write(to: root.appending(path: ".foreman/config.json"))

        let level = try await DirectoryLevel.read(".foreman", root: root, rootIsHome: false)
        #expect(level.nodes.map(\.name) == ["config.json"])
    }
}
