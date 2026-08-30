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
        data.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = String(decoding: record, as: UTF8.self).split(
                separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false)
            guard fields.count == 6, !fields[0].isEmpty else { return nil }
            return GitCommit(
                sha: String(fields[0]), shortSha: String(fields[1]), author: String(fields[2]),
                date: ISO8601DateFormatter().date(from: String(fields[3])),
                refs: fields[4].split(separator: ", ").map { String($0).trimmingCharacters(in: .whitespaces) },
                subject: String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// git R18: "3 minutes ago", "yesterday"…; a missing date reads as empty.
    static func relativeText(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
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
