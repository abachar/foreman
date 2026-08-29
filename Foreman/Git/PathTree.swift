import Foundation

/// git R6b: the paths of one group of the Changes panel as a tree.
///
/// A folder whose only child is a folder is folded into one row (`src/main/java`), as IntelliJ
/// does. Everything is expanded and nothing is persisted (decision 2026-08-30), so there is no
/// disclosure state to hold: the tree comes out already flattened, one row per folder and one per
/// file, each with the depth it is drawn at.
nonisolated enum PathTree {
    /// A row of the flattened tree.
    ///
    /// A folder row carries no action (R6b).
    enum Row: Equatable, Identifiable {
        /// `path` is the whole chain from the repo, `label` only what the row shows.
        case folder(path: String, label: String, depth: Int)
        case file(GitStatusEntry, depth: Int)

        var id: String {
            switch self {
            case .folder(let path, _, _): return "folder:\(path)"
            case .file(let entry, _): return "file:\(entry.path)"
            }
        }

        var depth: Int {
            switch self {
            case .folder(_, _, let depth), .file(_, let depth): return depth
            }
        }
    }

    /// The rows of `entries`, folders first then names in `localizedStandardCompare` order.
    ///
    /// The order is the explorer's (`explorer` R2). A rename stays one row, at its new path: only
    /// `path` ever builds the tree. `collapsed` holds the folded paths whose children are hidden;
    /// a collapsed folder still gets its row.
    static func rows(of entries: [GitStatusEntry], collapsed: Set<String> = []) -> [Row] {
        let root = Folder()
        for entry in entries {
            var folder = root
            for name in entry.path.split(separator: "/").dropLast() {
                folder = folder.child(String(name))
            }
            folder.files.append(entry)
        }
        var rows: [Row] = []
        emit(root, prefix: "", depth: 0, collapsed: collapsed, into: &rows)
        return rows
    }

    private static func emit(
        _ folder: Folder, prefix: String, depth: Int, collapsed: Set<String>, into rows: inout [Row]
    ) {
        for name in folder.folders.keys.sorted(by: isBefore) {
            guard var child = folder.folders[name] else { continue }
            var label = name
            // R6b: a folder whose only child is a folder joins it on the same row.
            while child.files.isEmpty, child.folders.count == 1, let only = child.folders.first {
                label += "/" + only.key
                child = only.value
            }
            let path = prefix + label
            rows.append(.folder(path: path, label: label, depth: depth))
            guard !collapsed.contains(path) else { continue }
            emit(child, prefix: path + "/", depth: depth + 1, collapsed: collapsed, into: &rows)
        }
        for entry in folder.files.sorted(by: { isBefore($0.path, $1.path) }) {
            rows.append(.file(entry, depth: depth))
        }
    }

    private static func isBefore(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    /// Only alive while `rows(of:)` builds; the rows that come out are values.
    private final class Folder {
        var folders: [String: Folder] = [:]
        var files: [GitStatusEntry] = []

        func child(_ name: String) -> Folder {
            if let existing = folders[name] {
                return existing
            }
            let folder = Folder()
            folders[name] = folder
            return folder
        }
    }
}
