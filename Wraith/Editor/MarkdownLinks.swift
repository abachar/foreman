import Foundation

/// editor R14 and security (architecture): where a link or image of a markdown file may go.
nonisolated enum MarkdownLinks {
    enum Target: Equatable {
        /// A file of the workspace: opened in Wraith.
        case file(URL)
        /// `http(s)`/`mailto`: opened in the browser on `cmd+clic`.
        case external(URL)
        /// Anchors, unknown schemes, files outside the workspace.
        case ignored
    }

    static func resolve(_ destination: String, from file: URL, root: URL) -> Target {
        guard !destination.isEmpty, !destination.hasPrefix("#") else { return .ignored }
        if let url = URL(string: destination), let scheme = url.scheme?.lowercased() {
            return ["http", "https", "mailto"].contains(scheme) ? .external(url) : .ignored
        }
        let path = destination.split(separator: "#", maxSplits: 1).first.map(String.init) ?? destination
        let resolved =
            path.hasPrefix("/")
            ? root.appending(path: String(path.dropFirst())) : file.deletingLastPathComponent().appending(path: path)
        return isInside(resolved, root: root) ? .file(resolved.standardizedFileURL) : .ignored
    }

    /// editor R14: local images of the workspace only, never a remote resource.
    static func image(_ source: String, from file: URL, root: URL) -> URL? {
        if case .file(let url) = resolve(source, from: file, root: root) {
            return url
        }
        return nil
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let target = url.standardizedFileURL.path(percentEncoded: false)
        let base = root.standardizedFileURL.path(percentEncoded: false)
        return target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}
