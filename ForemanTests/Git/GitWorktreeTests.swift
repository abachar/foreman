import Foundation
import Testing

@testable import Foreman

/// git R33–R38: the worktree list, the parent/child pairing, the refresh paths and the panel order.
struct GitWorktreeChildTests {
    private let root = URL(filePath: "/work")

    private func list(_ fields: [String]) -> Data {
        Data(fields.joined(separator: "\0").utf8)
    }

    // MARK: - git R33

    @Test func parsesEveryKindOfEntry() {
        let data = list([
            "worktree /work/app", "HEAD 1111", "branch refs/heads/main", "",
            "worktree /work/app-fix", "HEAD 2222", "branch refs/heads/fix/TGSCCPAG-467", "",
            "worktree /work/app-detached", "HEAD 3333", "detached", "",
            "worktree /work/app-locked", "HEAD 4444", "branch refs/heads/l", "locked on a USB disk", "",
            "worktree /work/app-silent", "HEAD 5555", "branch refs/heads/s", "locked", "",
            "worktree /work/app-gone", "HEAD 6666", "branch refs/heads/g",
            "prunable gitdir file points to non-existent location", "",
            "worktree /work/bare.git", "bare", "", "",
        ])
        let entries = WorktreeParser.parse(data)
        #expect(
            entries.map(\.folder.lastPathComponent) == [
                "app", "app-fix", "app-detached", "app-locked", "app-silent", "app-gone", "bare.git",
            ])
        #expect(entries[0].branch == "main")
        #expect(entries[1].branch == "fix/TGSCCPAG-467")
        #expect(entries[2].isDetached && entries[2].branch == nil && entries[2].head == "3333")
        #expect(entries[3].lockReason == "on a USB disk")
        #expect(entries[4].lockReason == "")
        #expect(entries[1].lockReason == nil)
        #expect(entries[5].isPrunable)
        #expect(entries[6].isBare)
        #expect(WorktreeParser.parse(Data()).isEmpty)
    }

    @Test func worktreesBecomeChildrenOfTheirRepoByFolderName() {
        let app = GitRepo(id: "app", url: URL(filePath: "/work/app"))
        let api = GitRepo(id: "api", url: URL(filePath: "/work/api"))
        let lists = [
            "app": [
                GitWorktree(folder: URL(filePath: "/work/app")),
                GitWorktree(folder: URL(filePath: "/elsewhere/app-zeta")),
                GitWorktree(folder: URL(filePath: "/elsewhere/app-alpha"), lockReason: "usb"),
                GitWorktree(folder: URL(filePath: "/elsewhere/app-gone"), isPrunable: true),
            ],
            "api": [GitWorktree(folder: URL(filePath: "/work/api"))],
        ]
        let arranged = GitRepo.arrange([api, app], worktrees: lists, root: root)
        #expect(arranged.map(\.id) == ["api", "app", "/elsewhere/app-alpha", "/elsewhere/app-zeta"])
        #expect(arranged.map(\.parent) == [nil, nil, "app", "app"])
        #expect(arranged[2].lockReason == "usb")
        #expect(arranged[2].name == "app-alpha")
    }

    /// git R33a: a worktree the scan found too is a child, not a second top-level section.
    @Test func aScannedWorktreeMovesUnderItsRepo() {
        let app = GitRepo(id: "app", url: URL(filePath: "/work/app"))
        let fix = GitRepo(id: "app-fix", url: URL(filePath: "/work/app-fix"))
        let entries = [
            GitWorktree(folder: URL(filePath: "/work/app")), GitWorktree(folder: URL(filePath: "/work/app-fix")),
        ]
        let arranged = GitRepo.arrange([app, fix], worktrees: ["app": entries, "app-fix": entries], root: root)
        #expect(arranged.map(\.id) == ["app", "app-fix"])
        #expect(arranged.map(\.parent) == [nil, "app"])
    }

    /// git R33a: a workspace opened on a linked worktree keeps its root on top, the main folder under it.
    @Test func aRootThatIsAWorktreeKeepsTheMainFolderAsAChild() {
        let root = GitRepo(id: ".", url: URL(filePath: "/work/app-fix"))
        let entries = [
            GitWorktree(folder: URL(filePath: "/work/app")), GitWorktree(folder: URL(filePath: "/work/app-fix")),
        ]
        let arranged = GitRepo.arrange([root], worktrees: [".": entries], root: URL(filePath: "/work/app-fix"))
        #expect(arranged.map(\.id) == [".", "/work/app"])
        #expect(arranged[1].parent == ".")
    }

    // MARK: - git R35

    @Test func aWorktreeAddedRemovedOrLockedRereadsTheList() {
        let commons = ["app": URL(filePath: "/work/app/.git")]
        func reread(_ path: String) -> Set<String> {
            GitModel.reposToRediscover([URL(filePath: path)], commonDirectories: commons)
        }
        #expect(reread("/work/app/.git/worktrees") == ["app"])
        #expect(reread("/work/app/.git/worktrees/app-fix") == ["app"])
        #expect(reread("/work/app/.git/worktrees/app-fix/locked") == ["app"])
        // An agent committing in its worktree is a status, not a new list.
        #expect(reread("/work/app/.git/worktrees/app-fix/index").isEmpty)
        #expect(reread("/work/app/.git/worktrees/app-fix/HEAD").isEmpty)
        #expect(reread("/work/app/.git/refs/heads/main").isEmpty)
        #expect(reread("/work/app/src/a.swift").isEmpty)
    }

    @Test func aChildsGitFolderRefreshesTheChild() {
        let repos = [
            GitRepo(id: "app", url: URL(filePath: "/work/app")),
            GitRepo(id: "/elsewhere/app-fix", url: URL(filePath: "/elsewhere/app-fix")),
        ]
        let directories = ["/elsewhere/app-fix": URL(filePath: "/work/app/.git/worktrees/app-fix")]
        func refreshed(_ path: String) -> Set<String> {
            GitModel.reposToRefresh([URL(filePath: path)], repos: repos, gitDirectories: directories, root: root)
        }
        #expect(refreshed("/work/app/.git/worktrees/app-fix/index") == ["/elsewhere/app-fix"])
        #expect(refreshed("/elsewhere/app-fix/src/main.ts") == ["/elsewhere/app-fix"])
        #expect(refreshed("/work/app/src/main.ts") == ["app"])
    }

    // MARK: - git R34b, R34c

    @MainActor private func grouped() -> GitModel {
        let model = GitModel()
        var alpha = GitRepo(url: URL(filePath: "/elsewhere/app-alpha"), root: root)
        alpha.parent = "app"
        var zeta = GitRepo(url: URL(filePath: "/elsewhere/app-zeta"), root: root)
        zeta.parent = "app"
        model.setRepos([GitRepo(id: "app", url: URL(filePath: "/work/app")), alpha, zeta])
        return model
    }

    private func session(_ title: String, in path: String, running: Bool = true) -> GitAgentSession {
        GitAgentSession(
            id: TabID(), title: title, icon: "sparkle", cwd: URL(filePath: path), isRunning: running, isMarked: false)
    }

    @Test @MainActor func childrenWithAnAgentComeFirstAndAStateChangeKeepsTheOrder() {
        let model = grouped()
        #expect(model.groups.map { $0.children.map(\.repo.name) } == [["app-alpha", "app-zeta"]])
        model.setAgentSessions([session("Claude", in: "/elsewhere/app-zeta/src")])
        #expect(model.groups[0].children.map(\.repo.name) == ["app-zeta", "app-alpha"])
        model.setAgentSessions([session("Claude", in: "/elsewhere/app-zeta/src", running: false)])
        #expect(model.groups[0].children.map(\.repo.name) == ["app-zeta", "app-alpha"])
        #expect(model.agentSessions(in: "/elsewhere/app-zeta").map(\.title) == ["Claude"])
        #expect(model.agentSessions(in: "app").isEmpty)
        // The session closes: the child goes back to its place.
        model.setAgentSessions([])
        #expect(model.groups[0].children.map(\.repo.name) == ["app-alpha", "app-zeta"])
    }

    @Test func aSessionBelongsToTheDeepestWorkingCopy() {
        let repos = [
            GitRepo(id: ".", url: URL(filePath: "/work")),
            GitRepo(id: "app", url: URL(filePath: "/work/app")),
        ]
        #expect(GitModel.owner(of: URL(filePath: "/work/app/src"), among: repos) == "app")
        #expect(GitModel.owner(of: URL(filePath: "/work/docs"), among: repos) == ".")
        #expect(GitModel.owner(of: URL(filePath: "/work/application"), among: repos) == ".")
        #expect(GitModel.owner(of: URL(filePath: "/tmp"), among: repos) == nil)
    }

    /// git R10 (amended 2026-10-16): the commit area goes where the user last worked.
    @Test @MainActor func theCommitAreaFollowsTheWorkingCopyLastWorkedIn() {
        let model = grouped()
        #expect(model.commitTarget?.id == "app")
        model.setStatus(
            "/elsewhere/app-zeta",
            GitStatus(
                head: .branch("fix"), entries: [GitStatusEntry(path: "a", index: .modified, worktree: .unmodified)]))
        #expect(model.commitTarget?.id == "/elsewhere/app-zeta")
        model.setCommitTarget("/elsewhere/app-alpha")
        #expect(model.commitTarget?.id == "/elsewhere/app-alpha")
        // A target that left (a worktree removed) falls back.
        model.setRepos([GitRepo(id: "app", url: URL(filePath: "/work/app"))])
        #expect(model.commitTarget?.id == "app")
    }

    /// git R34b: a group's fold under the repo id, its main folder's under `<id>#main`.
    @Test @MainActor func aGroupAndItsMainFolderFoldApart() {
        let model = grouped()
        model.toggleGroupCollapsed("app")
        model.toggleCollapsed("app")
        #expect(model.persisted.collapsed == ["app", "app#main"])
        let restored = GitModel()
        restored.restore(model.persisted)
        var alpha = GitRepo(url: URL(filePath: "/elsewhere/app-alpha"), root: root)
        alpha.parent = "app"
        restored.setRepos([GitRepo(id: "app", url: URL(filePath: "/work/app")), alpha])
        #expect(restored.isGroupCollapsed("app"))
        #expect(restored.section("app")?.isManuallyCollapsed == true)
        // Revealing a child opens its group.
        restored.reveal("/elsewhere/app-alpha")
        #expect(!restored.isGroupCollapsed("app"))
        #expect(restored.revealed == "/elsewhere/app-alpha")
    }
}

