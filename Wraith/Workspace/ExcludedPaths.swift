import Foundation

/// The single on-disk exclusion list (architecture: persisted formats).
///
/// What no feature scans, indexes or expands by itself. Paths are relative to the workspace root,
/// `/`-separated.
nonisolated enum ExcludedPaths {
    /// Folder names excluded wherever they appear.
    private static let folderNames: Set<String> = ["node_modules", "target", ".build"]

    /// Exact relative paths excluded.
    private static let exactPaths: Set<String> = [".git/objects", ".wraith/state.json", ".DS_Store"]

    /// `~/Library` when the workspace is the home folder (explorer, edge cases).
    static func isExcluded(_ relativePath: String, rootIsHome: Bool = false) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }
        if components.contains(where: { folderNames.contains($0) || $0 == ".DS_Store" }) {
            return true
        }
        if rootIsHome, components[0] == "Library" {
            return true
        }
        return exactPaths.contains {
            let path = components.joined(separator: "/")
            return path == $0 || path.hasPrefix($0 + "/")
        }
    }
}
