import Foundation
import Observation
import os

/// The bottom panel's state (editor R20, R21): options, grouped results, the running search.
@Observable
@MainActor
final class SearchModel {
    struct FileGroup: Identifiable {
        let path: String
        var matches: [ContentSearch.Match]
        var id: String { path }
    }

    var options = ContentSearch.Options(query: "")
    private(set) var groups: [FileGroup] = []
    /// editor R21 (amended 2026-10-17): where each file's group is, so a match is filed in O(1).
    private var groupIndex: [String: Int] = [:]
    private(set) var matchCount = 0
    private(set) var isTruncated = false
    private(set) var isRunning = false
    private(set) var error: String?
    let tool: ContentSearch.Tool

    private let root: URL
    private var task: Task<Void, Never>?

    init(root: URL, tool: ContentSearch.Tool = ContentSearch.locateTool()) {
        self.root = root
        self.tool = tool
    }

    /// editor R21: a new search cancels the running one.
    func search() {
        cancel()
        groups = []
        groupIndex = [:]
        matchCount = 0
        isTruncated = false
        error = nil
        guard !options.query.isEmpty else { return }
        isRunning = true
        task = Task { [options, tool, root] in
            // architecture, Performance (2026-10-17): one interval per search, its first result marked.
            let signpost = Perf.signposter.beginInterval("search", id: Perf.signposter.makeSignpostID())
            defer { Perf.signposter.endInterval("search", signpost) }
            // editor R21 (amended 2026-10-17): the panel is updated once per `batchDelay`, not
            // once per match — 2 000 list updates were the slow part, `rg` takes milliseconds.
            var pending: [ContentSearch.Match] = []
            var lastFlush = ContinuousClock.now
            do {
                for try await match in ContentSearch.run(options, tool: tool, root: root) {
                    guard !Task.isCancelled else { return }
                    if matchCount == 0, pending.isEmpty {
                        Perf.signposter.emitEvent("search.first")
                    }
                    pending.append(match)
                    if Self.shouldFlush(since: lastFlush, now: .now, isFirst: matchCount == 0) {
                        add(pending)
                        pending = []
                        lastFlush = .now
                    }
                }
            } catch let error as EditorError {
                self.error = error.description
            } catch {
                self.error = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            add(pending)
            isTruncated = matchCount >= ContentSearch.limit
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// editor R21: how long results wait before reaching the panel.
    nonisolated static let batchDelay = Duration.milliseconds(50)

    /// The first match shows at once; the next ones wait for `batchDelay` since the last update.
    nonisolated static func shouldFlush(
        since last: ContinuousClock.Instant, now: ContinuousClock.Instant, isFirst: Bool
    ) -> Bool {
        isFirst || now - last >= batchDelay
    }

    /// The matches filed under their file, in arrival order, in one update of the panel.
    func add(_ matches: [ContentSearch.Match]) {
        guard !matches.isEmpty else { return }
        var updated = groups
        for match in matches {
            if let index = groupIndex[match.path] {
                updated[index].matches.append(match)
            } else {
                groupIndex[match.path] = updated.count
                updated.append(FileGroup(path: match.path, matches: [match]))
            }
        }
        matchCount += matches.count
        groups = updated
    }
}