/// git R33, R36b, R37: on a throwaway repo with a real worktree (the system git).
@MainActor
struct GitWorktreeRepoTests {
    private static let identity = ["-c", "user.email=test@example.com", "-c", "user.name=Test"]

    private struct Fixture {
        let base: URL
        let main: URL
        let worktree: URL
        let client: GitCLI
        let child: GitCLI
    }

    /// `main` with one commit, a worktree `app-fix` on `fix` with two more, and one on `main` after the fork.
    private func fixture() async throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appending(path: "GitWorktreeTests-\(UUID().uuidString)")
        let main = base.appending(path: "app")
        let worktree = base.appending(path: "app-fix")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        let environment = ["PATH": "/usr/bin:/bin"]
        let client = GitCLI(executable: GitSnapshotTests.git, repo: main, loginEnvironment: environment)
        _ = try await client.run(["init", "-q", "-b", "main"], kind: .write)
        try "one\n".write(to: main.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "a.txt"], kind: .write)
        _ = try await client.run(Self.identity + ["commit", "-q", "-m", "first"], kind: .write)
        _ = try await client.run(
            ["worktree", "add", "-q", "-b", "fix", worktree.path(percentEncoded: false)], kind: .write)
        let child = GitCLI(executable: GitSnapshotTests.git, repo: worktree, loginEnvironment: environment)
        for name in ["b", "c"] {
            try "\(name)\n".write(to: worktree.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
            _ = try await child.run(["add", "\(name).txt"], kind: .write)
            _ = try await child.run(Self.identity + ["commit", "-q", "-m", "add \(name)"], kind: .write)
        }
        try "main\n".write(to: main.appending(path: "m.txt"), atomically: true, encoding: .utf8)
        _ = try await client.run(["add", "m.txt"], kind: .write)
        _ = try await client.run(Self.identity + ["commit", "-q", "-m", "main moves"], kind: .write)
        return Fixture(base: base, main: main, worktree: worktree, client: client, child: child)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func theWorktreeIsListedAndPairedWithItsRepo() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let entries = WorktreeParser.parse(try await fixture.client.run(WorktreeParser.arguments).stdout)
        #expect(entries.map(\.branch) == ["main", "fix"])
        let repo = GitRepo(id: "app", url: fixture.main)
        let arranged = GitRepo.arrange([repo], worktrees: ["app": entries], root: fixture.base)
        #expect(arranged.map(\.name) == ["app", "app-fix"])
        #expect(arranged[1].parent == "app")
        #expect(
            GitRepo.commonDirectory(of: fixture.worktree).map(GitRepo.canonicalPath)
                == GitRepo.canonicalPath(fixture.main.appending(path: ".git")))
    }

    /// git R36b: the range lists the branch's two commits; the three dots leave out those of main.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func compareShowsWhatTheBranchAddsOnly() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        var query = GitLogQuery()
        query.range = GitLogQuery.Range(base: "main", head: "fix")
        let log = LogParser.parse(try await fixture.child.run(query.arguments(field: nil)).stdout)
        #expect(log.map(\.subject) == ["add c", "add b"])
        let payload = GitDiffPayload(repo: "app-fix", source: .range(base: "main", head: "fix"))
        let diff = DiffParser.parse(try await fixture.child.run(payload.arguments()).stdout)
        #expect(diff.files.map(\.path).sorted() == ["b.txt", "c.txt"])
        #expect(payload.title == "fix vs main")
        #expect(!payload.source.isImmutable)
    }

    /// git R19b: a commit's files, a rename on one entry with its origin.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func aCommitListsItsFiles() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        _ = try await fixture.client.run(["mv", "a.txt", "renamed.txt"], kind: .write)
        try "new\n".write(to: fixture.main.appending(path: "n.txt"), atomically: true, encoding: .utf8)
        _ = try await fixture.client.run(["add", "-A"], kind: .write)
        _ = try await fixture.client.run(Self.identity + ["commit", "-q", "-m", "rename"], kind: .write)
        let files = CommitFilesParser.parse(try await fixture.client.run(CommitFilesParser.arguments("HEAD")).stdout)
        #expect(files.map(\.path).sorted() == ["n.txt", "renamed.txt"])
        #expect(files.first { $0.path == "renamed.txt" }?.originalPath == "a.txt")
        #expect(files.first { $0.path == "renamed.txt" }?.index == .renamed)
        #expect(files.first { $0.path == "n.txt" }?.index == .added)
    }

    /// git R37: a clean worktree goes and its branch lands in the main folder; a dirty one stays.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: GitSnapshotTests.git.path())))
    func checkOutHereRemovesACleanWorktreeOnly() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        try "dirty\n".write(to: fixture.worktree.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: GitError.self) {
            _ = try await fixture.client.run(GitCommand.removeWorktree(fixture.worktree, force: false), kind: .write)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.worktree.path(percentEncoded: false)))
        _ = try await fixture.child.run(["checkout", "--", "b.txt"], kind: .write)
        _ = try await fixture.client.run(GitCommand.removeWorktree(fixture.worktree, force: false), kind: .write)
        _ = try await fixture.client.run(GitCommand.checkout(GitBranch(local: "fix")), kind: .write)
        #expect(!FileManager.default.fileExists(atPath: fixture.worktree.path(percentEncoded: false)))
        let head = try await fixture.client.run(["branch", "--show-current"]).text
        #expect(head.trimmingCharacters(in: .whitespacesAndNewlines) == "fix")
    }
}

