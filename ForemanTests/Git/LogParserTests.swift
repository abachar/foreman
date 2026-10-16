import Foundation
import Testing

@testable import Foreman

/// `log --format -z` over fixtures, the query and the menu arguments (git R18, R19, R27).
struct LogParserTests {
    private func record(
        _ sha: String, _ short: String, _ author: String, _ date: String, _ refs: String, _ subject: String,
        parents: String = ""
    ) -> String {
        [sha, short, author, date, refs, parents, subject].joined(separator: "\u{1f}")
    }

    private func commit(_ sha: String, _ seconds: TimeInterval = 0) -> GitCommit {
        GitCommit(
            sha: sha, shortSha: sha, author: "", date: Date(timeIntervalSince1970: seconds), refs: [], subject: "")
    }

    @Test func readsRecordsFieldsRefsAndDates() throws {
        let data = Data(
            (record(
                "4f2a9c1e0b7d6a5f3c2b1a0e9d8c7b6a5f4e3d2c", "4f2a9c1", "Ada, Lovelace", "2026-08-27T10:00:00+02:00",
                "HEAD -> main, origin/main, tag: v1", "feat: x") + "\0"
                + record(
                    "1111111111111111111111111111111111111111", "1111111", "Bob", "2026-08-26T10:00:00Z", "", "fix")
                + "\0").utf8)
        let commits = LogParser.parse(data)
        #expect(commits.count == 2)
        let first = try #require(commits.first)
        #expect(first.shortSha == "4f2a9c1")
        #expect(first.author == "Ada, Lovelace")
        #expect(first.refs == ["HEAD -> main", "origin/main", "tag: v1"])
        #expect(first.subject == "feat: x")
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-08-27T10:00:00+02:00"))
        #expect(commits[1].refs == [""] || commits[1].refs.isEmpty || commits[1].refs == [""])
        #expect(commits[1].subject == "fix")
    }

    @Test func aSubjectMayHoldTheSeparatorOrANewline() throws {
        let data = Data(
            (record("a", "a", "me", "2026-08-27T10:00:00Z", "", "odd \u{1f} subject\nwith line") + "\0").utf8)
        let commit = try #require(LogParser.parse(data).first)
        #expect(commit.subject == "odd \u{1f} subject\nwith line")
        #expect(LogParser.parse(Data()).isEmpty)
        #expect(LogParser.parse(Data("garbage\0".utf8)).isEmpty)
    }

    /// git R19 (amended 2026-10-16): the parents, for the commit's details.
    @Test func readsTheParents() throws {
        let data = Data(
            (record("a", "a", "me", "2026-08-27T10:00:00Z", "", "merge", parents: "1a2b3c4 5d6e7f8") + "\0").utf8)
        #expect(try #require(LogParser.parse(data).first).parents == ["1a2b3c4", "5d6e7f8"])
    }

