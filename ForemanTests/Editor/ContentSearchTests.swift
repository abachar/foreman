import Foundation
import Testing

@testable import Foreman

/// editor R20, R21: the command lines and the parsers of both tools, and the cap.
struct ContentSearchTests {
    private let rg = ContentSearch.Tool.ripgrep(URL(filePath: "/opt/homebrew/bin/rg"))
    private let grep = ContentSearch.Tool.grep(URL(filePath: "/usr/bin/grep"))

    @Test func buildsRipgrepArguments() {
        var options = ContentSearch.Options(query: "foo bar")
        var arguments = ContentSearch.arguments(for: options, tool: rg)
        #expect(arguments.prefix(4) == ["--json", "--no-messages", "--no-config", "-i"])
        #expect(arguments.contains("-F"))
        #expect(arguments.suffix(4) == ["-e", "foo bar", "--", "."])
        #expect(arguments.contains("!node_modules"))
        options = ContentSearch.Options(
            query: "a.*b", isCaseSensitive: true, isWholeWord: true, isRegex: true, include: "src/**/*.ts")
        arguments = ContentSearch.arguments(for: options, tool: rg)
        #expect(arguments.contains("-s") && arguments.contains("-w") && !arguments.contains("-F"))
        #expect(arguments.contains("src/**/*.ts"))
    }

    @Test func buildsGrepArguments() {
        let options = ContentSearch.Options(query: "x", isRegex: true, include: "src/**/*.ts")
        let arguments = ContentSearch.arguments(for: options, tool: grep)
        #expect(arguments.prefix(3) == ["-rnI", "--null", "-E"])
        #expect(arguments.contains("-i"))
        #expect(arguments.contains("--include=*.ts"))
        #expect(arguments.contains("--exclude-dir=.git"))
        #expect(arguments.suffix(4) == ["-e", "x", "--", "."])
    }

    @Test func parsesRipgrepMatchesOnly() throws {
        let line =
            #"{"type":"match","data":{"path":{"text":"./src/a.swift"},"lines":{"text":"  let café = 1\n"},"line_number":7,"absolute_offset":0,"submatches":[{"match":{"text":"café"},"start":6,"end":11}]}}"#
        let match = try #require(ContentSearch.parseRipgrep(line))
        #expect(match.path == "src/a.swift")
        #expect(match.line == 7)
        #expect(match.text == "  let café = 1")
        #expect(match.ranges == [NSRange(location: 6, length: 4)])
        #expect(ContentSearch.parseRipgrep(#"{"type":"begin","data":{"path":{"text":"x"}}}"#) == nil)
        #expect(ContentSearch.parseRipgrep("not json") == nil)
    }

    @Test func parsesGrepLinesAndFindsTheRanges() throws {
        let options = ContentSearch.Options(query: "let")
        let match = try #require(ContentSearch.parseGrep("./src/a.swift\u{0}3:let a = 1; let b = 2", options: options))
        #expect(match.path == "src/a.swift")
        #expect(match.line == 3)
        #expect(match.ranges == [NSRange(location: 0, length: 3), NSRange(location: 11, length: 3)])
        #expect(ContentSearch.parseGrep("no separator", options: options) == nil)
        let word = ContentSearch.ranges(of: ContentSearch.Options(query: "let", isWholeWord: true), in: "letter let")
        #expect(word == [NSRange(location: 7, length: 3)])
    }

    /// editor R21: exit 1 is "no matches" for both tools; only a real error becomes one.
    @Test func mapsExitStatusesToTypedFailures() {
        #expect(ContentSearch.failure(status: 0, tool: rg, stderr: "") == nil)
        #expect(ContentSearch.failure(status: 1, tool: rg, stderr: "") == nil)
        #expect(ContentSearch.failure(status: 1, tool: grep, stderr: "") == nil)
        #expect(
            ContentSearch.failure(status: 2, tool: rg, stderr: "regex parse error:\n  unclosed group\n")
                == .searchFailed("regex parse error: unclosed group"))
        #expect(
            ContentSearch.failure(status: 2, tool: grep, stderr: "")
                == .searchFailed("Search tool exited with status 2"))
    }

    /// editor R21: an invalid regex must surface as an error, not as "No results".
    @Test func surfacesAGrepFailureInsteadOfNoResults() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ContentSearchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("some text\n".utf8).write(to: root.appending(path: "a.txt"))
        var thrown: EditorError?
        do {
            let options = ContentSearch.Options(query: "(", isRegex: true)
            for try await _ in ContentSearch.run(options, tool: grep, root: root) {}
        } catch let error as EditorError {
            thrown = error
        }
        guard case .searchFailed = thrown else {
            Issue.record("expected a searchFailed error, got \(String(describing: thrown))")
            return
        }
    }

    @Test func runsGrepAndStopsAtTheCap() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ContentSearchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("needle here\nnothing\nNEEDLE again\n".utf8).write(to: root.appending(path: "a.txt"))
        try Data("needle in excluded\n".utf8).write(to: root.appending(path: "node_modules/b.txt"))
        var matches: [ContentSearch.Match] = []
        for try await match in ContentSearch.run(ContentSearch.Options(query: "needle"), tool: grep, root: root) {
            matches.append(match)
        }
        #expect(matches.map(\.line) == [1, 3])
        #expect(matches.allSatisfy { $0.path == "a.txt" })
    }
}

