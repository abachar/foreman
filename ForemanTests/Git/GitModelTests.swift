import Foundation
import Testing

@testable import Foreman

/// The pure logic of the changes panel (git R2, R4, R6) and its persisted section.
struct GitModelTests {
    private let root = URL(filePath: "/work")
    private var repos: [GitRepo] {
        [
            GitRepo(id: ".", url: URL(filePath: "/work")),
            GitRepo(id: "libs/core", url: URL(filePath: "/work/libs/core")),
        ]
    }

    private func refreshed(_ paths: [String], gitDirectories: [String: URL] = [:]) -> Set<String> {
        GitModel.reposToRefresh(
            paths.map { URL(filePath: $0) }, repos: repos, gitDirectories: gitDirectories, root: root)
    }

    // MARK: - git R4

    @Test func aChangedPathBelongsToTheDeepestRepo() {
        #expect(refreshed(["/work/README.md"]) == ["."])
        #expect(refreshed(["/work/libs/core/src/a.swift"]) == ["libs/core"])
        #expect(refreshed(["/work/libs/other.txt", "/work/libs/core/b"]) == [".", "libs/core"])
        #expect(refreshed(["/elsewhere/x"]).isEmpty)
    }

    @Test func anExistingRepoFolderMatchesDespiteTheTrailingSlashOfItsURL() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GitModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = GitRepo(id: ".", url: folder)
        #expect(repo.url.path(percentEncoded: false).hasSuffix("/"))
        let changed = [folder.appending(path: "a.txt"), folder.appending(path: ".git/index")]
        #expect(GitModel.reposToRefresh(changed, repos: [repo], gitDirectories: [:], root: folder) == ["."])
    }

    @Test func onlyTheMeaningfulFilesOfTheGitDirectoryCount() {
        #expect(refreshed(["/work/.git/HEAD"]) == ["."])
        #expect(refreshed(["/work/.git/index"]) == ["."])
        #expect(refreshed(["/work/.git/refs/heads/main"]) == ["."])
        #expect(refreshed(["/work/.git/MERGE_HEAD"]) == ["."])
        #expect(refreshed(["/work/libs/core/.git/rebase-merge/done"]) == ["libs/core"])
        #expect(refreshed(["/work/libs/core/.git"]) == ["libs/core"])
        #expect(refreshed(["/work/.git/index.lock"]).isEmpty)
        #expect(refreshed(["/work/.git/objects/ab/cdef"]).isEmpty)
        #expect(refreshed(["/work/.git/logs/HEAD", "/work/.git/FETCH_HEAD", "/work/.git/COMMIT_EDITMSG"]).isEmpty)
        #expect(refreshed(["/work/.foreman/state.json", "/work/node_modules/x/y.js"]).isEmpty)
    }

    @Test func aWorktreeGitFolderOutsideTheRepoIsWatchedThroughItsOwner() {
        let directories = ["libs/core": URL(filePath: "/work/.worktrees/core")]
        #expect(refreshed(["/work/.worktrees/core/HEAD"], gitDirectories: directories) == ["libs/core"])
        #expect(refreshed(["/work/.worktrees/core/objects/ab"], gitDirectories: directories).isEmpty)
        let outside = ["libs/core": URL(filePath: "/opt/wt")]
        #expect(refreshed(["/opt/wt/index"], gitDirectories: outside) == ["libs/core"])
        #expect(refreshed(["/opt/wt/index.lock"], gitDirectories: outside).isEmpty)
    }

    @Test func twoRequestsDuringARunLeaveExactlyOnePendingRun() {
        var coalescer = RefreshCoalescer()
        let first = coalescer.request("a")
        let second = coalescer.request("a")
        let third = coalescer.request("a")
        let other = coalescer.request("b")
        let rerun = coalescer.finished("a")
        let again = coalescer.request("a")
        let done = coalescer.finished("a")
        let otherDone = coalescer.finished("b")
        #expect([first, second, third, other] == [true, false, false, true])
        #expect(rerun)
        #expect(again)
        #expect(!done)
        #expect(!otherDone)
    }

    // MARK: - git R6

    @Test func splitsAStatusIntoConflictsStagedAndChanges() {
        let both = GitStatusEntry(path: "both.txt", index: .modified, worktree: .modified)
        let staged = GitStatusEntry(path: "staged.txt", index: .added, worktree: .unmodified)
        let changed = GitStatusEntry(path: "changed.txt", index: .unmodified, worktree: .deleted)
        let untracked = GitStatusEntry(path: "new.txt", index: .untracked, worktree: .untracked)
        let ignored = GitStatusEntry(path: "out.o", index: .ignored, worktree: .ignored)
        let conflict = GitStatusEntry(path: "c.txt", index: .unmerged, worktree: .unmerged, isConflict: true)
        let sections = GitSections([both, staged, changed, untracked, ignored, conflict])
        #expect(sections.conflicts == [conflict])
        #expect(sections.staged == [both, staged])
        #expect(sections.changes == [both, changed, untracked])
        #expect(GitSections([ignored]).isEmpty)
    }

    // MARK: - git R2

    @Test func collapsesAutomaticallyWithoutChangesAndManuallyOtherwise() {
        #expect(GitModel.Section.isCollapsed(manually: false, hasChanges: false))
        #expect(!GitModel.Section.isCollapsed(manually: false, hasChanges: true))
        #expect(GitModel.Section.isCollapsed(manually: true, hasChanges: true))
    }

    @Test func roundtripsTheManualCollapsesAndKeepsThemAcrossRediscovery() async throws {
        let model = await GitModel()
        await model.restore(GitState(collapsed: ["libs/core"]))
        await model.setRepos(repos)
        await model.toggleCollapsed(".")
        let data = try JSONEncoder().encode(await model.persisted)
        let restored = try JSONDecoder().decode(GitState.self, from: data)
        #expect(restored == GitState(collapsed: [".", "libs/core"]))
        await model.setRepos([repos[1]])
        #expect(await model.persisted == GitState(collapsed: ["libs/core"]))
        #expect(await model.section("libs/core")?.isManuallyCollapsed == true)
    }
}
