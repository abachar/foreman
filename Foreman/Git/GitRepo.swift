import Foundation

/// A repository of the workspace (git R1): `config.repos`, or a `.git` found up to two levels
/// under the root; the root itself is the repo `"."`.
nonisolated struct GitRepo: Identifiable, Hashable, Sendable {
    /// `"."` or the path relative to the root; stable, used in `state.json`.
    let id: String
    let url: URL

    var name: String {
        id == "." ? url.lastPathComponent : id
    }

    init(id: String, url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }

    init(url: URL, root: URL) {
        let path = Workspace.persistedPath(for: url, root: root)
        self.init(id: path.isEmpty ? "." : path, url: url)
    }

    // MARK: - Discovery (git R1)

    /// The declared repos as they are, otherwise the scan; sorted by id, the root first.
    @concurrent
    static func discover(root: URL, declared: [URL]) async -> [GitRepo] {
        guard declared.isEmpty else {
            return declared.map { GitRepo(url: $0, root: root) }.sorted { $0.id < $1.id }
        }
        return scan(root: root)
    }

    /// git R1: the scan, disk IO never on the main actor.
    ///
    /// `.git` (a folder, or a worktree/submodule file) at the root or up to depth 2, the shared
    /// exclusion list and hidden folders skipped.
    static func scan(root: URL, maximumDepth: Int = 2) -> [GitRepo] {
        var found: [GitRepo] = []
        let rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        func visit(_ folder: URL, depth: Int) {
            if hasGitEntry(folder) {
                found.append(GitRepo(url: folder, root: root))
                return
            }
            guard depth < maximumDepth,
                let children = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { return }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let relative = Workspace.persistedPath(for: child, root: root)
                guard !ExcludedPaths.isExcluded(relative, rootIsHome: rootIsHome) else { continue }
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return found.sorted { $0.id == "." || ($1.id != "." && $0.id < $1.id) }
    }

    static func hasGitEntry(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path(percentEncoded: false))
    }

    /// The folder holding `HEAD`, `index`, `refs/`: `.git` itself, or the `gitdir:` a `.git` file
    /// points at (a worktree or a submodule); `nil` when there is none.
    static func gitDirectory(of repo: URL) -> URL? {
        let entry = repo.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: entry.path(percentEncoded: false), isDirectory: &isDirectory)
        else { return nil }
        if isDirectory.boolValue {
            return entry
        }
        guard let text = try? String(contentsOf: entry, encoding: .utf8),
            let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? URL(filePath: target) : repo.appending(path: target).standardizedFileURL
    }
}
