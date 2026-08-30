import Foundation
import Testing

@testable import Foreman

/// git R27: every parser round-tripped against the **real binary**, on a throwaway repo.
///
/// Methodology, and the reason this file exists (audit §4). A fixture written by hand encodes what
/// we believe git prints. C3 was exactly that: `stash list --format` kept `%1f` literal for the
/// life of the feature while the parser test fed itself a real `\u{1f}` and passed. So does M8:
/// the diff parser was written against paths git never prints that way. These tests run the
/// commands the app runs and hand the output to the parsers the app uses.
@MainActor
struct GitGoldenTests {
    /// A throwaway repo with one commit on `main`; the caller gets its client and its folder.
    static func repository(named name: String) async throws -> (GitCLI, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let client = GitCLI(executable: GitSnapshotTests.git, repo: root, loginEnvironment: ["PATH": "/usr/bin:/bin"])
        _ = try await client.run(["init", "-q", "-b", "main"], kind: .write)
        _ = try await client.run(["config", "user.email", "test@example.com"], kind: .write)
        _ = try await client.run(["config", "user.name", "Test"], kind: .write)
        _ = try await client.run(["config", "commit.gpgsign", "false"], kind: .write)
        try "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "-A"], kind: .write)
        _ = try await client.run(["commit", "-qm", "init"], kind: .write)
        return (client, root)
    }

