import Foundation

/// git R40 (2026-10-16, M21 21.4): the branch widget's menu, built as a value from the model so
/// its order and its marks are tested without a menu.
enum GitBranchMenu {
    /// One working copy as a menu row reads it.
    struct Copy: Equatable {
        let id: String
        /// The branch, or what `HEAD` is (`detached HEAD @ 1a2b3c4`).
        let head: String
        /// `~/Projects/orders-api`, `../orders-api-wt/order-lines`.
        let path: String
        let ahead: Int
        /// The agents working in the folder, by title; the state of the most urgent one.
        let agents: [String]
        let agentBadge: ToolbarBadge
        /// The working copy last worked in (git R10): the check mark.
        let isCurrent: Bool
        /// git R38: a locked worktree is not removed from here.
        let isLocked: Bool
    }

    /// One top-level repo: its main folder, its worktrees, its branches.
    struct Repo: Equatable {
        let id: String
        let name: String
        let main: Copy
        let worktrees: [Copy]
        let branches: [GitBranch]
    }

    /// What the rows do; each gets the id of the working copy it acts on.
    struct Actions {
        var showChanges: (String) -> Void = { _ in }
        var compare: (String) -> Void = { _ in }
        var checkOutInMain: (String) -> Void = { _ in }
        var reveal: (String) -> Void = { _ in }
        var removeWorktree: (String) -> Void = { _ in }
        var checkout: (GitBranch, String) -> Void = { _, _ in }
        var fetch: (String) -> Void = { _ in }
        var pull: (String) -> Void = { _ in }
        var push: (String) -> Void = { _ in }
        var newBranch: (String) -> Void = { _ in }
        var stash: (String) -> Void = { _ in }
        /// git R40 (amended 2026-10-17): the three entries of M22 22.2.
        var newWorktree: (String) -> Void = { _ in }
        var merge: (String) -> Void = { _ in }
        var openAgent: (_ agent: String, _ copy: String) -> Void = { _, _ in }
    }

    /// An agent of `config.agents` a worktree can be opened in (agents R2).
    struct Agent: Equatable {
        let id: String
        let title: String
    }

    /// One repo: its entries inline; several: one submenu each, named after the repo.
    @MainActor
    static func entries(
        _ repos: [Repo], agents: [Agent] = [], compareBase: (String) -> String?, actions: Actions
    ) -> [ToolbarMenuEntry] {
        guard repos.count > 1 else {
            return repos.first.map { entries(of: $0, agents: agents, compareBase: compareBase, actions: actions) } ?? []
        }
        return repos.map { repo in
            ToolbarMenuEntry(
                id: "git.menu.repo.\(repo.id)", title: repo.name, subtitle: repo.main.head,
                children: entries(of: repo, agents: agents, compareBase: compareBase, actions: actions), perform: {})
        }
    }

    @MainActor
    static func entries(
        of repo: Repo, agents: [Agent] = [], compareBase: (String) -> String?, actions: Actions
    ) -> [ToolbarMenuEntry] {
        var entries: [ToolbarMenuEntry] = []
        // Worktrees: the main folder first, then each worktree with its submenu, then *New worktree…*.
        entries.append(header("Worktrees", in: repo))
        if !repo.worktrees.isEmpty {
            entries.append(row(repo.main, in: repo, actions: actions))
            for copy in repo.worktrees {
                var entry = row(copy, in: repo, actions: actions)
                let base = compareBase(copy.id) ?? repo.main.head
                entry.children =
                    agentEntries(agents, copy: copy, actions: actions) + [
                        ToolbarMenuEntry(
                            id: "git.menu.compare.\(copy.id)", title: "Compare with \(base)",
                            startsSection: !agents.isEmpty
                        ) {
                            actions.compare(copy.id)
                        },
                        ToolbarMenuEntry(id: "git.menu.checkout-main.\(copy.id)", title: "Check out in main folder") {
                            actions.checkOutInMain(copy.id)
                        },
                        ToolbarMenuEntry(id: "git.menu.merge.\(copy.id)", title: "Merge into \(base)…") {
                            actions.merge(copy.id)
                        },
                        ToolbarMenuEntry(
                            id: "git.menu.reveal.\(copy.id)", title: "Reveal in Finder", startsSection: true
                        ) { actions.reveal(copy.id) },
                        ToolbarMenuEntry(
                            id: "git.menu.remove.\(copy.id)", title: "Remove worktree…", isEnabled: !copy.isLocked
                        ) { actions.removeWorktree(copy.id) },
                    ]
                entries.append(entry)
            }
        }
        entries.append(
            ToolbarMenuEntry(id: "git.menu.new-worktree.\(repo.id)", title: "New worktree…") {
                actions.newWorktree(repo.id)
            })
        // Branches: local then remote; a branch another worktree holds says so and leads there.
        let held = Dictionary(
            repo.worktrees.map { ($0.head, $0.id) } + [(repo.main.head, repo.main.id)]
        ) { first, _ in first }
        let local = repo.branches.filter { !$0.isRemote }
        // `refs/remotes/origin/HEAD` reads as a bare `origin`: it is left out by its ref.
        let remote = repo.branches.filter { $0.isRemote && !$0.ref.hasSuffix("/HEAD") }
        if !local.isEmpty {
            var first = header("Local branches", in: repo)
            first.startsSection = !entries.isEmpty
            entries.append(first)
            for branch in local {
                let holder = held[branch.name].flatMap { $0 == repo.main.id ? nil : $0 }
                entries.append(
                    ToolbarMenuEntry(
                        id: "git.menu.branch.\(repo.id).\(branch.ref)", title: branch.name,
                        subtitle: holder != nil ? "worktree" : branch.upstream,
                        isChecked: branch.name == repo.main.head
                    ) {
                        if let holder {
                            actions.showChanges(holder)
                        } else {
                            actions.checkout(branch, repo.id)
                        }
                    })
            }
        }
        if !remote.isEmpty {
            entries.append(header("Remote", in: repo))
            for branch in remote {
                entries.append(
                    ToolbarMenuEntry(id: "git.menu.branch.\(repo.id).\(branch.ref)", title: branch.name) {
                        actions.checkout(branch, repo.id)
                    })
            }
        }
        let ahead = repo.main.ahead
        entries.append(
            ToolbarMenuEntry(id: "git.menu.fetch.\(repo.id)", title: "Fetch", startsSection: !entries.isEmpty) {
                actions.fetch(repo.id)
            })
        entries.append(ToolbarMenuEntry(id: "git.menu.pull.\(repo.id)", title: "Pull") { actions.pull(repo.id) })
        entries.append(
            ToolbarMenuEntry(
                id: "git.menu.push.\(repo.id)", title: "Push",
                subtitle: ahead > 0 ? (ahead == 1 ? "1 commit" : "\(ahead) commits") : nil
            ) { actions.push(repo.id) })
        entries.append(
            ToolbarMenuEntry(id: "git.menu.new-branch.\(repo.id)", title: "New branch…") { actions.newBranch(repo.id) })
        entries.append(
            ToolbarMenuEntry(id: "git.menu.stash.\(repo.id)", title: "Stash changes…") { actions.stash(repo.id) })
        return entries
    }

