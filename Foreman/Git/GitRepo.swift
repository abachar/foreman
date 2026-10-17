import Foundation

/// A repository of the workspace (git R1): `config.repos`, or a `.git` found up to two levels
/// under the root; the root itself is the repo `"."`.
nonisolated struct GitRepo: Identifiable, Hashable, Sendable {
    /// `"."` or the path relative to the root; stable, used in `state.json`.
    let id: String
    let url: URL
    /// `canonicalPath(url)`, resolved once here so a comparison in a `body` makes no syscall
    /// (audit 2026-10-17 U5).
    let canonicalPath: String
    /// git R33: the repo this one is a worktree of; `nil` for a top-level section.
    var parent: String?
    /// git R34, R38: git's lock reason (`""` without one); `nil` when not locked.
    var lockReason: String?

    /// A worktree, or a folder outside the root, goes by its folder name (git R34).
    var name: String {
        id == "." || parent != nil || id.hasPrefix("/") ? url.lastPathComponent : id
    }

    init(id: String, url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
        canonicalPath = Self.canonicalPath(url)
    }

    init(url: URL, root: URL) {
        let path = Workspace.persistedPath(for: url, root: root)
        self.init(id: path.isEmpty ? "." : path, url: url)
    }

    // MARK: - Discovery (git R1)

    /// The declared repos as they are, otherwise the scan, minus the `!` exclusions of
    /// `config.repos` (git R1, amended 2026-09-09); sorted by id, the root first.
    @concurrent
    static func discover(root: URL, declared: [URL], ignored: [URL] = []) async -> [GitRepo] {
        let excluded = Set(ignored.map { GitRepo(url: $0, root: root).id })
        guard declared.isEmpty else {
            return declared.map { GitRepo(url: $0, root: root) }
                .filter { !excluded.contains($0.id) }
                .sorted { $0.id < $1.id }
        }
        return scan(root: root).filter { !excluded.contains($0.id) }
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

    /// git R33, R33a: each top-level repo followed by its worktrees, by folder name.
    ///
    /// `worktrees` is each repo's `worktree list`, its first entry the main folder: a repo whose
    /// main folder is another repo found moves under that one (no duplicate), a bare or prunable
    /// entry is skipped, and a repo's own folder is not its own child.
    static func arrange(_ repos: [GitRepo], worktrees: [String: [GitWorktree]], root: URL) -> [GitRepo] {
        let byPath = Dictionary(repos.map { ($0.canonicalPath, $0) }) { first, _ in first }
        let owned = Set(
            repos.filter { repo in
                guard let main = worktrees[repo.id]?.first, let owner = byPath[canonicalPath(main.folder)] else {
                    return false
                }
                return owner.id != repo.id
            }
            .map(\.id))
        var result: [GitRepo] = []
        for repo in repos where !owned.contains(repo.id) {
            result.append(repo)
            let own = repo.canonicalPath
            result += (worktrees[repo.id] ?? [])
                .filter { !$0.isBare && !$0.isPrunable && canonicalPath($0.folder) != own }
                .map { worktree in
                    // A worktree the scan also found keeps the id the scan gave it.
                    var child = byPath[canonicalPath(worktree.folder)] ?? GitRepo(url: worktree.folder, root: root)
                    child.parent = repo.id
                    child.lockReason = worktree.lockReason
                    return child
                }
                .sorted {
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                }
        }
        return result
    }

    /// A folder's path for comparisons: symlinks resolved (`/private/var` and `/var` alike), no
    /// trailing `/`.
    static func canonicalPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
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

    /// git R35: the folder shared by every worktree of the repo (`commondir` of a linked
    /// worktree's git folder, else the git folder itself); its `worktrees/` lists them.
    static func commonDirectory(of repo: URL) -> URL? {
        guard let directory = gitDirectory(of: repo) else { return nil }
        guard let text = try? String(contentsOf: directory.appending(path: "commondir"), encoding: .utf8) else {
            return directory
        }
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.hasPrefix("/") ? URL(filePath: target) : directory.appending(path: target).standardizedFileURL
    }
}
