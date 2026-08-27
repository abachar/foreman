import Foundation
import Observation
import os

/// What the tree shows (explorer, technical options).
///
/// The levels read so far, the expanded folders, the toggles. Views read it; the panel drives
/// the loads.
@Observable
@MainActor
final class ExplorerModel {
    let root: URL
    private(set) var levels: [String: DirectoryLevel] = [:]
    private(set) var loading: Set<String> = []
    /// explorer R11: relative paths, persisted.
    var expanded: Set<String> = []
    /// explorer R5: persisted.
    var hidesExcluded = false
    /// explorer R14: persisted.
    var followsActiveTab = true
    /// explorer R14: the file the tree must expand to and select; consumed by the outline view.
    var revealRequest: String?
    /// explorer R19: the last IO error, shown in the panel until the next successful operation.
    private(set) var error: ExplorerError?

    /// Relative path of the selected row, `nil` without selection.
    var selection: String?
    /// Bumped at every change of `levels`; the outline view reloads `lastLoaded` when it moves.
    private(set) var version = 0
    private(set) var lastLoaded: String?

    /// explorer R15: root-relative file path → status, from `Git.statusChanges`.
    private(set) var gitStatuses: [String: GitFileStatus] = [:]
    /// explorer R15: the status propagated onto the ancestor folders.
    private(set) var folderStatuses: [String: GitFileStatus] = [:]
    /// explorer R4: root-relative paths git ignores (files, or folders as `--ignored=matching` lists them).
    private(set) var ignoredPaths: Set<String> = []
    private var gitWatch: Task<Void, Never>?

