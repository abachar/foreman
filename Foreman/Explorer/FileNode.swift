import Foundation

/// One entry of the tree; its identity is its path relative to the workspace root (explorer,
/// technical options).
nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case file
        case directory
        /// explorer R6: shown with its own icon, expandable when it points to a folder, never
        /// followed by a recursive operation.
        case symlink(toDirectory: Bool)
    }

    let relativePath: String
    let kind: Kind
    /// explorer R4: on the shared exclusion list, greyed and never expanded automatically.
    let isExcluded: Bool
    /// explorer, edge cases: a folder without read permission, shown locked.
    let isUnreadable: Bool

    var id: String { relativePath }

    var name: String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }

    var isExpandable: Bool {
        switch kind {
        case .directory, .symlink(toDirectory: true):
            return !isUnreadable
        case .file, .symlink(toDirectory: false):
            return false
        }
    }

    /// explorer R2: folders (and links to folders) before files.
    fileprivate var sortsAsFolder: Bool {
        switch kind {
        case .directory, .symlink(toDirectory: true):
            return true
        case .file, .symlink(toDirectory: false):
            return false
        }
    }
}

/// The content of one folder, read at its first expansion (explorer R7).
nonisolated struct DirectoryLevel: Hashable, Sendable {
    /// explorer R8: a folder with more than this many entries is shown truncated.
    static let limit = 5000

    /// Sorted (R2), filtered (R3), already cut to `limit` when `truncatedCount` is not zero.
    let nodes: [FileNode]
    /// explorer R8: how many entries are not in `nodes`; the user can ask for all of them.
    let truncatedCount: Int

    /// explorer R5: the entries to show, with or without the greyed ones.
    func visibleNodes(hidingExcluded: Bool) -> [FileNode] {
        hidingExcluded ? nodes.filter { !$0.isExcluded } : nodes
    }

    /// Reads one level of `root/relativePath` (`""` for the root itself), never recursively.
    ///
    /// Disk IO: runs off the main actor.
    @concurrent
    static func read(
        _ relativePath: String, root: URL, rootIsHome: Bool, limit: Int? = limit
    ) async throws(ExplorerError) -> DirectoryLevel {
        let folder = relativePath.isEmpty ? root : root.appending(path: relativePath)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isReadableKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys), options: [])
        } catch {
            throw .io(relativePath, underlying: error)
        }
        var nodes: [FileNode] = []
        nodes.reserveCapacity(urls.count)
        for url in urls {
            let name = url.lastPathComponent
            // explorer R3: `.git/`, `.DS_Store`, `.foreman/state.json` and `.foreman/scratches/`
            // (editor R34: Foreman's drafts, not the workspace's files) are not shown at all.
            guard name != ".git", name != ".DS_Store",
                !(relativePath == ".foreman" && (name == "state.json" || name == "scratches"))
            else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            let kind: FileNode.Kind
            if values?.isSymbolicLink == true {
                let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
                kind = .symlink(toDirectory: target?.isDirectory == true)
            } else {
                kind = values?.isDirectory == true ? .directory : .file
            }
            let path = relativePath.isEmpty ? name : relativePath + "/" + name
            nodes.append(
                FileNode(
                    relativePath: path, kind: kind,
                    isExcluded: ExcludedPaths.isExcluded(path, rootIsHome: rootIsHome),
                    isUnreadable: kind != .file && values?.isReadable == false))
        }
        nodes.sort { first, second in
            if first.sortsAsFolder != second.sortsAsFolder {
                return first.sortsAsFolder
            }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
        if let limit, nodes.count > limit {
            return DirectoryLevel(nodes: Array(nodes.prefix(limit)), truncatedCount: nodes.count - limit)
        }
        return DirectoryLevel(nodes: nodes, truncatedCount: 0)
    }
}
