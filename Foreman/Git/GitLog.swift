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
    /// git R19 (amended 2026-10-16): the abbreviated parents, `%p`, for the commit's details.
    var parents: [String] = []

    var id: String {
        sha
    }
}

/// `log --format=<fields> -z` → `[GitCommit]` (git R27).
///
/// Fields separated by `\x1f`, the subject last so it may hold anything; records by NUL.
nonisolated enum LogParser {
    static let format = "%H%x1f%h%x1f%an%x1f%aI%x1f%D%x1f%p%x1f%s"

    static func parse(_ data: Data) -> [GitCommit] {
        // One formatter for the whole page instead of one per commit; `%aI` writes the offset with
        // a colon, which is what this formatter reads and what the panel's fixtures pin.
        let dates = ISO8601DateFormatter()
        return data.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = String(decoding: record, as: UTF8.self).split(
                separator: "\u{1f}", maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count == 7, !fields[0].isEmpty else { return nil }
            return GitCommit(
                sha: String(fields[0]), shortSha: String(fields[1]), author: String(fields[2]),
                date: dates.date(from: String(fields[3])),
                refs: fields[4].split(separator: ", ").map { String($0).trimmingCharacters(in: .whitespaces) },
                subject: String(fields[6]).trimmingCharacters(in: .whitespacesAndNewlines),
                parents: fields[5].split(separator: " ").map(String.init))
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

    /// git R18 (amended 2026-10-16, view 05): `Today 10:48`, `Yesterday 18:40`, `Oct 14 17:30`,
    /// and the year for a commit of another year (`Oct 14 2025`).
    static func shortDate(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let time = date.formatted(
            Date.FormatStyle(locale: Locale(identifier: "en_GB"), calendar: calendar, timeZone: calendar.timeZone)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday \(time)"
        }
        let day = date.formatted(
            Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).day())
        guard calendar.component(.year, from: date) == calendar.component(.year, from: now) else {
            return "\(day) \(calendar.component(.year, from: date))"
        }
        return "\(day) \(time)"
    }
}

/// git R19b: the files a commit changed, `show --name-status -z`.
nonisolated enum CommitFilesParser {
    /// A merge shows what it brought to its first parent, like its diff (R14).
    static func arguments(_ sha: String) -> [String] {
        [
            "-c", "core.quotepath=false", "show", "-m", "--first-parent", "--format=", "--name-status", "-z", "-M", sha,
            "--",
        ]
    }

    /// One entry per file, its status in `index` (the side a commit has).
    ///
    /// The fields are `M\0path\0` or `R100\0old\0new\0`: a status letter (a score after R and
    /// C), then one path, or two for a rename or a copy.
    static func parse(_ data: Data) -> [GitStatusEntry] {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self)
        }[...]
        var result: [GitStatusEntry] = []
        while let status = fields.popFirst() {
            let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let letter = trimmed.first, let change = GitChange(rawValue: letter) else { continue }
            if change == .renamed || change == .copied {
                guard let old = fields.popFirst(), let new = fields.popFirst() else { break }
                result.append(GitStatusEntry(path: new, originalPath: old, index: change, worktree: .unmodified))
            } else {
                guard let path = fields.popFirst() else { break }
                result.append(GitStatusEntry(path: path, index: change, worktree: .unmodified))
            }
        }
        return result
    }
}

/// What the history panel asks git (git R18, R20).
nonisolated struct GitLogQuery: Equatable, Sendable {
    static let pageSize = 200

    /// One text over the subject (`--grep`) or the author (`--author`), each asked separately.
    var filter = ""
    /// git R20: a file's history, `log --follow`.
    var path: String?
    /// git R36b: only the commits `head` adds over `base`.
    var range: Range?
    /// git R18 (amended 2026-10-16): every branch (`--all`, by date) instead of the current one's
    /// first-parent line; ignored for a range.
    var allBranches = false

    struct Range: Equatable, Sendable {
        let base: String
        let head: String
    }
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
        var arguments =
            (allBranches && range == nil ? ["log", "--all", "--date-order"] : ["log", "--first-parent"]) + [
                "--format=\(LogParser.format)", "-z", "-n", "\(Self.pageSize)", "--skip=\(consumed[field] ?? 0)",
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
        if let range {
            arguments.append(GitCommand.range(base: range.base, head: range.head))
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

/// git R18 (amended 2026-10-16, view 05): a ref of a history row as a chip — the branch `HEAD`
/// is on, a local branch, a remote one, a tag; `origin/HEAD` is left out.
nonisolated struct GitRefChip: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case head
        case local
        case remote
        case tag
    }

    let name: String
    let kind: Kind

    var id: String {
        "\(kind)-\(name)"
    }

    /// The chips of a row, from its `%D` decorations.
    ///
    /// `remotes` are the remote branches `for-each-ref` listed (R40), which tells `origin/main`
    /// from a local branch named with a slash.
    static func chips(_ decorations: [String], remotes: Set<String>) -> [GitRefChip] {
        decorations.compactMap { decoration in
            let text = decoration.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasSuffix("/HEAD") {
                return nil
            }
            if text.hasPrefix("HEAD -> ") {
                return GitRefChip(name: String(text.dropFirst("HEAD -> ".count)), kind: .head)
            }
            if text == "HEAD" {
                return GitRefChip(name: "HEAD", kind: .head)
            }
            if text.hasPrefix("tag: ") {
                return GitRefChip(name: String(text.dropFirst("tag: ".count)), kind: .tag)
            }
            return GitRefChip(name: text, kind: remotes.contains(text) ? .remote : .local)
        }
    }
}