/// git R40 (2026-10-16, M21 21.4): the branch widget's menu as a value.
@MainActor
struct GitBranchMenuTests {
    private func copy(
        _ id: String, _ head: String, path: String = "", ahead: Int = 0, agents: [String] = [],
        current: Bool = false
    ) -> GitBranchMenu.Copy {
        GitBranchMenu.Copy(
            id: id, head: head, path: path, ahead: ahead, agents: agents,
            agentBadge: agents.isEmpty ? .none : .dot(.green), isCurrent: current, isLocked: false)
    }

    private func branch(_ name: String, remote: Bool = false, upstream: String? = nil) -> GitBranch {
        GitBranch(
            name: name, ref: remote ? "refs/remotes/\(name)" : "refs/heads/\(name)", upstream: upstream,
            isCurrent: false)
    }

    private var repo: GitBranchMenu.Repo {
        GitBranchMenu.Repo(
            id: "api", name: "orders-api",
            main: copy("api", "main", path: "~/Projects/orders-api", ahead: 1, current: true),
            worktrees: [copy("wt", "feat/lines", path: "../orders-api-wt/lines", ahead: 2, agents: ["Claude Code"])],
            branches: [
                branch("main", upstream: "origin/main"), branch("feat/lines"), branch("release/1.4"),
                branch("origin/HEAD", remote: true), branch("origin/main", remote: true),
            ])
    }