    private let rootIsHome: Bool
    private let fsWatch: FSWatchService?
    private var activation: Task<Void, Never>?
    private var watch: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "explorer")

    init(root: URL, fsWatch: FSWatchService? = nil) {
        self.root = root
        self.fsWatch = fsWatch
        rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    isolated deinit {
        activation?.cancel()
        watch?.cancel()
        gitWatch?.cancel()
    }

    var persisted: ExplorerState {
        ExplorerState(expanded: expanded.sorted(), hidesExcluded: hidesExcluded, followsActiveTab: followsActiveTab)
    }

    func restore(_ state: ExplorerState) {
        expanded = Set(state.expanded)
        hidesExcluded = state.hidesExcluded
        followsActiveTab = state.followsActiveTab
    }

    /// explorer R14: the folders to expand, root first, to reach `path`; `nil` outside the root.
    nonisolated static func foldersToExpand(toReach path: String) -> [String]? {
        guard !path.hasPrefix("/"), !path.isEmpty else { return nil }
        let components = path.split(separator: "/").dropLast()
        return components.indices.map { components[...$0].joined(separator: "/") }
    }

    /// explorer R8: the first level is read at activation; layout R4: nothing before.
    ///
    /// explorer R9: the FSEvents subscription lives while the panel is shown; on a second
    /// activation the folders still expanded are read again once.
    func activate() {
        guard activation == nil else { return }
        let known = levels.keys.sorted()
        activation = Task { [weak self] in
            for folder in known.isEmpty ? [""] : known {
                await self?.load(folder)
            }
            self?.activation = nil
        }
        guard let fsWatch, watch == nil else { return }
        watch = Task { [weak self, root] in
            for await batch in await fsWatch.changes(under: root) {
                guard let self else { return }
                for folder in Self.foldersToReload(batch, root: root, loaded: Set(self.levels.keys)).sorted() {
                    await self.load(folder)
                }
            }
        }
    }

    func deactivate() {
        activation?.cancel()
        activation = nil
        watch?.cancel()
        watch = nil
    }

    // MARK: - Git (explorer R4, R15)

    /// explorer R15: the tree follows every status; outside a repo nothing changes.
    func watchGit(_ changes: AsyncStream<GitStatusChange>) {
        gitWatch?.cancel()
        gitWatch = Task { [weak self] in
            for await change in changes {
                self?.applyGitStatus(change)
            }
        }
    }

    /// One repo's table replaces what that repo said before; the others are kept.
    func applyGitStatus(_ change: GitStatusChange) {
        let prefix = change.repo.id == "." ? "" : change.repo.id + "/"
        let repoPath = Workspace.persistedPath(for: change.repo.url, root: root)
        guard !repoPath.hasPrefix("/") else { return }
        gitStatuses = gitStatuses.filter { !Self.belongs($0.key, toRepoWithPrefix: prefix) }
        ignoredPaths = ignoredPaths.filter { !Self.belongs($0, toRepoWithPrefix: prefix) }
        for (path, status) in change.statuses {
            let rootPath = prefix + (path.hasSuffix("/") ? String(path.dropLast()) : path)
            if status == .ignored {
                ignoredPaths.insert(rootPath)
            } else {
                gitStatuses[rootPath] = status
            }
        }
        folderStatuses = Self.propagate(gitStatuses)
        version += 1
        lastLoaded = nil
    }

    private nonisolated static func belongs(_ path: String, toRepoWithPrefix prefix: String) -> Bool {
        prefix.isEmpty || path.hasPrefix(prefix)
    }

    /// explorer R15: each ancestor folder carries the strongest status below it; ignored never
    /// propagates.
    nonisolated static func propagate(_ statuses: [String: GitFileStatus]) -> [String: GitFileStatus] {
        var folders: [String: GitFileStatus] = [:]
        for (path, status) in statuses where status != .ignored {
            let components = path.split(separator: "/").dropLast()
            for end in components.indices {
                let folder = components[...end].joined(separator: "/")
                if let current = folders[folder], rank(current) >= rank(status) { continue }
                folders[folder] = status
            }
        }
        return folders
    }

    private nonisolated static func rank(_ status: GitFileStatus) -> Int {
        switch status {
        case .conflicted: return 4
        case .modified, .deleted, .renamed: return 3
        case .added, .untracked: return 2
        case .ignored: return 0
        }
    }

    /// explorer R15: the status a row shows, `nil` outside a repo or for a clean entry.
    func gitStatus(of node: FileNode) -> GitFileStatus? {
        node.kind == .directory ? folderStatuses[node.relativePath] : gitStatuses[node.relativePath]
    }

    /// explorer R4: the entry or one of its ancestors is gitignored.
    func isGitIgnored(_ relativePath: String) -> Bool {
        Self.isIgnored(relativePath, in: ignoredPaths)
    }

    nonisolated static func isIgnored(_ relativePath: String, in ignored: Set<String>) -> Bool {
        var path = Substring(relativePath)
        while !path.isEmpty {
            if ignored.contains(String(path)) {
                return true
            }
            guard let slash = path.lastIndex(of: "/") else { return false }
            path = path[..<slash]
        }
        return false
    }

    /// explorer R9: the loaded folders one batch of changed paths makes the explorer read again.
    ///
    /// The parent of each path, and the path itself when it is a loaded folder. Anything outside
    /// the root or under a folder not read yet is ignored (a collapsed folder is read at expansion).
    nonisolated static func foldersToReload(_ changes: [URL], root: URL, loaded: Set<String>) -> Set<String> {
        var folders: Set<String> = []
        for url in changes {
            let path = Workspace.persistedPath(for: url, root: root)
            guard !path.hasPrefix("/") else { continue }
            if loaded.contains(path) {
                folders.insert(path)
            }
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            if loaded.contains(parent) {
                folders.insert(parent)
            }
        }
        return folders
    }

    func level(_ relativePath: String) -> DirectoryLevel? {
        levels[relativePath]
    }

    /// explorer R5: the entries of a loaded folder, `nil` while it is not read yet.
    func children(of relativePath: String) -> [FileNode]? {
        levels[relativePath]?.visibleNodes(hidingExcluded: hidesExcluded)
    }

    /// Reads (or re-reads) one folder, off the main actor.
    ///
    /// `all` lifts the 5 000 entries cap (explorer R8). Concurrent calls for the same folder are
    /// collapsed into the first one.
    func load(_ relativePath: String, all: Bool = false) async {
        guard !loading.contains(relativePath) else { return }
        loading.insert(relativePath)
        defer { loading.remove(relativePath) }
        do {
            let level = try await DirectoryLevel.read(
                relativePath, root: root, rootIsHome: rootIsHome, limit: all ? nil : DirectoryLevel.limit)
            levels[relativePath] = level
            lastLoaded = relativePath
            version += 1
            error = nil
        } catch {
            logger.error("folder not read: \(error.description, privacy: .private)")
            self.error = error
        }
    }

    /// explorer R19: an operation failed; shown in the panel, the tree untouched.
    func report(_ error: any Error) {
        self.error = error as? ExplorerError ?? .io("operation", underlying: error)
    }

    /// The node at `relativePath`, when its parent level is loaded.
    func node(at relativePath: String) -> FileNode? {
        let parent = relativePath.split(separator: "/").dropLast().joined(separator: "/")
        return levels[parent]?.nodes.first { $0.relativePath == relativePath }
    }

    /// explorer R9: a collapsed folder is read again at its next expansion.
    func forget(_ relativePath: String) {
        guard levels.removeValue(forKey: relativePath) != nil else { return }
        lastLoaded = relativePath
        version += 1
    }

    /// explorer R11: a persisted folder opens again once shown, a greyed one never does.
    func isRestoredExpanded(_ node: FileNode) -> Bool {
        node.isExpandable && !node.isExcluded && expanded.contains(node.id)
    }

    func setExpanded(_ relativePath: String, _ isExpanded: Bool) {
        if isExpanded {
            expanded.insert(relativePath)
        } else {
            expanded.remove(relativePath)
        }
    }
}
