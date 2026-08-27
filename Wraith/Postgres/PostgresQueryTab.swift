import AppKit
import Foundation
import Observation

/// One `postgres.query` center tab (postgres R9, R10, R17, R19): its buffer, its last result.
@Observable
@MainActor
final class PostgresQueryTab: Identifiable {
    nonisolated struct Payload: Codable, Equatable, Sendable {
        var title: String
        var text: String

        func encoded() -> String {
            String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
        }

        static func decode(_ payload: String) -> Payload? {
            try? JSONDecoder().decode(Payload.self, from: Data(payload.utf8))
        }
    }

    /// R17: what the status bar shows.
    struct Result: Equatable {
        var columns: [String]
        var rows: [Row]
        var duration: Duration
        var isTruncated = false

        struct Row: Identifiable, Equatable {
            let id: Int
            let cells: [String?]
        }
    }

    let id: TabID
    let title: String
    /// R9: persisted through the payload; the view mirrors it.
    var text: String
    /// R19: where the view must place the cursor, consumed by the view.
    var requestedCursor: Int?
    /// R8: text the view must insert at the cursor, consumed by the view.
    var pendingInsertion: String?
    var selection = NSRange(location: 0, length: 0)
    private(set) var isRunning = false
    private(set) var result: Result?
    private(set) var error: String?
    private(set) var hint: String?
    /// The text view, set by `SQLEditorView` for the commands.
    weak var textView: NSTextView?

    init(id: TabID, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    var payload: Payload {
        Payload(title: title, text: text)
    }

    func start() {
        isRunning = true
        error = nil
        hint = nil
        result = Result(columns: [], rows: [], duration: .zero)
    }

    func setColumns(_ columns: [String]) {
        result?.columns = columns
    }

    func append(_ rows: [Result.Row]) {
        result?.rows.append(contentsOf: rows)
    }

    func finish(duration: Duration, isTruncated: Bool) {
        result?.duration = duration
        result?.isTruncated = isTruncated
        isRunning = false
    }

    func fail(_ error: PostgresError, cursor: Int?) {
        self.error = error.description
        if case .server(_, let state, _) = error {
            hint = QueryExecution.hint(sqlState: state)
        }
        requestedCursor = cursor
        isRunning = false
    }
}