    /// git R18 (amended 2026-10-16, view 05): today and yesterday by name, the year when it differs.
    @Test func shortDatesNameTodayAndYesterday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-16T15:00:00Z"))
        func date(_ text: String) throws -> Date { try #require(ISO8601DateFormatter().date(from: text)) }
        #expect(LogParser.shortDate(try date("2026-10-16T10:48:00Z"), now: now, calendar: calendar).hasPrefix("Today "))
        #expect(
            LogParser.shortDate(try date("2026-10-15T18:40:00Z"), now: now, calendar: calendar).hasPrefix("Yesterday "))
        #expect(
            LogParser.shortDate(try date("2026-10-14T17:30:00Z"), now: now, calendar: calendar).hasPrefix("Oct 14 "))
        #expect(LogParser.shortDate(try date("2025-03-02T09:00:00Z"), now: now, calendar: calendar) == "Mar 2 2025")
        #expect(LogParser.shortDate(nil, now: now).isEmpty)
    }

    /// git R18 (amended 2026-10-16): the chips of a row, `origin/HEAD` left out.
    @Test func refChipsTellTheHeadLocalRemoteAndTags() {
        let chips = GitRefChip.chips(
            ["HEAD -> main", "origin/main", "origin/HEAD", "tag: v1.3.0", "feat/order-lines", ""],
            remotes: ["origin/main"])
        #expect(
            chips == [
                GitRefChip(name: "main", kind: .head), GitRefChip(name: "origin/main", kind: .remote),
                GitRefChip(name: "v1.3.0", kind: .tag), GitRefChip(name: "feat/order-lines", kind: .local),
            ])
        #expect(GitRefChip.chips(["HEAD"], remotes: []) == [GitRefChip(name: "HEAD", kind: .head)])
    }

    /// git R18 (amended 2026-10-16): *All branches* reads every ref by date, except for a range.
    @Test func allBranchesReadsEveryRefByDate() {
        var query = GitLogQuery()
        query.allBranches = true
        #expect(Array(query.arguments(field: nil).prefix(3)) == ["log", "--all", "--date-order"])
        query.range = GitLogQuery.Range(base: "main", head: "feat")
        #expect(Array(query.arguments(field: nil).prefix(2)) == ["log", "--first-parent"])
    }

    @Test @MainActor func relativeDates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!LogParser.relativeText(now.addingTimeInterval(-90), now: now).isEmpty)
        #expect(LogParser.relativeText(nil, now: now).isEmpty)
    }

    @Test func queriesOnePageWithSkipAndTheFilterPerField() {
        var query = GitLogQuery()
        #expect(
            query.arguments(field: nil) == [
                "log", "--first-parent", "--format=\(LogParser.format)", "-z", "-n", "200", "--skip=0", "--",
            ])
        #expect(query.fields == [nil])
        query.filter = "ada"
        #expect(query.fields == [.subject, .author])
        #expect(query.arguments(field: .subject).contains("--grep=ada"))
        #expect(query.arguments(field: .author).contains("--author=ada"))
        // git R18: the text is matched literally, on both fields.
        #expect(query.arguments(field: .subject).contains("--fixed-strings"))
        #expect(query.arguments(field: .author).contains("--fixed-strings"))
        query.filter = "fix: [x] (y)"
        #expect(query.arguments(field: .subject).contains("--grep=fix: [x] (y)"))
        #expect(!query.arguments(field: nil).contains("--fixed-strings"))
        query.path = "src/a.swift"
        #expect(query.arguments(field: nil).suffix(3) == ["--follow", "--", "src/a.swift"])
    }

    /// git R18: a commit matching both fields is one row, so the merged count is smaller than what
    /// the two `log` runs consumed; skipping the merged count would drop the difference.
    @Test func eachFilteredQueryPaginatesOnItsOwnCount() {
        func page(_ field: GitLogQuery.Field, _ shas: [String]) -> GitLogQuery.Page {
            GitLogQuery.Page(field: field, commits: shas.map { commit($0) })
        }
        var query = GitLogQuery()
        query.filter = "ada"
        #expect(query.arguments(field: .subject).contains("--skip=0"))
        #expect(query.arguments(field: .author).contains("--skip=0"))

        let subjects = (0..<200).map { "s\($0)" }
        // The author page repeats three of them and brings 197 of its own.
        let authors = ["s0", "s1", "s2"] + (0..<197).map { "a\($0)" }
        let pages = [page(.subject, subjects), page(.author, authors)]
        query.advance(pages)
        #expect(GitLogQuery.merge(pages.map(\.commits)).count == 397)
        #expect(query.arguments(field: .subject).contains("--skip=200"))
        #expect(query.arguments(field: .author).contains("--skip=200"))

        query.advance([page(.subject, ["s200"]), page(.author, [])])
        #expect(query.arguments(field: .subject).contains("--skip=201"))
        #expect(query.arguments(field: .author).contains("--skip=200"))
        query.rewind()
        #expect(query.arguments(field: .subject).contains("--skip=0"))
    }

    /// git R18: `--first-parent` is git's order, and an author date is not it — a rebased or
    /// cherry-picked commit keeps an older one and must stay where git put it.
    @Test func anUnfilteredPageKeepsGitsOrder() {
        let first = [commit("a", 10), commit("b", 300), commit("c", 200)]
        let page = [GitLogQuery.Page(field: nil, commits: first)]
        #expect(GitLogQuery.combine(page, after: []).map(\.sha) == ["a", "b", "c"])
        let next = [GitLogQuery.Page(field: nil, commits: [commit("c", 200), commit("d", 400)])]
        #expect(GitLogQuery.combine(next, after: first).map(\.sha) == ["a", "b", "c", "d"])
        // Two filtered queries have no order in common: those are dated, newest first.
        let filtered = [
            GitLogQuery.Page(field: .subject, commits: [commit("x", 10)]),
            GitLogQuery.Page(field: .author, commits: [commit("y", 20)]),
        ]
        #expect(GitLogQuery.combine(filtered, after: []).map(\.sha) == ["y", "x"])
    }

    @Test func mergesPagesBySha() {
        let merged = GitLogQuery.merge([[commit("a", 30), commit("b", 20)], [commit("b", 20), commit("c", 25)]])
        #expect(merged.map(\.sha) == ["a", "c", "b"])
    }

    @Test func menuArgumentsNeverProduceHard() {
        #expect(GitCommand.checkoutDetached("abc") == ["checkout", "--detach", "abc"])
        #expect(GitCommand.createBranch("feat/x", at: "abc") == ["switch", "-c", "feat/x", "abc"])
        #expect(GitCommand.cherryPick("abc") == ["cherry-pick", "abc"])
        #expect(GitCommand.revert("abc") == ["revert", "--no-edit", "abc"])
        #expect(GitCommand.reset(to: "abc", mode: .soft) == ["reset", "--soft", "abc"])
        #expect(GitCommand.reset(to: "abc", mode: .mixed) == ["reset", "--mixed", "abc"])
        for mode in [GitCommand.ResetMode.soft, .mixed] {
            #expect(!GitCommand.reset(to: "abc", mode: mode).contains("--hard"))
        }
    }

    @Test func aPathRelativeToTheRootBecomesRelativeToItsRepo() {
        let root = URL(filePath: "/work")
        let repo = GitRepo(id: "libs/core", url: URL(filePath: "/work/libs/core"))
        #expect(GitFeature.path("libs/core/src/a.swift", in: repo, root: root) == "src/a.swift")
        #expect(GitFeature.path("README.md", in: GitRepo(id: ".", url: root), root: root) == "README.md")
    }
}

/// git R19b: `show --name-status -z` as the history's file tree reads it.
struct CommitFilesParserTests {
    @Test func readsStatusesRenamesAndCopies() {
        let fields = [
            "M", "src/a.swift", "R087", "old/b.swift", "new/b.swift", "D", "gone.txt", "C100", "x", "y", "A", "n",
        ]
        let files = CommitFilesParser.parse(Data((fields.joined(separator: "\0") + "\0").utf8))
        #expect(files.map(\.path) == ["src/a.swift", "new/b.swift", "gone.txt", "y", "n"])
        #expect(files.map(\.index) == [.modified, .renamed, .deleted, .copied, .added])
        #expect(files[1].originalPath == "old/b.swift")
        #expect(files.allSatisfy { $0.worktree == .unmodified })
        #expect(CommitFilesParser.parse(Data()).isEmpty)
    }
}
