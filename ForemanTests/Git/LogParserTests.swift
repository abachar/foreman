import Foundation
import Testing

@testable import Foreman

/// `log --format -z` over fixtures, the query and the menu arguments (git R18, R19, R27).
struct LogParserTests {
    private func record(
        _ sha: String, _ short: String, _ author: String, _ date: String, _ refs: String, _ subject: String
    ) -> String {
        [sha, short, author, date, refs, subject].joined(separator: "\u{1f}")
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

    @Test func relativeDates() {
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
        query.skip = 200
        #expect(query.fields == [.subject, .author])
        #expect(query.arguments(field: .subject).contains("--grep=ada"))
        #expect(query.arguments(field: .author).contains("--author=ada"))
        #expect(query.arguments(field: .author).contains("--skip=200"))
        query.path = "src/a.swift"
        #expect(query.arguments(field: nil).suffix(3) == ["--follow", "--", "src/a.swift"])
    }

    @Test func mergesPagesBySha() {
        func commit(_ sha: String, _ seconds: TimeInterval) -> GitCommit {
            GitCommit(
                sha: sha, shortSha: sha, author: "", date: Date(timeIntervalSince1970: seconds), refs: [], subject: "")
        }
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
