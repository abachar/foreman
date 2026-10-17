import Foundation
import FuzzyMatch

/// editor R18: the relative paths of the workspace's files, built at the first `cmd+p`, kept
/// up to date from FSEvents, searched with FuzzyMatch (decision 2026-08-26).
actor QuickOpenIndex {
    /// editor R18: beyond this the index is cut and the palette says so.
    static let limit = 200_000
    /// The most candidates one keystroke scores.
    static let scoringCap = 1000

    struct Search: Sendable {
        let paths: [String]
        let isIndexTruncated: Bool
    }

    private let root: URL
    private let rootIsHome: Bool
    /// Every indexed path with its lowercased UTF-8, the pre-filter's haystack.
    private var paths: [String: [UInt8]] = [:]
    /// editor R18: root-relative paths git ignores (a folder covers what is below it).
    private var ignored: Set<String> = []
    private(set) var isTruncated = false
    private(set) var isBuilt = false
    /// editor R18: the walk in progress, shared by every `build()` that arrives while it runs.
    private var building: Task<Void, Never>?
    private let matcher = FuzzyMatcher(config: .smithWaterman)

    init(root: URL) {
        self.root = root
        rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    var count: Int {
        paths.count
    }

    /// Walks the workspace once, skipping the shared exclusion list; a call once built is a no-op.
    ///
    /// editor R18: the walk is one task shared by every caller that arrives while it runs and
    /// cancelled by none of them — the palette cancels its own search at each keystroke, and that
    /// must not reach the walk (awaiting a task's value does not forward the caller's
    /// cancellation). Only `setIgnored` cancels it; the next call then starts a new walk.
    func build() async {
        guard !isBuilt else { return }
        if let building {
            await building.value
            return
        }
        let walk = Task { await self.walk() }
        building = walk
        await walk.value
        if building == walk {
            building = nil
        }
    }

    /// The walk behind `build()`; it yields regularly — a 200,000-file scan must not monopolise
    /// a pool thread — and stops at a yield once `setIgnored` has cancelled it.
    private func walk() async {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: [.producesRelativePathURLs])
        else {
            isBuilt = true
            return
        }
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited.isMultiple(of: 512) {
                await Task.yield()
                // `setIgnored` already reset the index, and a newer walk may be filling it: leave it alone.
                if Task.isCancelled {
                    return
                }
            }
            let path = url.relativePath
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory == true
            if Self.isSkipped(path, rootIsHome: rootIsHome) || Self.isIgnored(path, in: ignored) {
                // editor R18: `skipDescendants()` after a file or a symlink skips the folder
                // enumerated next (checked 2026-10-17, M23 23.12), so only a folder's are skipped.
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            // The enumerator never descends into a symlink: its `isDirectory` is false (M23 23.12).
            if isDirectory || values?.isSymbolicLink == true {
                continue
            }
            if paths.count >= Self.limit {
                isTruncated = true
                isBuilt = true
                return
            }
            paths[path] = Self.lowered(path)
        }
        isBuilt = true
    }

    /// One FSEvents batch: files that appeared are added, files that are gone are removed.
    func apply(_ changes: [URL]) {
        // A batch during the walk is dropped: the walk sees the file or not, the next batch catches up.
        guard isBuilt else { return }
        for url in changes {
            let path = Workspace.persistedPath(for: url, root: root)
            guard !path.hasPrefix("/"), !Self.isSkipped(path, rootIsHome: rootIsHome) else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) {
                if !isDirectory.boolValue, paths.count < Self.limit {
                    paths[path] = Self.lowered(path)
                }
            } else {
                paths[path] = nil
                let prefix = path + "/"
                paths = paths.filter { !$0.key.hasPrefix(prefix) }
            }
        }
    }

    /// editor R18: replaces the ignored set; an un-ignored path is offered again at once.
    /// editor R18: gitignored folders are not walked either; a built index is dropped and
    /// rebuilt at the next search when the set changes (a gitignored `build/` can hold more files
    /// than the repository).
    func setIgnored(_ ignored: Set<String>) {
        guard ignored != self.ignored else { return }
        self.ignored = ignored
        // An unfinished walk with the old set is abandoned; the next search starts a new one.
        building?.cancel()
        building = nil
        paths = [:]
        isTruncated = false
        isBuilt = false
    }

    /// editor R18: `path` or one of its ancestors is gitignored.
    nonisolated static func isIgnored(_ path: String, in ignored: Set<String>) -> Bool {
        ExplorerModel.isIgnored(path, in: ignored)
    }

    /// editor R17, R18: the best `limit` paths for `query`, gitignored ones left out.
    ///
    /// Scoring is Smith-Waterman at ~40 us per candidate (2 s per keystroke over 53,000 paths,
    /// measured in M6 6.5), and it does not parallelise (contention inside the library). So, as
    /// fzf does, a cheap subsequence test keeps only the paths that can match, and at most
    /// `scoringCap` of them are scored: those whose file name matches first (R17: the name wins),
    /// the shortest paths first among them.
    func search(_ query: String, limit: Int) async -> Search {
        await build()
        let needle = Self.lowered(query).filter { $0 != UInt8(ascii: " ") }
        var named: [String] = []
        var others: [String] = []
        for (path, bytes) in paths where Self.isSubsequence(needle, of: bytes) && !Self.isIgnored(path, in: ignored) {
            let name = bytes.lastIndex(of: UInt8(ascii: "/")).map { Array(bytes[($0 + 1)...]) } ?? bytes
            if Self.isSubsequence(needle, of: name) {
                named.append(path)
            } else {
                others.append(path)
            }
        }
        var candidates = named
        if candidates.count > Self.scoringCap {
            candidates = Array(candidates.sorted { $0.utf8.count < $1.utf8.count }.prefix(Self.scoringCap))
        } else if candidates.count < Self.scoringCap {
            candidates += others.sorted { $0.utf8.count < $1.utf8.count }.prefix(Self.scoringCap - candidates.count)
        }
        let matches = matcher.topMatches(candidates, against: query, limit: limit)
        return Search(paths: matches.map(\.candidate), isIndexTruncated: isTruncated)
    }

    nonisolated static func lowered(_ text: String) -> [UInt8] {
        Array(text.lowercased().utf8)
    }

    /// Every byte of `needle` appears in `haystack`, in order (both lowercased by `lowered`).
    nonisolated static func isSubsequence(_ needle: [UInt8], of haystack: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = 0
        for byte in haystack where byte == needle[index] {
            index += 1
            if index == needle.count {
                return true
            }
        }
        return false
    }

    /// The exclusion list, plus `.git` itself and `.foreman`: nothing in there is a file to open.
    nonisolated static func isSkipped(_ path: String, rootIsHome: Bool) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name == ".git" || name == ".foreman" || ExcludedPaths.isExcluded(path, rootIsHome: rootIsHome)
    }
}