    @Test func listsWorktreesThenLocalThenRemoteThenTheActions() {
        let entries = GitBranchMenu.entries([repo], compareBase: { _ in "main" }, actions: .init())
        #expect(
            entries.map(\.title) == [
                "Worktrees", "main", "feat/lines", "Local branches", "main", "feat/lines", "release/1.4", "Remote",
                "origin/main", "Fetch", "Pull", "Push", "New branch…", "Stash changes…",
            ])
        #expect(entries.filter(\.isHeader).map(\.title) == ["Worktrees", "Local branches", "Remote"])
        #expect(entries[1].isChecked)
        #expect(entries[1].subtitle == "~/Projects/orders-api \u{00B7} \u{2191}1")
        #expect(entries[2].subtitle == "../orders-api-wt/lines \u{00B7} \u{2191}2 \u{00B7} Claude Code")
        #expect(entries[2].badge == .dot(.green))
        #expect(
            entries[2].children.map(\.title) == [
                "Compare with main", "Check out in main folder", "Reveal in Finder", "Remove worktree…",
            ])
        // The current branch is checked; the one a worktree holds says so.
        #expect(entries[4].isChecked)
        #expect(entries[4].subtitle == "origin/main")
        #expect(entries[5].subtitle == "worktree")
        #expect(entries.first { $0.title == "Push" }?.subtitle == "1 commit")
        #expect(entries.first { $0.title == "Fetch" }?.startsSection == true)
    }

    @Test func aBranchHeldByAWorktreeLeadsToItsChanges() {
        var shown: [String] = []
        var checkedOut: [String] = []
        var actions = GitBranchMenu.Actions()
        actions.showChanges = { shown.append($0) }
        actions.checkout = { branch, _ in checkedOut.append(branch.name) }
        let entries = GitBranchMenu.entries([repo], compareBase: { _ in nil }, actions: actions)
        entries.first { $0.id.hasSuffix("refs/heads/feat/lines") }?.perform()
        entries.first { $0.id.hasSuffix("refs/heads/release/1.4") }?.perform()
        #expect(shown == ["wt"])
        #expect(checkedOut == ["release/1.4"])
    }

    @Test func severalReposGetASubmenuEach() {
        let second = GitBranchMenu.Repo(id: "web", name: "web", main: copy("web", "dev"), worktrees: [], branches: [])
        let entries = GitBranchMenu.entries([repo, second], compareBase: { _ in nil }, actions: .init())
        #expect(entries.map(\.title) == ["orders-api", "web"])
        #expect(entries[1].children.map(\.title) == ["Fetch", "Pull", "Push", "New branch…", "Stash changes…"])
        #expect(entries[1].children.first?.startsSection == false)
    }

    @Test func pathsAreShortenedUnderTheHomeAndBesideTheRepo() {
        let home = URL(filePath: "/Users/me")
        #expect(GitBranchMenu.displayPath(URL(filePath: "/Users/me/p/api"), relativeTo: nil, home: home) == "~/p/api")
        #expect(
            GitBranchMenu.displayPath(
                URL(filePath: "/Users/me/p/api-wt/x"), relativeTo: URL(filePath: "/Users/me/p/api"), home: home)
                == "../api-wt/x")
        #expect(GitBranchMenu.displayPath(URL(filePath: "/opt/x"), relativeTo: nil, home: home) == "/opt/x")
    }

    @Test func theFilterKeepsMatchesAndTheirHeaders() {
        let rows: [ToolbarMenuFilter.Row] = [
            .header, .item(["main", "~/p"]), .item(["feat/lines", "../wt"]), .separator, .header,
            .item(["release/1.4"]), .separator, .item(["Fetch"]),
        ]
        #expect(ToolbarMenuFilter.visibility(of: rows, query: "") == Array(repeating: true, count: 8))
        #expect(
            ToolbarMenuFilter.visibility(of: rows, query: "LINES")
                == [true, false, true, false, false, false, false, false])
        #expect(
            ToolbarMenuFilter.visibility(of: rows, query: "1.4")
                == [false, false, false, false, true, true, false, false])
    }
}
