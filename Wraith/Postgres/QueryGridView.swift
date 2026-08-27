import SwiftUI

/// The result grid (postgres R16): a SwiftUI `Table` — sorting, resizable columns and row
/// selection are native; `cmd+c` copies the selection (or everything) as TSV; a double click
/// shows the row's whole values, `json` pretty-printed.
struct QueryGridView: View {
    let tab: PostgresQueryTab
    let result: QueryResult
    let theme: ThemeService
    let onCopy: (String) -> Void
    @State private var detail: QueryResult.Row?

    var body: some View {
        Table(tab.sortedRows, selection: Bindable(tab).gridSelection, sortOrder: Bindable(tab).sortOrder) {
            TableColumnForEach(Array(result.columns.enumerated()), id: \.offset) { index, column in
                TableColumn(header(column), sortUsing: QueryColumnComparator(column: index)) { row in
                    let value = index < row.values.count ? row.values[index] : QueryValue.null
                    Text(value.displayText)
                        .font(Font(theme.editorFont))
                        .foregroundStyle(value == .null ? .tertiary : .primary)
                        .lineLimit(1)
                        .help(value.displayText)
                }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button("Copy as TSV") { onCopy(tab.copyText) }
            if let id = ids.first, let row = tab.sortedRows.first(where: { $0.id == id }) {
                Button("Show Row") { detail = row }
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = tab.sortedRows.first(where: { $0.id == id }) {
                detail = row
            }
        }
        .copyable([tab.copyText])
        .sheet(item: $detail) { row in
            rowSheet(row)
        }
    }

    private func header(_ column: QueryResult.Column) -> Text {
        Text("\(column.name)  \(Text(column.type).foregroundStyle(.secondary).font(theme.font(.small)))")
    }

    /// Edge cases: the full content of every cell of the row.
    private func rowSheet(_ row: QueryResult.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(result.columns.enumerated()), id: \.offset) { index, column in
                        let value = index < row.values.count ? row.values[index] : QueryValue.null
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(column.name)  \(column.type)")
                                .font(theme.font(.small))
                                .foregroundStyle(.secondary)
                            Text(value.detailText)
                                .font(Font(theme.editorFont))
                                .foregroundStyle(value == .null ? .tertiary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(8)
            }
            HStack {
                Spacer()
                Button("Copy Row as TSV") { onCopy(QueryResult.tsv(columns: result.columns, rows: [row])) }
                Button("Close") { detail = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 640, minHeight: 300, idealHeight: 480)
    }
}
