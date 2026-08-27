import SwiftUI

/// The `postgres.query` center tab (postgres R9, R10, R14, R17, R19): the header, the editor,
/// a draggable separator, the results.
struct PostgresQueryView: View {
    let tab: PostgresQueryTab
    let connection: PostgresModel
    let feature: PostgresFeature
    let theme: ThemeService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VSplitView {
                SQLEditorView(
                    tab: tab, theme: theme, onRun: { feature.run(tab) }, onStop: { feature.stop() }
                )
                .frame(minHeight: 80)
                results
                    .frame(minHeight: 80)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: theme.color(for: connection.state)))
                .frame(width: 8, height: 8)
            Text(connection.label ?? "Postgres")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if tab.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                feature.run(tab)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(tab.isRunning || connection.configMessage != nil)
            .help("Run the selection, or the whole buffer (⌘↩)")
            Button {
                feature.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!tab.isRunning)
            .help("Cancel on the server (⌘.)")
            Toggle(isOn: Binding(get: { connection.allowWrites }, set: { feature.setAllowWrites($0) })) {
                Image(systemName: "pencil")
                    .foregroundStyle(connection.allowWrites ? .red : .secondary)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Allow writes (this session only)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var results: some View {
        VStack(spacing: 0) {
            if let error = tab.error {
                // R19: the message, the SQLSTATE, and what to do about it.
                VStack(alignment: .leading, spacing: 2) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if let hint = tab.hint {
                        Text(hint)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            if let message = connection.configMessage {
                ContentUnavailableView {
                    Label("No Database Configured", systemImage: "cylinder")
                } description: {
                    Text(message)
                }
            } else if let result = tab.result, !result.columns.isEmpty {
                grid(result)
                statusBar(result)
            } else if let result = tab.result, !tab.isRunning, tab.error == nil {
                ContentUnavailableView("OK", systemImage: "checkmark.circle", description: Text("No result set."))
                statusBar(result)
            } else if tab.isRunning {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Result", systemImage: "tablecells", description: Text("⌘↩ runs the selection or the buffer."))
            }
        }
    }

    /// R16, the minimum of it until 5.7: text cells, `NULL` dimmed, native column resizing.
    private func grid(_ result: PostgresQueryTab.Result) -> some View {
        Table(result.rows) {
            TableColumnForEach(Array(result.columns.enumerated()), id: \.offset) { index, name in
                TableColumn(name) { row in
                    let value = index < row.cells.count ? row.cells[index] : nil
                    Text(value ?? QueryCell.nullText)
                        .font(Font(theme.editorFont))
                        .foregroundStyle(value == nil ? .tertiary : .primary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// R17: `N rows · 42 ms · user@database`.
    private func statusBar(_ result: PostgresQueryTab.Result) -> some View {
        HStack(spacing: 6) {
            Text(result.columns.isEmpty ? "OK" : "\(result.rows.count) rows")
            if result.isTruncated {
                Label(
                    "truncated at \(PostgresFeature.rowLimit) rows, add a LIMIT",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            Text("·")
            Text(
                "\(result.duration.components.seconds * 1000 + result.duration.components.attoseconds / 1_000_000_000_000_000) ms"
            )
            Text("·")
            Text(connection.label ?? "")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
