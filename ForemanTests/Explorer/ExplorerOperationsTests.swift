import Foundation
import Testing

@testable import Foreman

/// explorer R16–R19: names, root boundary, and the operations on a temporary folder.
struct ExplorerOperationsTests {
    @Test(arguments: ["", ".", "..", "a/b", "a:b", "a\u{0}b", "/x"])
    func rejectsBadNames(name: String) {
        #expect(!ExplorerOperations.isValidName(name, allowsSlash: false))
    }

    @Test func allowsSlashesOnlyForCreation() {
        #expect(ExplorerOperations.isValidName("a/b/c.txt", allowsSlash: true))
        #expect(!ExplorerOperations.isValidName("a//c.txt", allowsSlash: true))
        #expect(!ExplorerOperations.isValidName("a/../c.txt", allowsSlash: true))
        #expect(ExplorerOperations.isValidName(".env", allowsSlash: false))
    }

    @Test func picksTheTargetFolder() {
        let root = URL(filePath: "/ws")
        let folder = FileNode(relativePath: "src", kind: .directory, isExcluded: false, isUnreadable: false)
        let file = FileNode(relativePath: "src/a.swift", kind: .file, isExcluded: false, isUnreadable: false)
        func path(_ url: URL) -> String {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            return path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        #expect(path(ExplorerOperations.targetFolder(forSelection: nil, root: root)) == "/ws")
        #expect(path(ExplorerOperations.targetFolder(forSelection: folder, root: root)) == "/ws/src")
        #expect(path(ExplorerOperations.targetFolder(forSelection: file, root: root)) == "/ws/src")
    }

    /// explorer R17: a case-only rename is not a collision with itself, another name is.
    @Test func aCaseOnlyRenameOnlyCollidesWithADifferentEntry() {
        #expect(!ExplorerOperations.isTaken("README", siblings: ["Readme", "src"], source: "Readme"))
        #expect(ExplorerOperations.isTaken("README", siblings: ["Readme", "README"], source: "Readme"))
        #expect(!ExplorerOperations.isTaken("Readme", siblings: ["Readme"], source: "Readme"))
    }

    @Test func keepsTheFileWhenARenameIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ExplorerRenameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        try "y".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)

        await #expect(throws: ExplorerError.self) {
            _ = try await ExplorerOperations.rename(source, to: "b.txt", root: root)
        }

        #expect(try String(contentsOf: source, encoding: .utf8) == "x")
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        #expect(left.sorted() == ["a.txt", "b.txt"])
    }

    @Test func createsRenamesAndRefusesOutsideTheRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ExplorerOperationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let created = try await ExplorerOperations.createFile(named: "a/b/Note.md", in: root, root: root)
        #expect(created == root.appending(path: "a/b/Note.md").standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: created.path(percentEncoded: false)))
        await #expect(throws: ExplorerError.self) {
            _ = try await ExplorerOperations.createFile(named: "a/b/Note.md", in: root, root: root)
        }
        let folder = try await ExplorerOperations.createFolder(named: "docs", in: root, root: root)
        #expect(folder.lastPathComponent == "docs")

        let renamed = try await ExplorerOperations.rename(created, to: "Renamed.md", root: root)
        #expect(renamed.lastPathComponent == "Renamed.md")
        let recased = try await ExplorerOperations.rename(renamed, to: "renamed.md", root: root)
        #expect(recased.lastPathComponent == "renamed.md")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "a/b").path(percentEncoded: false))
                == ["renamed.md"])

        await #expect(throws: ExplorerError.self) {
            _ = try await ExplorerOperations.createFile(named: "x", in: root.deletingLastPathComponent(), root: root)
        }
        await #expect(throws: ExplorerError.self) {
            try await ExplorerOperations.trash(root, root: root)
        }
        await #expect(throws: ExplorerError.self) {
            try await ExplorerOperations.trash(URL(filePath: "/tmp/elsewhere"), root: root)
        }
        #expect(await ExplorerOperations.entryCount(of: root) == 4)
    }
}

/// explorer R22: a drop moves inside the root, never onto itself, its parent or a descendant.
struct ExplorerMoveTests {
    @Test func dropTargetsAreChecked() {
        #expect(ExplorerOperations.canMove("src/a.swift", into: "lib"))
        #expect(ExplorerOperations.canMove("src/a.swift", into: ""))
        #expect(!ExplorerOperations.canMove("src/a.swift", into: "src"))
        #expect(!ExplorerOperations.canMove("src", into: "src"))
        #expect(!ExplorerOperations.canMove("src", into: "src/inner"))
        #expect(!ExplorerOperations.canMove("src", into: ""))
        #expect(!ExplorerOperations.canMove("", into: "src"))
    }

    @Test func movesAndRefusesAnExistingName() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ExplorerMoveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "lib"), withIntermediateDirectories: true)
        try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let moved = try await ExplorerOperations.move(
            root.appending(path: "a.txt"), into: root.appending(path: "lib"), root: root)
        #expect(moved.lastPathComponent == "a.txt")
        #expect(FileManager.default.fileExists(atPath: root.appending(components: "lib", "a.txt").path()))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "a.txt").path()))
        try "y".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: ExplorerError.self) {
            try await ExplorerOperations.move(
                root.appending(path: "a.txt"), into: root.appending(path: "lib"), root: root)
        }
        await #expect(throws: ExplorerError.self) {
            try await ExplorerOperations.move(
                root.appending(path: "lib"), into: root.appending(path: "lib"), root: root)
        }
    }
}
