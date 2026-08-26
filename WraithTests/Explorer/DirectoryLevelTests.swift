import Foundation
import Testing

@testable import Wraith

/// Sorting, filtering and truncation of one folder level (explorer R2–R8), on a temporary folder.
struct DirectoryLevelTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DirectoryLevelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    private func read(
        _ path: String = "", rootIsHome: Bool = false, limit: Int? = DirectoryLevel.limit
    ) async throws
        -> DirectoryLevel
    {
        defer { try? FileManager.default.removeItem(at: root) }
        return try await DirectoryLevel.read(path, root: root, rootIsHome: rootIsHome, limit: limit)
    }

    @Test func sortsFoldersFirstThenNamesNaturally() async throws {
        try make(directories: ["zeta", "Alpha"], files: ["file10", "file2", "b.txt", "A.txt"])
        let level = try await read()
        #expect(level.nodes.map(\.name) == ["Alpha", "zeta", "A.txt", "b.txt", "file2", "file10"])
    }

    @Test func hidesGitAndStateButShowsDotfiles() async throws {
        try make(
            directories: [".git", ".github", ".wraith"],
            files: [".env", ".DS_Store", ".wraith/state.json", ".wraith/config.json"])
        let wraith = try await DirectoryLevel.read(".wraith", root: root, rootIsHome: false)
        #expect(wraith.nodes.map(\.relativePath) == [".wraith/config.json"])
        let level = try await read()
        #expect(level.nodes.map(\.name) == [".github", ".wraith", ".env"])
    }

    @Test func greysExcludedEntriesAndHidesThemOnDemand() async throws {
        try make(directories: ["node_modules", "src"], files: ["a.txt"])
        let level = try await read()
        #expect(level.nodes.first { $0.name == "node_modules" }?.isExcluded == true)
        #expect(level.nodes.first { $0.name == "src" }?.isExcluded == false)
        #expect(level.visibleNodes(hidingExcluded: true).map(\.name) == ["src", "a.txt"])
        #expect(level.visibleNodes(hidingExcluded: false).count == 3)
    }

    @Test func truncatesBeyondTheLimitUnlessAllIsAsked() async throws {
        try make(files: (0..<12).map { "f\($0)" })
        let cut = try await DirectoryLevel.read("", root: root, rootIsHome: false, limit: 10)
        #expect(cut.nodes.count == 10)
        #expect(cut.truncatedCount == 2)
        let all = try await read(limit: nil)
        #expect(all.nodes.count == 12)
        #expect(all.truncatedCount == 0)
    }

    @Test func describesSymlinksWithoutFollowingThem() async throws {
        try make(directories: ["dir"], files: ["file"])
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "to-dir"), withDestinationURL: root.appending(path: "dir"))
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "to-file"), withDestinationURL: root.appending(path: "file"))
        let level = try await read()
        let kinds = Dictionary(uniqueKeysWithValues: level.nodes.map { ($0.name, $0.kind) })
        #expect(kinds["to-dir"] == .symlink(toDirectory: true))
        #expect(kinds["to-file"] == .symlink(toDirectory: false))
        #expect(level.nodes.map(\.name) == ["dir", "to-dir", "file", "to-file"])
        #expect(level.nodes.first { $0.name == "to-dir" }?.isExpandable == true)
    }

    @Test func marksAnUnreadableFolderInsteadOfFailing() async throws {
        try make(directories: ["locked"])
        let locked = root.appending(path: "locked")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        }
        let level = try await DirectoryLevel.read("", root: root, rootIsHome: false)
        let node = try #require(level.nodes.first)
        #expect(node.isUnreadable)
        #expect(!node.isExpandable)
        await #expect(throws: ExplorerError.self) {
            try await DirectoryLevel.read("locked", root: root, rootIsHome: false)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        try FileManager.default.removeItem(at: root)
    }

    @Test func greysLibraryOnlyWhenTheRootIsHome() async throws {
        try make(directories: ["Library"])
        let asHome = try await DirectoryLevel.read("", root: root, rootIsHome: true)
        #expect(asHome.nodes.first?.isExcluded == true)
        let level = try await read()
        #expect(level.nodes.first?.isExcluded == false)
    }
}
