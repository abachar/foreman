import Foundation
import Observation

/// git R5: what one `status` tells the other features.
nonisolated struct GitStatusChange: Sendable {
    let repo: GitRepo
    let statuses: [String: GitFileStatus]
}

/// git R4: one `status` at a time per repo; a request during a run is kept, once, for after it.
nonisolated struct RefreshCoalescer: Equatable, Sendable {
    private(set) var running: Set<String> = []
    private(set) var pending: Set<String> = []

    /// `true` when the caller must run the status now.
    mutating func request(_ id: String) -> Bool {
        guard !running.contains(id) else {
            pending.insert(id)
            return false
        }
        running.insert(id)
        return true
    }

    /// `true` when a request arrived during the run and the status must run again.
    mutating func finished(_ id: String) -> Bool {
        running.remove(id)
        return pending.remove(id) != nil
    }
}

/// git R6: the three lists of a section; an entry changed on both sides is in two of them.
nonisolated struct GitSections: Equatable, Sendable {
    var conflicts: [GitStatusEntry] = []
    var staged: [GitStatusEntry] = []
    var changes: [GitStatusEntry] = []

    init(_ entries: [GitStatusEntry]) {
        for entry in entries {
            if entry.isConflict {
                conflicts.append(entry)
                continue
            }
            switch entry.index {
            case .untracked:
                changes.append(entry)
                continue
            case .ignored:
                continue
            case .unmodified:
                break
            case .modified, .typeChanged, .added, .deleted, .renamed, .copied, .unmerged:
                staged.append(entry)
            }
            if entry.worktree != .unmodified {
                changes.append(entry)
            }
        }
    }

    var isEmpty: Bool {
        conflicts.isEmpty && staged.isEmpty && changes.isEmpty
    }
}

/// git R34c: an agent tab as the changes panel shows it, handed over by `agents`.
nonisolated struct GitAgentSession: Equatable, Sendable, Identifiable {
    let id: TabID
    let title: String
    /// The agent's icon, as `IconImage.resolve` reads it.
    let icon: String
    let cwd: URL
    let isRunning: Bool
    /// The tab rang (terminal R7).
    let isMarked: Bool
}

/// git R34b: a top-level repo and its worktrees, as the panel lays them out.
struct GitRepoGroup: Identifiable {
    let top: GitModel.Section
    let children: [GitModel.Section]

    var id: String {
        top.id
    }
}

/// What the changes panel shows (git R2–R4, R6).
@Observable
@MainActor
final class GitModel {
    struct Section: Identifiable {
        var repo: GitRepo
        /// `nil` until the first `status` answers.
        var status: GitStatus?
        var error: GitError?
        var isLoading = false
        /// git R2: persisted.
        var isManuallyCollapsed = false
        /// The last action's failure, until the next successful one (like explorer R19).
        var actionError: GitError?
        /// git R12: persisted until the commit.
        var message = ""
        var isAmending = false
        /// git, edge cases: a slow hook; the view shows the indicator and *Cancel*.
        var isCommitting = false
        /// git R21: the remote operation in progress, shown in the header.
        var remoteOperation: RemoteOperations.Kind?
        /// git R22: shown until the next successful remote operation.
        var authRequired: GitAuthRequired?
        /// git R24: `stash list`, refreshed with the status.
        var stashes: [GitStash] = []
        var isStashListExpanded = false

        var id: String {
            repo.id
        }

        var sections: GitSections {
            GitSections(status?.entries ?? [])
        }

        /// git R2: collapsed by hand, or automatically while there is nothing to show.
        var isCollapsed: Bool {
            Self.isCollapsed(
                manually: isManuallyCollapsed, hasChanges: status.map { !GitSections($0.entries).isEmpty } ?? true)
        }

        nonisolated static func isCollapsed(manually: Bool, hasChanges: Bool) -> Bool {
            manually || !hasChanges
        }
    }

