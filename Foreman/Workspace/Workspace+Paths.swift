import Foundation

/// config R10: paths in `state.json` are relative to the root when inside it, absolute otherwise.
extension Workspace {
    nonisolated static func persistedPath(for url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= rootComponents.count, components.prefix(rootComponents.count) == rootComponents[...]
        else {
            return url.standardizedFileURL.path(percentEncoded: false)
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// The URL of a persisted or configured path; `nil` when a relative path escapes the root.
    ///
    /// architecture, security: a relative path comes from `state.json` or `config.json`, which a
    /// cloned repository can ship, so it must stay under the workspace root. An absolute path is
    /// outside the root by construction (config R10) and passes through as it is.
    nonisolated static func url(forPersistedPath path: String, root: URL) -> URL? {
        guard !path.hasPrefix("/") else { return URL(filePath: path) }
        let url = root.appending(path: path).standardizedFileURL
        guard contains(url, under: root) else { return nil }
        return url
    }

    /// Whether `url` is `root` itself or below it, comparing standardized paths.
    ///
    /// Symlinks are not resolved: the check catches `..` escapes before touching the disk, it does
    /// not vouch for what the path points at.
    nonisolated static func contains(_ url: URL, under root: URL) -> Bool {
        let rootPath = normalizedPath(root)
        let path = normalizedPath(url)
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    /// The standardized path without its trailing slash, so `/code` never contains `/codex`.
    private nonisolated static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