    /// *Open terminal agent here*: the entry itself with one agent, a submenu with several.
    @MainActor
    private static func agentEntries(_ agents: [Agent], copy: Copy, actions: Actions) -> [ToolbarMenuEntry] {
        guard agents.count > 1 else {
            return agents.map { agent in
                ToolbarMenuEntry(
                    id: "git.menu.agent.\(copy.id).\(agent.id)", title: "Open \(agent.title) here"
                ) { actions.openAgent(agent.id, copy.id) }
            }
        }
        return [
            ToolbarMenuEntry(
                id: "git.menu.agents.\(copy.id)", title: "Open terminal agent here",
                children: agents.map { agent in
                    ToolbarMenuEntry(id: "git.menu.agent.\(copy.id).\(agent.id)", title: agent.title) {
                        actions.openAgent(agent.id, copy.id)
                    }
                }, perform: {})
        ]
    }

    /// git R41 (2026-10-17): the folder a new worktree goes to — beside the repo, in
    /// `<repo>-wt/<branch>` with the branch's slashes turned into dashes (`../orders-api-wt/feat-lines`).
    nonisolated static func worktreeFolder(repo: URL, branch: String) -> URL {
        repo.standardizedFileURL.deletingLastPathComponent()
            .appending(components: "\(repo.lastPathComponent)-wt", branch.replacingOccurrences(of: "/", with: "-"))
    }

    /// git R41: a merge is refused while the main folder holds tracked changes (untracked files
    /// are git's own business: it refuses itself when one would be overwritten).
    nonisolated static func canMerge(into status: GitStatus?) -> Bool {
        guard let status else { return false }
        return status.entries.allSatisfy(\.isUntracked)
    }

    @MainActor
    private static func header(_ title: String, in repo: Repo) -> ToolbarMenuEntry {
        ToolbarMenuEntry(id: "git.menu.header.\(repo.id).\(title)", title: title, isHeader: true, perform: {})
    }

    /// A working copy: its branch, its folder, how far ahead, the agents there; a click shows it
    /// in Changes.
    @MainActor
    private static func row(_ copy: Copy, in repo: Repo, actions: Actions) -> ToolbarMenuEntry {
        let details = [copy.path, copy.ahead > 0 ? "\u{2191}\(copy.ahead)" : nil] + copy.agents.map(Optional.some)
        return ToolbarMenuEntry(
            id: "git.menu.copy.\(copy.id)", title: copy.head,
            subtitle: details.compactMap { $0 }.joined(separator: " \u{00B7} "), badge: copy.agentBadge,
            isChecked: copy.isCurrent
        ) { actions.showChanges(copy.id) }
    }

    /// `~/…` for a folder under the home, `../…` for a worktree beside its repo, else the path.
    nonisolated static func displayPath(_ url: URL, relativeTo top: URL?, home: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        if let top {
            let parent = top.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
                .trimmingSuffix("/")
            if path.hasPrefix(parent + "/") {
                return ".." + path.dropFirst(parent.count)
            }
        }
        let homePath = home.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        if path == homePath || path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}

extension String {
    nonisolated fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}