    nonisolated static var hasGit: Bool {
        FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())
    }

    // MARK: - Refs (C3)

    @Test(.enabled(if: hasGit))
    func theStashListParsesWhatGitActuallyPrints() async throws {
        let (client, root) = try await Self.repository(named: "GoldenStash")
        defer { try? FileManager.default.removeItem(at: root) }
        try "one\ntwo\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(GitCommand.stashPush(message: "wip", includeUntracked: false), kind: .write)

        let output = try await client.run(GitCommand.stashList)

        // The separator must arrive as U+001F, not as the three characters "%1f".
        #expect(!output.text.contains("%1f"))
        let stashes = RefParser.stashes(output.stdout)
        #expect(stashes.map(\.ref) == ["stash@{0}"])
        // git prefixes the message with the branch it was taken on.
        #expect(stashes.first?.message == "On main: wip")
    }

    @Test(.enabled(if: hasGit))
    func branchesParseWhatForEachRefActuallyPrints() async throws {
        let (client, root) = try await Self.repository(named: "GoldenBranches")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await client.run(GitCommand.newBranch("feat/x"), kind: .write)

        let output = try await client.run(GitCommand.branches)

        #expect(!output.text.contains("%1f"))
        let branches = RefParser.branches(output.stdout)
        #expect(branches.map(\.name).sorted() == ["feat/x", "main"])
        #expect(branches.first { $0.name == "feat/x" }?.isCurrent == true)
    }

    // MARK: - Status

    @Test(.enabled(if: hasGit))
    func statusReadsAPathWithAnAccentASpaceAndARename() async throws {
        let (client, root) = try await Self.repository(named: "GoldenStatus")
        defer { try? FileManager.default.removeItem(at: root) }
        let odd = "sous dossier/café.txt"
        try FileManager.default.createDirectory(
            at: root.appending(path: "sous dossier"), withIntermediateDirectories: true)
        try "x\n".write(to: root.appending(path: odd), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "-A"], kind: .write)
        _ = try await client.run(["commit", "-qm", "odd"], kind: .write)
        _ = try await client.run(["mv", "a.txt", "b.txt"], kind: .write)
        try "changed\n".write(to: root.appending(path: odd), atomically: true, encoding: .utf8)

        let status = StatusParser.parse(try await client.run(GitCommand.status).stdout)

        #expect(status.head == .branch("main"))
        #expect(status.entries.contains { $0.path == odd })
        let renamed = status.entries.first { $0.path == "b.txt" }
        #expect(renamed?.index == .renamed)
        #expect(renamed?.originalPath == "a.txt")
    }

    // MARK: - Diff (M8)

    @Test(.enabled(if: hasGit))
    func aDiffNamesThePathGitPrintsEvenWithAnAccent() async throws {
        let (client, root) = try await Self.repository(named: "GoldenDiff")
        defer { try? FileManager.default.removeItem(at: root) }
        let odd = "été.txt"
        try "un\n".write(to: root.appending(path: odd), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "-A"], kind: .write)
        _ = try await client.run(["commit", "-qm", "accent"], kind: .write)
        try "un\ndeux\n".write(to: root.appending(path: odd), atomically: true, encoding: .utf8)

        let payload = GitDiffPayload(repo: ".", source: .workingTree(path: odd))
        let diff = DiffParser.parse(try await client.run(payload.arguments()).stdout)

        #expect(diff.files.map(\.path) == [odd])
        #expect(diff.files.first?.hunks.count == 1)
    }

    @Test(.enabled(if: hasGit))
    func aMergeCommitShowsWhatItBrought() async throws {
        let (client, root) = try await Self.repository(named: "GoldenMerge")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await client.run(["switch", "-q", "-c", "side"], kind: .write)
        try "from side\n".write(to: root.appending(path: "side.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "-A"], kind: .write)
        _ = try await client.run(["commit", "-qm", "side"], kind: .write)
        _ = try await client.run(["switch", "-q", "main"], kind: .write)
        try "one\nmain\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["commit", "-qam", "main"], kind: .write)
        _ = try await client.run(["merge", "--no-ff", "-m", "merge side", "side"], kind: .write)
        let sha = try await client.run(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = GitDiffPayload(repo: ".", source: .commit(sha: sha, subject: "merge side"))
        let diff = DiffParser.parse(try await client.run(payload.arguments()).stdout)

        // The combined `diff --cc` git shows by default parses to nothing at all: what the merge
        // brought to `main` is `side.txt`.
        #expect(diff.files.map(\.path) == ["side.txt"])
    }

    @Test(.enabled(if: hasGit))
    func aRenameWithNoEditHasNoHunkAndKeepsBothPaths() async throws {
        let (client, root) = try await Self.repository(named: "GoldenRename")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await client.run(["mv", "a.txt", "renamed.txt"], kind: .write)
        _ = try await client.run(["commit", "-qm", "rename"], kind: .write)
        let sha = try await client.run(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)

        let commit = GitDiffPayload(repo: ".", source: .commit(sha: sha, subject: "rename"))
        let diff = DiffParser.parse(try await client.run(commit.arguments()).stdout)

        let file = diff.files.first
        #expect(file?.isRename == true)
        #expect(file?.oldPath == "a.txt")
        #expect(file?.newPath == "renamed.txt")
        #expect(file?.hunks.isEmpty == true)
    }

    /// What git does, so nobody reads it as a parser bug.
    ///
    /// A pathspec filters the deletion out of the comparison, so `-M` has nothing to pair the new
    /// path with and prints an addition. The Changes panel opens a file diff that way, and names
    /// the rename's origin on the row itself (git R6b).
    @Test(.enabled(if: hasGit))
    func aPathspecHidesTheRenameFromGitItself() async throws {
        let (client, root) = try await Self.repository(named: "GoldenRenamePathspec")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await client.run(["mv", "a.txt", "renamed.txt"], kind: .write)

        let staged = GitDiffPayload(repo: ".", source: .staged(path: "renamed.txt"))
        let diff = DiffParser.parse(try await client.run(staged.arguments()).stdout)

        #expect(diff.files.first?.isRename == false)
        #expect(diff.files.first?.oldPath == nil)
        #expect(diff.files.first?.newPath == "renamed.txt")
    }

    @Test(.enabled(if: hasGit))
    func aFileWithNoFinalNewlineIsMarkedOnTheSideThatLacksIt() async throws {
        let (client, root) = try await Self.repository(named: "GoldenNoNewline")
        defer { try? FileManager.default.removeItem(at: root) }
        // Committed with a trailing newline, edited to lose it.
        try "one".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)

        let payload = GitDiffPayload(repo: ".", source: .workingTree(path: "a.txt"))
        let diff = DiffParser.parse(try await client.run(payload.arguments()).stdout)

        let lines = diff.files.first?.hunks.first?.lines ?? []
        #expect(lines.contains { $0.kind == .added && $0.hasNoNewline })
        #expect(lines.contains { $0.kind == .removed && !$0.hasNoNewline })
    }
}
