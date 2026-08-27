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

/// What the changes panel shows (git R2–R4, R6).
@Observable
@MainActor
final class GitModel {
    struct Section: Identifiable {
        let repo: GitRepo
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
    /// git R28: `git` missing or too old; the feature is inert while it is set.
    private(set) var banner: String?
    /// `true` between the panel's activation and the end of repo discovery.
    private(set) var isDiscovering = false
    private var restoredCollapsed: Set<String> = []
    private var restoredMessages: [String: String] = [:]

    var persisted: GitState {
        GitState(
            collapsed: sections.filter(\.isManuallyCollapsed).map(\.id).sorted(),
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
        sections = repos.map { repo in
            sections.first { $0.repo == repo }
                ?? Section(
                    repo: repo, isManuallyCollapsed: restoredCollapsed.contains(repo.id),
                    message: restoredMessages[repo.id] ?? "")
        }
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
