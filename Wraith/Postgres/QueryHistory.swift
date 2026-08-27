import Foundation

/// `.wraith/postgres-history.json` (postgres R20): every run, 500 at most, pinned ones kept
/// out of the FIFO; nothing from a result is ever written.
///
/// Plain `Codable` + an atomic write, the same policy as `state.json` (config R9): a missing
/// file is an empty history, an unreadable one is set aside as `.bak`.
nonisolated struct QueryHistory: Codable, Equatable, Sendable {
    struct Entry: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let text: String
        /// `user@host/database`.
        let connection: String
        let date: Date
        let durationMilliseconds: Int
        let rowCount: Int?
        let error: String?
        var isPinned: Bool

        init(
            id: UUID = UUID(), text: String, connection: String, date: Date, durationMilliseconds: Int,
            rowCount: Int?, error: String?, isPinned: Bool = false
        ) {
            self.id = id
            self.text = text
            self.connection = connection
            self.date = date
            self.durationMilliseconds = durationMilliseconds
            self.rowCount = rowCount
            self.error = error
            self.isPinned = isPinned
        }

        /// The list shows the first non-empty line.
        var subject: String {
            text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        }
    }

    static let version = 1
    static let limit = 500
    static let empty = QueryHistory(version: version, entries: [])

    let version: Int
    /// Newest first.
    private(set) var entries: [Entry]

    /// R20: appended at the top; over the bound, the oldest unpinned entry leaves.
    mutating func append(_ entry: Entry) {
        entries.insert(entry, at: 0)
        while entries.count > Self.limit, let index = entries.lastIndex(where: { !$0.isPinned }) {
            entries.remove(at: index)
        }
    }

    mutating func setPinned(_ id: UUID, _ isPinned: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned = isPinned
    }

    /// R20: case-insensitive over the text; empty matches everything.
    func search(_ needle: String) -> [Entry] {
        let trimmed = needle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Disk

    static func file(under root: URL) -> URL {
        root.appending(components: ".wraith", "postgres-history.json")
    }

    @concurrent
    static func load(root: URL) async -> QueryHistory {
        let file = file(under: root)
        guard let data = try? Data(contentsOf: file) else { return .empty }
        guard let history = try? decoder.decode(QueryHistory.self, from: data), history.version == version else {
            let backup = file.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: file, to: backup)
            return .empty
        }
        return history
    }

    /// A temporary file next to it, then `replaceItemAt`; `.wraith/` created if needed.
    @concurrent
    static func write(_ history: QueryHistory, root: URL) async throws {
        let file = file(under: root)
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: "postgres-history.json.tmp")
        try encoder.encode(history).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
