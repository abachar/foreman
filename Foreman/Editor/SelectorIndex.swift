import Foundation

/// editor R47: the workspace's stylesheets, indexed by what they define.
///
/// Built at the **first resolution**, never at startup and never on opening a tab (P4), off the
/// main actor, walking the same exclusion list as the quick-open index (`QuickOpenIndex`, R18) —
/// which is the model this copies rather than abstracts over: two walks, two purposes, no shared
/// "walker" for a third that does not exist.
actor SelectorIndex {
    /// One place a selector is defined.
    struct Site: Equatable, Sendable {
        let url: URL
        let line: Int
    }

    private let root: URL
    private let rootIsHome: Bool
    /// `kind` + name → where it is defined, in walk order (R48 takes the first).
    private var sites: [Key: [Site]] = [:]
    /// What each file contributed, so one file can be re-read without rebuilding everything.
    private var byFile: [URL: [Key]] = [:]
    private var isBuilt = false

    private struct Key: Hashable {
        let name: String
        let kind: Selectors.Kind
    }

    init(root: URL) {
        self.root = root
        rootIsHome = root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    var count: Int {
        sites.count
    }

    /// editor R48: where `name` is defined, in walk order; the index is built on the first call.
    func sites(of name: String, kind: Selectors.Kind) async -> [Site] {
        await build()
        return sites[Key(name: name, kind: kind)] ?? []
    }

    /// editor R47: walks the workspace's `.css` files once; a second call is a no-op.
    func build() async {
        guard !isBuilt else { return }
        isBuilt = true
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.producesRelativePathURLs])
        else { return }
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited.isMultiple(of: 512) {
                await Task.yield()
                if Task.isCancelled {
                    sites = [:]
                    byFile = [:]
                    isBuilt = false
                    return
                }
            }
            if QuickOpenIndex.isSkipped(url.relativePath, rootIsHome: rootIsHome) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true || values?.isSymbolicLink == true {
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            // editor R49: `.css` only — `.scss` and `.less` have no grammar (R11).
            guard url.pathExtension.lowercased() == "css" else { continue }
            read(url)
        }
    }

    /// editor R47: the stylesheets of a `FSWatchService` batch, re-read or forgotten.
    ///
    /// Nothing happens before the index exists: a change to a file nobody has asked about yet is
    /// answered by the first build, not by keeping a list against the day someone does (P4).
    func apply(_ batch: [URL]) {
        guard isBuilt else { return }
        for url in batch where url.pathExtension.lowercased() == "css" {
            forget(url)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                read(url)
            }
        }
    }

    /// editor R47: a file that went takes its selectors with it.
    func forget(_ url: URL) {
        for key in byFile[url] ?? [] {
            sites[key]?.removeAll { $0.url == url }
            if sites[key]?.isEmpty == true {
                sites[key] = nil
            }
        }
        byFile[url] = nil
    }

    private func read(_ url: URL) {
        guard let css = try? String(contentsOf: url, encoding: .utf8) else { return }
        var keys: [Key] = []
        for definition in Selectors.definitions(in: css) {
            let key = Key(name: definition.name, kind: definition.kind)
            sites[key, default: []].append(Site(url: url, line: definition.line))
            keys.append(key)
        }
        guard !keys.isEmpty else { return }
        byFile[url] = keys
    }
}
