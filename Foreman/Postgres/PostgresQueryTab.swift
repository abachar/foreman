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

    let id: TabID
    let title: String
    /// R9: persisted through the payload; the view mirrors it.
    var text: String
    /// R19: where the view must place the cursor, consumed by the view.
    var requestedCursor: Int?
    /// R8: text the view must insert at the cursor, consumed by the view.
    var pendingInsertion: String?
    /// R20: a history entry replacing the buffer, consumed by the view.
    var pendingReplacement: String?
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
        requestedCursor = cursor
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
