import Foundation
import Testing

@testable import Foreman

/// git R30: the snapshot tree through a temporary index, on a throwaway repo (the system git).
@MainActor
struct GitSnapshotTests {
    nonisolated static let git = URL(filePath: "/usr/bin/git")

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: git.path())))
    func snapshotIncludesUntrackedFilesAndLeavesTheIndexAlone() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GitCLI(executable: Self.git, repo: root, loginEnvironment: ["PATH": "/usr/bin:/bin"])
        _ = try await client.run(["init", "-q"], kind: .write)
        try "a".write(to: root.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "tracked.txt"], kind: .write)
        try "b".write(to: root.appending(path: "new.txt"), atomically: true, encoding: .utf8)

        let tree = try await client.snapshotTree()
        #expect(tree.count == 40)
        let listed = try await client.run(["ls-tree", "--name-only", tree]).text
        #expect(listed.split(separator: "\n").sorted() == ["new.txt", "tracked.txt"])
        // The real index still knows only the staged file.
        let staged = try await client.run(["ls-files", "--cached"]).text
        #expect(staged.trimmingCharacters(in: .whitespacesAndNewlines) == "tracked.txt")
    }
}

/// git R31: the session diff lists what changed since the snapshot, new files included.
@MainActor
struct GitSessionDiffTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func sessionDiffShowsEditsAndNewFilesSinceTheSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitSessionDiffTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GitCLI(executable: GitSnapshotTests.git, repo: root, loginEnvironment: ["PATH": "/usr/bin:/bin"])
        _ = try await client.run(["init", "-q"], kind: .write)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let base = try await client.snapshotTree()
        try "one\ntwo\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)

        let repo = GitRepo(id: ".", url: root)
        let theme = ThemeService()
        let model = GitDiffModel(
            payload: GitDiffPayload(repo: ".", source: .session(base: base, title: "Claude")), client: { client },
            repo: repo, highlighter: Highlighter(theme: theme), theme: theme, statusChanges: nil)
        model.load()
        for _ in 0..<100 where model.diff == nil && model.error == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.error == nil)
        #expect(model.diff?.files.map(\.path).sorted() == ["a.txt", "b.txt"])
    }
}

/// agents R12–R13: `git worktree add -b` and `remove --force`, the branch kept.
@MainActor
struct GitWorktreeTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func addsThenRemovesAWorktreeKeepingItsBranch() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "GitWorktreeTests-\(UUID().uuidString)")
        let root = base.appending(path: "repo")
        let folder = base.appending(path: "wt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let client = GitCLI(executable: GitSnapshotTests.git, repo: root, loginEnvironment: ["PATH": "/usr/bin:/bin"])
        _ = try await client.run(["init", "-q"], kind: .write)
        _ = try await client.run(
            ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"], kind: .write)

        _ = try await client.run(
            ["worktree", "add", "-b", "foreman/claude-1", folder.path(percentEncoded: false), "HEAD"], kind: .write)
        #expect(GitRepo.hasGitEntry(folder))
        _ = try await client.run(["worktree", "remove", "--force", folder.path(percentEncoded: false)], kind: .write)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        let branches = try await client.run(["branch", "--list", "foreman/claude-1"]).text
        #expect(branches.contains("foreman/claude-1"))
    }
}
