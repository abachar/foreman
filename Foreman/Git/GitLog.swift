import Foundation

/// One line of the history (git R18).
nonisolated struct GitCommit: Equatable, Sendable, Identifiable {
    let sha: String
    let shortSha: String
    let author: String
    let date: Date?
    /// `HEAD -> main`, `origin/main`, `tag: v1`, as `%D` lists them.
    let refs: [String]
    let subject: String

    var id: String {
        sha
    }
}

/// `log --format=<fields> -z` → `[GitCommit]` (git R27).
///
/// Fields separated by `\x1f`, the subject last so it may hold anything; records by NUL.
nonisolated enum LogParser {
    static let format = "%H%x1f%h%x1f%an%x1f%aI%x1f%D%x1f%s"

    static func parse(_ data: Data) -> [GitCommit] {
        // One formatter for the whole page instead of one per commit; `%aI` writes the offset with
        // a colon, which is what this formatter reads and what the panel's fixtures pin.
        let dates = ISO8601DateFormatter()
        return data.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = String(decoding: record, as: UTF8.self).split(
                separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false)
            guard fields.count == 6, !fields[0].isEmpty else { return nil }
            return GitCommit(
                sha: String(fields[0]), shortSha: String(fields[1]), author: String(fields[2]),
                date: dates.date(from: String(fields[3])),
                refs: fields[4].split(separator: ", ").map { String($0).trimmingCharacters(in: .whitespaces) },
                subject: String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The panel draws one row per commit and a formatter is expensive to build; it is kept on the
    /// main actor, which is where the rows are drawn.
    @MainActor private static let relativeDates: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// git R18: "3 minutes ago", "yesterday"…; a missing date reads as empty.
    @MainActor static func relativeText(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        return relativeDates.localizedString(for: date, relativeTo: now)
    }
}

/// What the history panel asks git (git R18, R20).
nonisolated struct GitLogQuery: Equatable, Sendable {
    static let pageSize = 200

    /// One text over the subject (`--grep`) or the author (`--author`), each asked separately.
    var filter = ""
    /// git R20: a file's history, `log --follow`.
    var path: String?
    /// git R18: how many commits each query already brought back.
    ///
    /// The pages are merged by sha, so a commit matching both the subject and the author is one
    /// row and the merged count is not what either `log` consumed: each paginates on its own.
    private(set) var consumed: [Field?: Int] = [:]

    enum Field: Sendable, CaseIterable {
        case subject
        case author
    }

    /// One query's answer, next to the field it filtered on.
    struct Page: Sendable {
        let field: Field?
        let commits: [GitCommit]
    }

    /// git R27: `--first-parent`, machine format, one page; the filter on one field at a time.
    func arguments(field: Field?) -> [String] {
        var arguments = [
            "log", "--first-parent", "--format=\(LogParser.format)", "-z", "-n", "\(Self.pageSize)",
            "--skip=\(consumed[field] ?? 0)",
        ]
        if !filter.isEmpty, let field {
            // git R18: a text filter, not a pattern. Without `--fixed-strings` git reads it as a
            // basic regular expression, so a `[` is a fatal error and a `.` matches anything; it
            // applies to `--author` as well as to `--grep`.
            arguments.append("--fixed-strings")
            switch field {
            case .subject: arguments += ["-i", "--grep=\(filter)"]
            case .author: arguments += ["-i", "--author=\(filter)"]
            }
        }
        if path != nil {
            arguments.append("--follow")
        }
        arguments.append("--")
        if let path {
            arguments.append(path)
        }
        return arguments
    }

    /// The queries to run: one without a filter, or one per field with it.
    var fields: [Field?] {
        filter.isEmpty ? [nil] : Field.allCases
    }

    /// The next page of each query starts where that query stopped.
    mutating func advance(_ pages: [Page]) {
        for page in pages {
            consumed[page.field, default: 0] += page.commits.count
        }
    }

    /// Back to the first page of every query (a new repo, filter or path).
    mutating func rewind() {
        consumed = [:]
    }

    /// The list to show once `pages` answered, `existing` being what is already on screen.
    ///
    /// One query is git's own answer and keeps its order: `--first-parent` puts the branch's
    /// commits in the order they were merged, which an author date does not — a rebased or
    /// cherry-picked commit carries an older one and would sink far below HEAD. Two filtered
    /// queries have no order in common, so there they are merged by sha, newest first.
    static func combine(_ pages: [Page], after existing: [GitCommit]) -> [GitCommit] {
        guard pages.count > 1 else {
            var seen = Set(existing.map(\.sha))
            return existing + (pages.first?.commits ?? []).filter { seen.insert($0.sha).inserted }
        }
        return merge([existing, merge(pages.map(\.commits))])
    }

    /// The pages merged: by sha, newest first, git's order kept for equal dates.
    static func merge(_ pages: [[GitCommit]]) -> [GitCommit] {
        var seen: Set<String> = []
        var result: [GitCommit] = []
        for commit in pages.flatMap({ $0 }) where seen.insert(commit.sha).inserted {
            result.append(commit)
        }
        return result.enumerated().sorted { first, second in
            let (a, b) = (first.element.date ?? .distantPast, second.element.date ?? .distantPast)
            return a == b ? first.offset < second.offset : a > b
        }.map(\.element)
    }
}
