import AppKit
import Foundation
import Observation

/// One `postgres.query` center tab (postgres R9, R10, R16, R17, R19): its buffer, its last result.
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

    /// What the view must still do to the buffer (postgres R8, R19, R20).
    ///
    /// A version rather than fields the view clears: a `NSViewRepresentable` may not write back
    /// to observed state while SwiftUI is updating it, so the request stays here and the
    /// coordinator remembers the last version it applied.
    nonisolated struct PendingEdit: Equatable, Sendable {
        var version = 0
        /// R20: a history entry replacing the whole buffer.
        var replacement: String?
        /// R8: a name inserted at the cursor.
        var insertion: String?
        /// R19: where the cursor must go.
        var cursor: Int?
    }

    let id: TabID
    let title: String
    /// R9: persisted through the payload; the view mirrors it.
    var text: String
    /// R8, R19, R20: the last request made to the view; applied once, never cleared from a view
    /// update.
    private(set) var pending = PendingEdit()
    var selection = NSRange(location: 0, length: 0)
    private(set) var isRunning = false
    private(set) var result: QueryResult?
    /// R16: the loaded rows in the grid's order.
    private(set) var sortedRows: [QueryResult.Row] = []
    var sortOrder: [QueryColumnComparator] = [] {
        didSet { resort() }
    }
    var gridSelection: Set<Int> = []
    private(set) var error: String?
    private(set) var hint: String?
    /// The text view, set by `SQLEditorView` for the commands; not observed, since the view
    /// assigns it from its own update pass.
    @ObservationIgnored weak var textView: NSTextView?

    init(id: TabID, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    var payload: Payload {
        Payload(title: title, text: text)
    }

    // MARK: - Requests to the view (R8, R19, R20)

    /// R20: a history entry replaces the whole buffer.
    func requestReplacement(_ text: String) {
        pending = PendingEdit(version: pending.version + 1, replacement: text)
    }

    /// R8: a schema name is inserted at the cursor.
    func requestInsertion(_ text: String) {
        pending = PendingEdit(version: pending.version + 1, insertion: text)
    }

    /// R19: the cursor goes to the server's error position.
    func requestCursor(_ location: Int) {
        pending = PendingEdit(version: pending.version + 1, cursor: location)
    }

    func start() {
        isRunning = true
        error = nil
        hint = nil
        result = QueryResult(columns: [], rows: [], duration: .zero)
        sortedRows = []
        gridSelection = []
    }

    func setColumns(_ columns: [QueryResult.Column]) {
        result?.columns = columns
    }

    func append(_ rows: [QueryResult.Row]) {
        guard !rows.isEmpty else { return }
        result?.rows.append(contentsOf: rows)
        resort()
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
        if let cursor {
            requestCursor(cursor)
        }
        isRunning = false
    }

    private func resort() {
        guard let result else { return }
        if let comparator = sortOrder.first {
            sortedRows = QueryResult.sorted(result.rows, by: comparator.column, ascending: comparator.order == .forward)
        } else {
            sortedRows = result.rows
        }
    }

    /// R16: what `cmd+c` copies — the selected rows, or everything. The rows travel as values;
    /// the TSV is joined only when the clipboard reads it.
    var clipboard: QueryClipboard {
        QueryClipboard(columns: result?.columns ?? [], rows: sortedRows, selection: gridSelection)
    }

    /// R16: the selected rows, or everything, as TSV.
    var copyText: String {
        result == nil ? "" : clipboard.text
    }
}
