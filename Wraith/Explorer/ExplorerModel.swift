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
    /// explorer R19: the last IO error, shown in the panel until the next successful operation.
    private(set) var error: ExplorerError?

    /// Relative path of the selected row, `nil` without selection.
    var selection: String?
    /// Bumped at every change of `levels`; the outline view reloads `lastLoaded` when it moves.
    private(set) var version = 0
    private(set) var lastLoaded: String?

    private let rootIsHome: Bool
    private var activation: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "explorer")

    init(root: URL) {
        self.root = root
        rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    var persisted: ExplorerState {
        ExplorerState(expanded: expanded.sorted(), hidesExcluded: hidesExcluded)
    }

    func restore(_ state: ExplorerState) {
        expanded = Set(state.expanded)
        hidesExcluded = state.hidesExcluded
    }

    /// explorer R8: the first level is read at activation; layout R4: nothing before.
    func activate() {
        guard levels[""] == nil, activation == nil else { return }
        activation = Task { [weak self] in
            await self?.load("")
            self?.activation = nil
        }
    }

    func deactivate() {
        activation?.cancel()
        activation = nil
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
