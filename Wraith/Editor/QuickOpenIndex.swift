import Foundation
import FuzzyMatch

/// editor R18: the relative paths of the workspace's files, built at the first `cmd+p`, kept
/// up to date from FSEvents, searched with FuzzyMatch (decision 2026-08-26).
actor QuickOpenIndex {
    /// editor R18: beyond this the index is cut and the palette says so.
    static let limit = 200_000

    struct Search: Sendable {
        let paths: [String]
        let isIndexTruncated: Bool
    }

    private let root: URL
    private let rootIsHome: Bool
    private var paths: Set<String> = []
    /// editor R18: root-relative paths git ignores (a folder covers what is below it).
    private var ignored: Set<String> = []
    private(set) var isTruncated = false
    private(set) var isBuilt = false
    private let matcher = FuzzyMatcher(config: .smithWaterman)

    init(root: URL) {
        self.root = root
        rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    var count: Int {
        paths.count
    }

    /// Walks the workspace once, skipping the shared exclusion list; a second call is a no-op.
    func build() {
        guard !isBuilt else { return }
        isBuilt = true
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: [.producesRelativePathURLs])
        else { return }
        while let url = enumerator.nextObject() as? URL {
            let path = url.relativePath
            if Self.isSkipped(path, rootIsHome: rootIsHome) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true || values?.isSymbolicLink == true {
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if paths.count >= Self.limit {
                isTruncated = true
                return
            }
            paths.insert(path)
        }
    }

    /// One FSEvents batch: files that appeared are added, files that are gone are removed.
    func apply(_ changes: [URL]) {
        guard isBuilt else { return }
        for url in changes {
            let path = Workspace.persistedPath(for: url, root: root)
            guard !path.hasPrefix("/"), !Self.isSkipped(path, rootIsHome: rootIsHome) else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) {
                if !isDirectory.boolValue, paths.count < Self.limit {
                    paths.insert(path)
                }
            } else {
                paths.remove(path)
                let prefix = path + "/"
                paths = paths.filter { !$0.hasPrefix(prefix) }
            }
        }
    }

    /// editor R18: replaces the ignored set; an un-ignored path is offered again at once.
    func setIgnored(_ ignored: Set<String>) {
        self.ignored = ignored
    }

    /// editor R18: `path` or one of its ancestors is gitignored.
    nonisolated static func isIgnored(_ path: String, in ignored: Set<String>) -> Bool {
        ExplorerModel.isIgnored(path, in: ignored)
    }

    /// editor R17, R18: the best `limit` paths for `query`, gitignored ones left out.
    func search(_ query: String, limit: Int) -> Search {
        let candidates = ignored.isEmpty ? paths : paths.filter { !Self.isIgnored($0, in: ignored) }
        let matches = matcher.topMatches(candidates, against: query, limit: limit)
        return Search(paths: matches.map(\.candidate), isIndexTruncated: isTruncated)
    }

    /// The exclusion list, plus `.git` itself and `.wraith`: nothing in there is a file to open.
    nonisolated static func isSkipped(_ path: String, rootIsHome: Bool) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name == ".git" || name == ".wraith" || ExcludedPaths.isExcluded(path, rootIsHome: rootIsHome)
    }
}
