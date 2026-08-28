import Foundation

/// explorer R16–R19: the file operations, validated, always under the root.
nonisolated enum ExplorerOperations {
    /// explorer R19: what a name may be. `allowsSlash` is for creation, where `a/b/c.txt` makes
    /// the intermediate folders.
    static func isValidName(_ name: String, allowsSlash: Bool) -> Bool {
        let components =
            allowsSlash ? name.split(separator: "/", omittingEmptySubsequences: false).map(String.init) : [name]
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("/")
                && !component.contains(":") && !component.unicodeScalars.contains { $0.value == 0 }
        }
    }

    /// explorer R19 and security: `url` is the root or below it.
    static func isInside(_ url: URL, root: URL) -> Bool {
        let target = url.standardizedFileURL.path(percentEncoded: false)
        let base = root.standardizedFileURL.path(percentEncoded: false)
        return target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// explorer R16: the folder a new entry goes to — the selected folder, the parent of the
    /// selected file, or the root.
    static func targetFolder(forSelection selection: FileNode?, root: URL) -> URL {
        guard let selection else { return root }
        let url = root.appending(path: selection.relativePath)
        return selection.isExpandable || selection.kind == .directory ? url : url.deletingLastPathComponent()
    }

    /// explorer R16: creates the file (and its intermediate folders) and returns its URL.
    @concurrent
    static func createFile(named name: String, in folder: URL, root: URL) async throws(ExplorerError) -> URL {
        let url = try destination(name, in: folder, root: root, allowsSlash: true)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw ExplorerError.io(name, underlying: CocoaError(.fileWriteFileExists))
            }
            try Data().write(to: url, options: .withoutOverwriting)
        } catch let error as ExplorerError {
            throw error
        } catch {
            throw .io(name, underlying: error)
        }
        return url
    }

    @concurrent
    static func createFolder(named name: String, in folder: URL, root: URL) async throws(ExplorerError) -> URL {
        let url = try destination(name, in: folder, root: root, allowsSlash: true)
        do {
            guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw ExplorerError.io(name, underlying: CocoaError(.fileWriteFileExists))
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch let error as ExplorerError {
            throw error
        } catch {
            throw .io(name, underlying: error)
        }
        return url
    }

    /// explorer R17 and edge cases: a rename that only changes the case goes through a temporary
    /// name, APFS being case-insensitive by default.
    @concurrent
    static func rename(_ url: URL, to name: String, root: URL) async throws(ExplorerError) -> URL {
        let target = try destination(name, in: url.deletingLastPathComponent(), root: root, allowsSlash: false)
        guard isInside(url, root: root) else { throw .io(name, underlying: CocoaError(.fileWriteNoPermission)) }
        let fileManager = FileManager.default
        do {
            if url.lastPathComponent.lowercased() == name.lowercased(), url.lastPathComponent != name {
                let temporary = url.deletingLastPathComponent().appending(path: ".\(name).foreman-rename")
                try fileManager.moveItem(at: url, to: temporary)
                try fileManager.moveItem(at: temporary, to: target)
            } else {
                guard !fileManager.fileExists(atPath: target.path(percentEncoded: false)) else {
                    throw ExplorerError.io(name, underlying: CocoaError(.fileWriteFileExists))
                }
                try fileManager.moveItem(at: url, to: target)
            }
        } catch let error as ExplorerError {
            throw error
        } catch {
            throw .io(name, underlying: error)
        }
        return target
    }

    /// explorer R18: to the Trash, never deleted for good.
    @concurrent
    static func trash(_ url: URL, root: URL) async throws(ExplorerError) {
        guard isInside(url, root: root), url.standardizedFileURL != root.standardizedFileURL else {
            throw .io(url.lastPathComponent, underlying: CocoaError(.fileWriteNoPermission))
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw .io(url.lastPathComponent, underlying: error)
        }
    }

    /// explorer R18: how many entries a folder holds, for the confirmation; capped to stay quick.
    @concurrent
    static func entryCount(of url: URL, limit: Int = 10_000) async -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: []) else { return 0 }
        var count = 0
        while enumerator.nextObject() != nil {
            count += 1
            if count >= limit {
                return count
            }
        }
        return count
    }

    private static func destination(
        _ name: String, in folder: URL, root: URL, allowsSlash: Bool
    ) throws(ExplorerError)
        -> URL
    {
        guard isValidName(name, allowsSlash: allowsSlash) else {
            throw .io(name, underlying: CocoaError(.fileWriteInvalidFileName))
        }
        let url = folder.appending(path: name).standardizedFileURL
        guard isInside(url, root: root), isInside(folder, root: root) else {
            throw .io(name, underlying: CocoaError(.fileWriteNoPermission))
        }
        return url
    }
}
