import Foundation

/// Where a `stopped` event leads (debug R5, R12): the decision, apart from the work of doing it.
nonisolated enum StoppedTarget: Equatable, Sendable {
    /// An absolute file — under the root or outside it (editor R64 makes the latter read-only).
    case file(URL)
    /// A `jdt://` URI the language server of the adapter's extension provides (editor R62).
    case library(uri: String)
    /// Nothing to open, and why: the frame is not marked.
    case unavailable(String)

    /// What an adapter's `source` becomes.
    ///
    /// The adapter is untrusted (R12): only a path or a `file:`
    /// URL, and the one scheme M26 serves, are opened.
    static func resolve(_ source: DAPSource?) -> StoppedTarget {
        guard let path = source?.path, !path.isEmpty else { return .unavailable("the frame has no source path") }
        if path.hasPrefix("/") {
            return .file(URL(filePath: path).standardizedFileURL)
        }
        guard let url = URL(string: path), let scheme = url.scheme?.lowercased() else {
            return .unavailable("`\(path)` is not an absolute path")
        }
        switch scheme {
        case "file": return .file(url.standardizedFileURL)
        case "jdt": return .library(uri: path)
        default: return .unavailable("no source for the scheme `\(scheme)`")
        }
    }
}

/// The paused line (debug R5): set by `stopped`, gone on `continued`, `terminated`, `exited` and
/// when the session ends.
nonisolated struct PausedMark: Equatable, Sendable {
    struct Location: Equatable, Sendable {
        var url: URL
        var line: Int
    }

    private(set) var location: Location?

    mutating func stopped(at location: Location) {
        self.location = location
    }

    /// An event of the adapter; only the three that end a stop clear it.
    mutating func handle(event name: String) {
        if ["continued", "terminated", "exited"].contains(name) {
            location = nil
        }
    }

    mutating func clear() {
        location = nil
    }

    /// The line to paint in the file at `url`, if it is the paused one.
    func line(in url: URL) -> Int? {
        location.flatMap { $0.url == url.standardizedFileURL ? $0.line : nil }
    }
}