/// Search speed (editor R21 amended 2026-10-17, M22 22.4).
@MainActor
struct SearchSpeedTests {
    private func match(_ path: String, _ line: Int) -> ContentSearch.Match {
        ContentSearch.Match(path: path, line: line, text: "x", ranges: [])
    }

    @Test func aBatchIsFiledUnderItsFilesInOrder() {
        let model = SearchModel(root: URL(filePath: "/ws"), tool: .grep(URL(filePath: "/usr/bin/grep")))
        model.add([match("a.swift", 1), match("b.swift", 2), match("a.swift", 3)])
        model.add([match("c.swift", 1), match("b.swift", 9)])
        #expect(model.groups.map(\.path) == ["a.swift", "b.swift", "c.swift"])
        #expect(model.groups[0].matches.map(\.line) == [1, 3])
        #expect(model.groups[1].matches.map(\.line) == [2, 9])
        #expect(model.matchCount == 5)
    }

    @Test func theFirstMatchShowsAtOnceTheOthersWaitForTheBatch() {
        let now = ContinuousClock.now
        #expect(SearchModel.shouldFlush(since: now, now: now, isFirst: true))
        #expect(!SearchModel.shouldFlush(since: now, now: now + .milliseconds(10), isFirst: false))
        #expect(SearchModel.shouldFlush(since: now, now: now + .milliseconds(50), isFirst: false))
    }

    @Test func aLongLineIsCutAroundItsFirstMatch() {
        let text = String(repeating: "x", count: 5000) + "needle" + String(repeating: "y", count: 5000)
        let shown = ContentSearch.window(text, ranges: [NSRange(location: 5000, length: 6)])
        let cut = shown.text as NSString
        #expect(cut.length == ContentSearch.maximumLine + 2)
        #expect(shown.text.hasPrefix("\u{2026}") && shown.text.hasSuffix("\u{2026}"))
        #expect(shown.ranges.count == 1)
        #expect(cut.substring(with: shown.ranges[0]) == "needle")
        let short = ContentSearch.window("let a = 1", ranges: [NSRange(location: 4, length: 1)])
        #expect(short.text == "let a = 1")
        #expect(short.ranges == [NSRange(location: 4, length: 1)])
    }
}

/// The search's stdout cut into lines (editor R21, the hang fixed on 2026-10-17).
struct SearchLineBufferTests {
    @Test func linesAreCutAtNewlinesWhateverTheChunks() {
        var buffer = ContentSearch.LineBuffer()
        #expect(buffer.append(Data("{\"a\"".utf8)).isEmpty)
        #expect(buffer.append(Data(":1}\n{\"b\":2}\n{\"c".utf8)) == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(buffer.append(Data("\":3}".utf8)).isEmpty)
        #expect(buffer.finish() == #"{"c":3}"#)
        #expect(buffer.finish() == nil)
        #expect(buffer.append(Data("x\n\ny\n".utf8)) == ["x", "", "y"])
    }

    /// More than a pipe's worth of output, stdout and stderr read together: this hung forever
    /// while both went through `FileHandle.bytes`.
    @Test func aLargeOutputIsReadToTheCap() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "foreman-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let line = "let component = Component() // " + String(repeating: "x", count: 200) + "\n"
        for index in 0..<30 {
            try String(repeating: line, count: 100).write(
                to: root.appending(path: "file\(index).swift"), atomically: true, encoding: .utf8)
        }
        let tool = ContentSearch.locateTool()
        var count = 0
        for try await _ in ContentSearch.run(ContentSearch.Options(query: "Component"), tool: tool, root: root) {
            count += 1
        }
        #expect(count == ContentSearch.limit)
    }
}
