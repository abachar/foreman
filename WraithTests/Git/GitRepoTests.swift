import Foundation
import Testing

@testable import Wraith

/// Repo discovery over a temporary tree (git R1; edge cases: the `.git` file).
struct GitRepoTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GitRepoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeFolder(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
    }

    @Test func findsGitFoldersAndFilesUpToDepthTwoOutsideTheExclusions() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFolder("a/.git")
        try makeFolder("b/c")
        try Data("gitdir: ../../.worktrees/c\n".utf8).write(to: root.appending(path: "b/c/.git"))
        try makeFolder("b/d/e/.git")
        try makeFolder("node_modules/dep/.git")
        try makeFolder(".hidden/.git")
        try makeFolder("target/x/.git")

        #expect(GitRepo.scan(root: root).map(\.id) == ["a", "b/c"])
        #expect(GitRepo.gitDirectory(of: root.appending(path: "b/c")) == root.appending(path: ".worktrees/c"))
        #expect(GitRepo.gitDirectory(of: root.appending(path: "a")) == root.appending(path: "a/.git"))
        #expect(GitRepo.gitDirectory(of: root.appending(path: "b")) == nil)
    }

    @Test func aRootThatIsARepoIsTheOnlyRepo() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFolder(".git")
        try makeFolder("sub/.git")
        let repos = GitRepo.scan(root: root)
        #expect(repos.map(\.id) == ["."])
        #expect(repos.first?.name == root.lastPathComponent)
        #expect(repos.first?.url == root.standardizedFileURL)
    }

    @Test func declaredReposAreUsedAsTheyAreAndSorted() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFolder("z")
        try makeFolder("m")
        let repos = await GitRepo.discover(
            root: root, declared: [root.appending(path: "z"), root.appending(path: "m")])
        #expect(repos.map(\.id) == ["m", "z"])
        #expect(GitRepo(url: root, root: root).id == ".")
    }

    @Test func readsTheOperationInProgressOffTheGitDirectory() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFolder(".git")
        let git = root.appending(path: ".git")
        #expect(GitOperation.current(inGitDirectory: git) == nil)
        try Data().write(to: git.appending(path: "MERGE_HEAD"))
        #expect(GitOperation.current(inGitDirectory: git) == .merging)
        try FileManager.default.removeItem(at: git.appending(path: "MERGE_HEAD"))
        try makeFolder(".git/rebase-merge")
        #expect(GitOperation.current(inGitDirectory: git) == .rebasing)
        try FileManager.default.removeItem(at: git.appending(path: "rebase-merge"))
        try Data().write(to: git.appending(path: "CHERRY_PICK_HEAD"))
        #expect(GitOperation.current(inGitDirectory: git) == .cherryPicking)
    }
}