    private(set) var sections: [Section] = []

    /// design R17: the number on the Changes tab — the files every repo would commit.
    var changedFileCount: Int {
        sections.reduce(0) { total, section in
            total + (section.status?.entries.count { $0.index != .ignored } ?? 0)
        }
    }
    /// git R23: the repo whose branch sheet is open, and the list the sheet shows.
    private(set) var branchSheetRepo: String?
    private(set) var branches: [GitBranch] = []
    private(set) var isLoadingBranches = false
    /// git R28: `git` missing or too old; the feature is inert while it is set.
    private(set) var banner: String?
    /// `true` between the panel's activation and the end of repo discovery.
    private(set) var isDiscovering = false
    /// git R34b: the groups folded by hand, by repo id; persisted under that id.
    private(set) var collapsedGroups: Set<String> = []
    /// git R34c: the agent tabs of the window, as `agents` last said.
    private(set) var agentSessions: [GitAgentSession] = []
    /// git R10: the working copy the commit area commits in, as last chosen.
    private var chosenCommitTarget: String?
    /// git R36, agents R5b: the section to scroll to, once.
    private(set) var revealed: String?
    private var restoredCollapsed: Set<String> = []
    private var restoredMessages: [String: String] = [:]

    var persisted: GitState {
        GitState(
            collapsed: (sections.filter(\.isManuallyCollapsed).map { collapseKey($0.id) } + collapsedGroups).sorted(),
            messages: Dictionary(sections.filter { !$0.message.isEmpty }.map { ($0.id, $0.message) }) { first, _ in
                first
            })
    }

    func restore(_ state: GitState) {
        restoredCollapsed = Set(state.collapsed)
        restoredMessages = state.messages
    }

    func setBanner(_ text: String?) {
        banner = text
    }

    func setDiscovering(_ value: Bool) {
        isDiscovering = value
    }

    /// The repos found; a known repo keeps its status and its collapse, a new one starts from the
    /// persisted collapse.
    func setRepos(_ repos: [GitRepo]) {
        let hadChildren = Set(sections.compactMap(\.repo.parent))
        let previous = sections
        sections = repos.map { repo in
            guard var known = previous.first(where: { $0.repo.id == repo.id }) else {
                return Section(
                    repo: repo, isManuallyCollapsed: false, message: restoredMessages[repo.id] ?? "")
            }
            known.repo = repo
            return known
        }
        // git R34b: a working copy's fold is persisted under `<id>#main` once its repo is a group,
        // the group's under the id; both restored the first time they appear.
        for index in sections.indices where !previous.contains(where: { $0.repo.id == sections[index].id }) {
            sections[index].isManuallyCollapsed = restoredCollapsed.contains(collapseKey(sections[index].id))
        }
        for id in Set(sections.compactMap(\.repo.parent)).subtracting(hadChildren)
        where restoredCollapsed.contains(id) {
            collapsedGroups.insert(id)
        }
    }

    /// git R34b: where a working copy's fold is persisted.
    private func collapseKey(_ id: String) -> String {
        sections.contains { $0.repo.parent == id } ? id + "#main" : id
    }

    /// git R34b, R34c: each top-level repo and its children; the children with an agent session
    /// first, then by folder name — the order moves when a session opens or closes, never when an
    /// agent's state changes.
    var groups: [GitRepoGroup] {
        let tops = sections.filter { $0.repo.parent == nil }
        return tops.map { top in
            let children = sections.filter { $0.repo.parent == top.id }
            let busy = Set(agentSessions.compactMap { Self.owner(of: $0.cwd, among: sections.map(\.repo)) })
            return GitRepoGroup(
                top: top, children: children.filter { busy.contains($0.id) } + children.filter { !busy.contains($0.id) }
            )
        }
    }

