import Foundation
import Observation

/// What the history panel shows (git R18–R20).
@Observable
@MainActor
final class GitHistoryModel {
    /// The repo shown; `nil` until the changes panel discovered one.
    var repoID: String?
    private(set) var commits: [GitCommit] = []
    private(set) var isLoading = false
    private(set) var error: GitError?
    /// `true` while the last page was full.
    private(set) var hasMore = false
    var query = GitLogQuery()
    /// The rows the table selected, by sha.
    var selection: Set<String> = []

    private var loading: Task<Void, Never>?

    /// The first page again, for a new repo, filter or path.
    func reload(with client: GitCLI?) {
        loading?.cancel()
        commits = []
        query.rewind()
        hasMore = false
        guard let client else { return }
        load(client, append: false)
    }

    /// git R18: the next page of every query, each from its own `--skip`.
    func loadMore(with client: GitCLI?) {
        guard let client, hasMore, !isLoading else { return }
        load(client, append: true)
    }

    private func load(_ client: GitCLI, append: Bool) {
        isLoading = true
        let query = query
        loading = Task { [weak self] in
            do throws(GitError) {
                let pages = try await Self.fetch(query, client: client)
                guard !Task.isCancelled, let self else { return }
                commits = GitLogQuery.combine(pages, after: append ? commits : [])
                self.query.advance(pages)
                hasMore = pages.contains { $0.commits.count >= GitLogQuery.pageSize }
                error = nil
            } catch {
                // A load `reload` superseded: the newer one owns the panel's state, error and
                // spinner included.
                guard !Task.isCancelled else { return }
                self?.error = error
            }
            guard !Task.isCancelled else { return }
            self?.isLoading = false
        }
    }

    @concurrent
    private static func fetch(_ query: GitLogQuery, client: GitCLI) async throws(GitError) -> [GitLogQuery.Page] {
        var pages: [GitLogQuery.Page] = []
        for field in query.fields {
            let output = try await client.run(query.arguments(field: field))
            pages.append(GitLogQuery.Page(field: field, commits: LogParser.parse(output.stdout)))
        }
        return pages
    }
}
