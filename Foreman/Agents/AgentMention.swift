import Foundation

/// What a feature sends to the active agent (agents R10a): a path with optional lines, or a
/// literal such as a commit sha.
nonisolated enum AgentMention: Equatable, Sendable {
    case path(URL, lines: ClosedRange<Int>?, isDirectory: Bool)
    case literal(String)
    /// browser R9: a web address, as is (no `@`).
    case url(URL)

    /// agents R10a: `@<path>[:<line>[-<line>]] `, relative to `cwd` when under it; a folder keeps
    /// its trailing `/`; a trailing space, no newline.
    func text(relativeTo cwd: URL) -> String {
        switch self {
        case .literal(let text):
            return "@\(text) "
        case .url(let url):
            return "\(url.absoluteString) "
        case .path(let url, let lines, let isDirectory):
            var path = Self.relativePath(of: url, to: cwd)
            if isDirectory, !path.hasSuffix("/") {
                path += "/"
            }
            switch lines {
            case nil: return "@\(path) "
            case let range? where range.lowerBound == range.upperBound: return "@\(path):\(range.lowerBound) "
            case let range?: return "@\(path):\(range.lowerBound)-\(range.upperBound) "
            }
        }
    }

    private static func relativePath(of url: URL, to cwd: URL) -> String {
        let base = cwd.standardizedFileURL.path(percentEncoded: false)
        let root = base.hasSuffix("/") ? base : base + "/"
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }
}
