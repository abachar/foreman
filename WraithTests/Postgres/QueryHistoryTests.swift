import Foundation
import Testing

@testable import Wraith

/// postgres R20: the FIFO, pinning, the file round trip, the `.bak` policy, search.
struct QueryHistoryTests {
    private func entry(_ text: String, pinned: Bool = false) -> QueryHistory.Entry {
        QueryHistory.Entry(
            text: text, connection: "u@h/d", date: Date(timeIntervalSince1970: 1_000), durationMilliseconds: 3,
            rowCount: 1, error: nil, isPinned: pinned)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "QueryHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func newestFirstAndTheOldestUnpinnedLeavesAtTheBound() {
        var history = QueryHistory.empty
        history.append(entry("first", pinned: true))
        for index in 1...QueryHistory.limit {
            history.append(entry("q\(index)"))
        }
        #expect(history.entries.count == QueryHistory.limit)
        #expect(history.entries.first?.text == "q500")
        #expect(history.entries.last?.text == "first")
        #expect(!history.entries.contains { $0.text == "q1" })
    }

    @Test func pinningIsToggledById() {
        var history = QueryHistory.empty
        let pinned = entry("keep")
        history.append(pinned)
        history.setPinned(pinned.id, true)
        #expect(history.entries[0].isPinned)
        history.setPinned(pinned.id, false)
        #expect(!history.entries[0].isPinned)
        history.setPinned(UUID(), true)
    }

    @Test func roundtripsThroughTheFileAndCreatesTheFolder() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var history = QueryHistory.empty
        history.append(entry("SELECT 'é';", pinned: true))
        try await QueryHistory.write(history, root: root)
        #expect(FileManager.default.fileExists(atPath: QueryHistory.file(under: root).path(percentEncoded: false)))
        #expect(await QueryHistory.load(root: root) == history)
    }

    @Test func missingFileIsEmpty() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await QueryHistory.load(root: root) == .empty)
    }

    @Test func unreadableFileIsSetAsideAsBak() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = QueryHistory.file(under: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        #expect(await QueryHistory.load(root: root) == .empty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("bak").path(percentEncoded: false)))
    }

    @Test func searchIsCaseInsensitiveOverTheText() {
        var history = QueryHistory.empty
        history.append(entry("SELECT * FROM users"))
        history.append(entry("select count(*) from orders"))
        #expect(history.search("USERS").map(\.text) == ["SELECT * FROM users"])
        #expect(history.search("select").count == 2)
        #expect(history.search("  ").count == 2)
        #expect(history.search("nothing").isEmpty)
    }

    @Test func subjectIsTheFirstNonEmptyLine() {
        #expect(entry("\n  \n  SELECT 1\nFROM t").subject == "SELECT 1")
    }
}
