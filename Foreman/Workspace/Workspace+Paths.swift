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

    nonisolated static func url(forPersistedPath path: String, root: URL) -> URL {
        guard !path.hasPrefix("/") else { return URL(filePath: path) }
        return root.appending(path: path)
    }
}
