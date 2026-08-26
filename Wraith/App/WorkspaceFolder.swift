import Foundation

/// Resolution of the folder a window is rooted at.
///
/// One window is exactly one folder (product R1), and `WindowGroup(for: URL.self)` activates an
/// existing window only when the presented value is *equal*: two paths that reach the same
/// directory must therefore produce the same URL. Everything here is pure — the current directory
/// and the home directory are passed in — so it is testable without touching `$HOME`.
nonisolated enum WorkspaceFolder {
    /// Canonical folder designated by `path`, or `home` when no path is given (product R8).
    ///
    /// A leading `~` is expanded against `home`, a relative path is resolved against
    /// `currentDirectory`. A folder that does not exist is returned as it is: the window opens on an
    /// error, it does not silently fall back to another folder.
    static func resolve(path: String?, currentDirectory: URL, home: URL) -> URL {
        guard let path, !path.isEmpty else { return canonical(home) }
        return canonical(absolute(path: path, currentDirectory: currentDirectory, home: home))
    }

    /// The same folder always written the same way: absolute path, relative components removed,
    /// symlinks resolved, trailing slash.
    static func canonical(_ folder: URL) -> URL {
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        return URL(filePath: resolved.path(percentEncoded: false), directoryHint: .isDirectory)
    }

    /// Folder passed on the command line (`Wraith <folder>`), if any.
    ///
    /// Only an argument that looks like a path is considered: Xcode and the system inject flags and
    /// their values (`-NSDocumentRevisionsDebugMode YES`), which are not folders.
    static func argument(in arguments: [String]) -> String? {
        arguments.dropFirst().first { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.hasPrefix(".") }
    }

    private static func absolute(path: String, currentDirectory: URL, home: URL) -> URL {
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home.appending(path: path.dropFirst(2), directoryHint: .isDirectory)
        }
        if path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return currentDirectory.appending(path: path, directoryHint: .isDirectory)
    }
}
