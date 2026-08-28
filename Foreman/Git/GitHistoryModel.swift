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
        query.skip = 0
        hasMore = false
        guard let client else { return }
        load(client, append: false)
    }

    /// git R18: the next page, by `--skip`.
    func loadMore(with client: GitCLI?) {
        guard let client, hasMore, !isLoading else { return }
        query.skip = commits.count
        load(client, append: true)
    }

    private func load(_ client: GitCLI, append: Bool) {
        isLoading = true
        let query = query
        loading = Task { [weak self] in
            defer { self?.isLoading = false }
            do throws(GitError) {
                let pages = try await Self.fetch(query, client: client)
                guard !Task.isCancelled, let self else { return }
                let merged = GitLogQuery.merge(pages)
                commits = append ? GitLogQuery.merge([commits, merged]) : merged
                hasMore = pages.contains { $0.count >= GitLogQuery.pageSize }
                error = nil
            } catch {
                self?.error = error
            }
        }
    }

    @concurrent
    private static func fetch(_ query: GitLogQuery, client: GitCLI) async throws(GitError) -> [[GitCommit]] {
        var pages: [[GitCommit]] = []
        for field in query.fields {
            pages.append(LogParser.parse(try await client.run(query.arguments(field: field)).stdout))
        }
        return pages
    }
}
