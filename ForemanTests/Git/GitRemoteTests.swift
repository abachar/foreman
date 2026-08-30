import Foundation
import Testing

@testable import Foreman

/// Remote, branches and stash: arguments, parsers, the one-at-a-time machine (git R21–R24, R27).
struct GitRemoteTests {
    @Test func remoteArguments() {
        #expect(GitCommand.fetch == ["fetch", "--prune"])
        #expect(GitCommand.pull == ["pull"])
        #expect(GitCommand.push(branch: "main", hasUpstream: true) == ["push"])
        #expect(GitCommand.push(branch: "feat/x", hasUpstream: false) == ["push", "-u", "origin", "feat/x"])
        #expect(!GitCommand.push(branch: "x", hasUpstream: false).contains { $0.contains("force") })
    }

    @Test func branchArguments() {
        let local = GitBranch(name: "feat/x", ref: "refs/heads/feat/x", upstream: nil, isCurrent: false)
        let remote = GitBranch(
            name: "origin/feat/y", ref: "refs/remotes/origin/feat/y", upstream: nil, isCurrent: false)
        #expect(GitCommand.checkout(local) == ["switch", "feat/x"])
        #expect(GitCommand.checkout(remote) == ["checkout", "--track", "origin/feat/y"])
        #expect(GitCommand.newBranch("n") == ["switch", "-c", "n"])
        #expect(GitCommand.renameBranch("a", to: "b") == ["branch", "-m", "a", "b"])
        #expect(GitCommand.deleteBranch("a", force: false) == ["branch", "-d", "a"])
        #expect(GitCommand.deleteBranch("a", force: true) == ["branch", "-D", "a"])
        #expect(GitCommand.setUpstream(of: "a", to: "origin/a") == ["branch", "--set-upstream-to=origin/a", "a"])
    }

    @Test func stashArguments() {
        #expect(GitCommand.stashPush(message: nil, includeUntracked: false) == ["stash", "push"])
        #expect(GitCommand.stashPush(message: "", includeUntracked: true) == ["stash", "push", "--include-untracked"])
        #expect(GitCommand.stashPush(message: "wip", includeUntracked: false) == ["stash", "push", "-m", "wip"])
        #expect(GitCommand.stash(.pop, "stash@{1}") == ["stash", "pop", "stash@{1}"])
        #expect(GitCommand.stash(.drop, "stash@{0}") == ["stash", "drop", "stash@{0}"])
    }

    @Test func parsesForEachRefAndStashList() {
        let refs = [
            "refs/heads/main\u{1f}main\u{1f}origin/main\u{1f}*", "refs/heads/feat/x\u{1f}feat/x\u{1f}\u{1f} ",
            "refs/remotes/origin/HEAD\u{1f}origin/HEAD\u{1f}\u{1f} ",
            "refs/remotes/origin/main\u{1f}origin/main\u{1f}\u{1f} ",
        ].joined(separator: "\n")
        let branches = RefParser.branches(Data(refs.utf8))
        #expect(branches.map(\.name) == ["main", "feat/x", "origin/main"])
        #expect(branches[0].isCurrent)
        #expect(branches[0].upstream == "origin/main")
        #expect(branches[1].upstream == nil)
        #expect(branches[2].isRemote)
        #expect(!branches[1].isRemote)
        #expect(RefParser.branches(Data()).isEmpty)

        // Bytes of `git stash list --format=<stashFormat>` on a repo with three stashes (git 2.43); the
        // first was pushed with a message holding the separator itself, which git passes through.
        let list = "stash@{0}\u{1f}On main: odd\u{1f}msg\nstash@{1}\u{1f}WIP on main: aa177fd first\n"
        let stashes = RefParser.stashes(Data((list + "stash@{2}\u{1f}On main: wip one\n").utf8))
        #expect(stashes.map(\.ref) == ["stash@{0}", "stash@{1}", "stash@{2}"])
        #expect(stashes[0].message == "On main: odd\u{1f}msg")
        #expect(stashes[2].message == "On main: wip one")
        #expect(RefParser.stashes(Data("garbage".utf8)).isEmpty)
    }

    /// `stash list` runs the pretty machinery, which prints `%1f` verbatim: only `%x1f` yields a separator.
    @Test func theStashFormatAsksForAnEscapedSeparator() {
        #expect(RefParser.stashFormat == "%gd%x1f%s")
        // What git 2.43 emitted for a stash when the format asked for `%1f` instead.
        #expect(RefParser.stashes(Data("stash@{0}%1fWIP on main: aa177fd first\n".utf8)).isEmpty)
    }

    @Test func oneRemoteOperationAtATimePerRepo() {
        var operations = RemoteOperations()
        let first = operations.start(.fetch, in: ".")
        let second = operations.start(.push, in: ".")
        let other = operations.start(.pull, in: "libs")
        #expect(first)
        #expect(!second)
        #expect(other)
        #expect(operations.current(in: ".") == .fetch)
        operations.finish(".")
        #expect(operations.current(in: ".") == nil)
        let again = operations.start(.push, in: ".")
        #expect(again)
    }

    @Test func theAuthBannerNamesTheCommandAndTheFolderAndNothingElse() {
        let auth = GitAuthRequired(arguments: ["push", "-u", "origin", "main"], cwd: URL(filePath: "/work/repo"))
        #expect(auth.command == "git push -u origin main")
        #expect(auth.copyText == "cd /work/repo && git push -u origin main")
    }

    /// git R22: the banner's command is pasted into a shell; a name holding shell syntax must run
    /// as the name it is.
    @Test func theCommandQuotesAnArgumentTheShellWouldReadAsCode() {
        let auth = GitAuthRequired(
            arguments: ["push", "-u", "origin", "feat/x; rm -rf ~"], cwd: URL(filePath: "/work/my repo"))
        #expect(auth.command == "git push -u origin 'feat/x; rm -rf ~'")
        #expect(auth.copyText == "cd '/work/my repo' && git push -u origin 'feat/x; rm -rf ~'")
        let apostrophe = GitAuthRequired(arguments: ["stash", "push", "-m", "it's a wip"], cwd: URL(filePath: "/w"))
        #expect(apostrophe.command == #"git stash push -m 'it'\''s a wip'"#)
        #expect(GitAuthRequired.quoted("") == "''")
        #expect(GitAuthRequired.quoted("--set-upstream-to=origin/feat/x") == "--set-upstream-to=origin/feat/x")
    }

    @Test func theBranchSheetFiltersCaseInsensitively() {
        let branches = [
            GitBranch(name: "main", ref: "refs/heads/main", upstream: nil, isCurrent: true),
            GitBranch(name: "feat/Login", ref: "refs/heads/feat/Login", upstream: nil, isCurrent: false),
        ]
        #expect(GitBranchesSheet.filter(branches, query: "LOG").map(\.name) == ["feat/Login"])
        #expect(GitBranchesSheet.filter(branches, query: " ").count == 2)
    }
}
