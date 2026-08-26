import Foundation
import Observation

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
        matchCount = 0
        isTruncated = false
        error = nil
        guard !options.query.isEmpty else { return }
        isRunning = true
        task = Task { [options, tool, root] in
            do {
                for try await match in ContentSearch.run(options, tool: tool, root: root) {
                    guard !Task.isCancelled else { return }
                    add(match)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isTruncated = matchCount >= ContentSearch.limit
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func add(_ match: ContentSearch.Match) {
        matchCount += 1
        if let index = groups.firstIndex(where: { $0.path == match.path }) {
            groups[index].matches.append(match)
        } else {
            groups.append(FileGroup(path: match.path, matches: [match]))
        }
    }
}