    /// git R10 (amended 2026-10-16): the working copy last worked in; else the first one with
    /// something staged; else the first one.
    var commitTarget: Section? {
        chosenCommitTarget.flatMap(section) ?? sections.first { !$0.sections.staged.isEmpty } ?? sections.first
    }

    func setCommitTarget(_ id: String) {
        guard chosenCommitTarget != id else { return }
        chosenCommitTarget = id
    }

    func children(of id: String) -> [Section] {
        sections.filter { $0.repo.parent == id }
    }

    func isGroupCollapsed(_ id: String) -> Bool {
        collapsedGroups.contains(id)
    }

    func toggleGroupCollapsed(_ id: String) {
        if collapsedGroups.remove(id) == nil {
            collapsedGroups.insert(id)
        }
    }

    // MARK: - Agents (git R34c)

    func setAgentSessions(_ sessions: [GitAgentSession]) {
        guard sessions != agentSessions else { return }
        agentSessions = sessions
    }

    /// git R34c: the sessions running in the working copy `id`, by title.
    func agentSessions(in id: String) -> [GitAgentSession] {
        let repos = sections.map(\.repo)
        return agentSessions.filter { Self.owner(of: $0.cwd, among: repos) == id }
    }

    /// git R34c: the working copy whose folder contains `cwd`, the deepest one.
    nonisolated static func owner(of cwd: URL, among repos: [GitRepo]) -> String? {
        let path = GitRepo.canonicalPath(cwd)
        return repos.map { ($0.id, GitRepo.canonicalPath($0.url)) }
            .filter { path == $0.1 || path.hasPrefix($0.1 + "/") }
            .max { $0.1.count < $1.1.count }?.0
    }

    // MARK: - Reveal (git R36, agents R5b)

    /// The section opened — its group too — and scrolled to by the panel.
    func reveal(_ id: String) {
        guard let section = section(id) else { return }
        if let parent = section.repo.parent {
            collapsedGroups.remove(parent)
        } else if !children(of: id).isEmpty {
            collapsedGroups.remove(id)
        }
        update(id) { $0.isManuallyCollapsed = false }
        revealed = id
    }

    func clearRevealed() {
        revealed = nil
    }

    func section(_ id: String) -> Section? {
        sections.first { $0.id == id }
    }

