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
