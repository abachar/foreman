import Foundation

/// editor R34: the file behind an untitled tab, under `<root>/.foreman/scratches/`.
///
/// A scratch is an ordinary file, so an untitled tab is an ordinary `editor.file` tab: nothing in
/// the tab, its payload or the restoration knows about it. Only the name, the numbering and the
/// two ends of its life (created empty, moved away or deleted) live here.
nonisolated enum Scratch {
    /// config R1: `.foreman/` is Foreman's, created on demand.
    static let relativeFolder = ".foreman/scratches"
    static let baseTitle = "Untitled"

    /// git R6, explorer R3: the folder ignores itself, so a draft never reaches the Changes panel
    /// and the user's own `.gitignore` is left alone (`*` covers this file too, which is what we
    /// want: nothing here is ever committed).
    static let gitignore = "*\n"

    static func folder(root: URL) -> URL {
        root.appending(path: relativeFolder)
    }

    /// Whether a persisted path (config R10) is a scratch of this workspace.
    static func isScratch(path: String) -> Bool {
        path.hasPrefix(relativeFolder + "/") && !path.dropFirst(relativeFolder.count + 1).contains("/")
    }

    /// editor R34: `Untitled`, then `Untitled 2`, `Untitled 3`… the first name `taken` does not hold.
    static func nextTitle(taken: Set<String>) -> String {
        guard taken.contains(baseTitle) else { return baseTitle }
        var number = 2
        while taken.contains("\(baseTitle) \(number)") {
            number += 1
        }
        return "\(baseTitle) \(number)"
    }

    /// editor R34: the folder, its `.gitignore` and an empty file under the first free title.
    @concurrent
    static func create(root: URL) async throws(EditorError) -> URL {
        let folder = folder(root: root)
        let files = FileManager.default
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let ignore = folder.appending(path: ".gitignore")
            if !files.fileExists(atPath: ignore.path(percentEncoded: false)) {
                try Data(gitignore.utf8).write(to: ignore)
            }
            let taken = Set((try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            let url = folder.appending(path: nextTitle(taken: taken))
            try Data().write(to: url, options: .withoutOverwriting)
            return url
        } catch {
            throw .unreadable("\(relativeFolder): \(error.localizedDescription)")
        }
    }

    /// editor R34: the scratch becomes the file the user named.
    ///
    /// An existing destination is replaced: `NSSavePanel` has already asked about it.
    @concurrent
    static func move(_ scratch: URL, to destination: URL) async throws(EditorError) {
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: scratch)
            } else {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: scratch, to: destination)
            }
        } catch {
            throw .unreadable("\(destination.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// editor R34: the scratch goes with its tab; a scratch that was saved away is already gone.
    @concurrent
    static func remove(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }
}