    private func update(_ id: String, _ change: (inout Section) -> Void) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        change(&sections[index])
    }

    func setLoading(_ id: String, _ value: Bool) {
        update(id) { $0.isLoading = value }
    }

    func setStatus(_ id: String, _ status: GitStatus) {
        update(id) {
            $0.status = status
            $0.error = nil
        }
    }

    /// git, edge cases and "To decide": the section stays, with the reason, never removed silently.
    func setError(_ id: String, _ error: GitError) {
        update(id) { $0.error = error }
    }

    func setActionError(_ id: String, _ error: GitError?) {
        update(id) { $0.actionError = error }
    }

    func toggleCollapsed(_ id: String) {
        update(id) { $0.isManuallyCollapsed.toggle() }
    }

    func setMessage(_ id: String, _ message: String) {
        update(id) { $0.message = message }
    }

    func setAmending(_ id: String, _ value: Bool) {
        update(id) { $0.isAmending = value }
    }

    func setCommitting(_ id: String, _ value: Bool) {
        update(id) { $0.isCommitting = value }
    }

    func setRemoteOperation(_ id: String, _ kind: RemoteOperations.Kind?) {
        update(id) { $0.remoteOperation = kind }
    }

    func setAuthRequired(_ id: String, _ value: GitAuthRequired?) {
        update(id) { $0.authRequired = value }
    }

    /// git R40: each top-level repo's branches, read with its status, for the branch menu.
    private(set) var refs: [String: [GitBranch]] = [:]

    func setRefs(_ id: String, _ branches: [GitBranch]) {
        guard refs[id] != branches else { return }
        refs[id] = branches
    }

    func setStashes(_ id: String, _ stashes: [GitStash]) {
        update(id) { $0.stashes = stashes }
    }

    func toggleStashList(_ id: String) {
        update(id) { $0.isStashListExpanded.toggle() }
    }

    // MARK: - Branch sheet (git R23)

    /// Opens the sheet on `id` with an empty list to load, or closes it with `nil`.
    func setBranchSheet(_ id: String?) {
        branchSheetRepo = id
        branches = []
        isLoadingBranches = id != nil
    }

    func setBranches(_ branches: [GitBranch]) {
        self.branches = branches
        isLoadingBranches = false
    }

    // MARK: - Refresh (git R4)

    /// `.git/` files whose change means a new status; everything else under `.git/` is noise.
    private nonisolated static let gitDirectoryFiles: Set<String> = [
        "HEAD", "ORIG_HEAD", "MERGE_HEAD", "CHERRY_PICK_HEAD", "index", "packed-refs",
    ]
    private nonisolated static let gitDirectoryFolders = ["refs/", "rebase-merge/", "rebase-apply/"]

    /// git R4: the repos one batch of changed paths touches.
    ///
    /// A path belongs to the deepest repo containing it; under `.git/` only `HEAD`, `index`,
    /// `refs/`, `MERGE_HEAD` and the like count, and never a `.lock`; the shared exclusions
    /// (`.git/objects`, `state.json`…) are skipped. `gitDirectories` are the git folders that live
    /// outside their repo (worktrees): a path in one belongs to that repo, not to the repo the
    /// folder sits in.
    nonisolated static func reposToRefresh(
        _ changes: [URL], repos: [GitRepo], gitDirectories: [String: URL], root: URL
    ) -> Set<String> {
        var result: Set<String> = []
        let repoPaths = repos.map { ($0.id, folderPath($0.url)) }
        for url in changes {
            let path = folderPath(url)
            guard !ExcludedPaths.isExcluded(Workspace.persistedPath(for: url, root: root)) else { continue }
            if let (id, directory) = gitDirectories.first(where: { isUnder(path, folderPath($0.value)) }) {
                let directoryPath = folderPath(directory)
                if isRelevant(inGitDirectory: String(path.dropFirst(directoryPath.count + 1))) {
                    result.insert(id)
                }
                continue
            }
            guard let (id, repoPath) = repoPaths.filter({ isUnder(path, $0.1) }).max(by: { $0.1.count < $1.1.count })
            else { continue }
            let gitEntry = repoPath + "/.git"
            if isUnder(path, gitEntry), path != gitEntry {
                if isRelevant(inGitDirectory: String(path.dropFirst(gitEntry.count + 1))) {
                    result.insert(id)
                }
            } else {
                result.insert(id)
            }
        }
        return result
    }

    /// `URL.path()` ends an existing directory with `/`; prefixes compare without it.
    /// git R35: the repos whose `worktree list` must be read again — a worktree added, removed,
    /// locked or unlocked shows as `<common>/worktrees/<name>` or its `locked` file.
    nonisolated static func reposToRediscover(_ changes: [URL], commonDirectories: [String: URL]) -> Set<String> {
        var result: Set<String> = []
        for url in changes {
            let path = folderPath(url)
            for (id, common) in commonDirectories {
                let worktrees = folderPath(common) + "/worktrees"
                guard isUnder(path, worktrees) else { continue }
                let relative = path.dropFirst(worktrees.count).split(separator: "/")
                if relative.count <= 1 || (relative.count == 2 && relative[1] == "locked") {
                    result.insert(id)
                }
            }
        }
        return result
    }

    private nonisolated static func folderPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private nonisolated static func isUnder(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    private nonisolated static func isRelevant(inGitDirectory relative: String) -> Bool {
        guard !relative.hasSuffix(".lock") else { return false }
        return gitDirectoryFiles.contains(relative) || gitDirectoryFolders.contains { relative.hasPrefix($0) }
    }
}
