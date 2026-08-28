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
            theme.tokens.separator.color.frame(height: 1)
            VSplitView {
                SQLEditorView(
                    tab: tab, theme: theme, onRun: { feature.run(tab) }, onStop: { feature.stop() }
                )
                .frame(maxWidth: .infinity, minHeight: 80)
                results
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: theme.color(for: connection.state)))
                .frame(width: 8, height: 8)
            Text(connection.label ?? "Postgres")
                .font(theme.font(.title, weight: .medium))
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
                    .foregroundStyle(
                        connection.allowWrites ? theme.tokens.statusRed.color : theme.tokens.textSecondary.color)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Allow writes (this session only)")
            Button {
                feature.showHistory(for: tab)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Query history")
        }
        .padding(.horizontal, 10)
        .frame(height: theme.tokens.barHeight)
        .background(theme.tokens.surfaceRaised.color)
        // R20: the sheet belongs to the tab it was opened for.
        .sheet(
            isPresented: Binding(
                get: { feature.history.presentedFor == tab.id }, set: { if !$0 { feature.history.presentedFor = nil } })
        ) {
            PostgresHistoryView(model: feature.history, theme: theme) { entry in
                feature.history.presentedFor = nil
                tab.pendingReplacement = entry.text
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        VStack(spacing: 0) {
            if let error = tab.error {
                // R19: the message, the SQLSTATE, and what to do about it.
                VStack(alignment: .leading, spacing: 2) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.tokens.statusRed.color)
                    if let hint = tab.hint {
                        Text(hint)
                            .foregroundStyle(theme.tokens.textSecondary.color)
                    }
                }
                .font(theme.font())
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.tokens.surfaceRaised.color)
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

    private func grid(_ result: QueryResult) -> some View {
        QueryGridView(tab: tab, result: result, theme: theme, onCopy: { feature.copy($0) })
    }

    /// R17: `N rows · 42 ms · user@database`.
    private func statusBar(_ result: QueryResult) -> some View {
        HStack(spacing: 6) {
            Text(result.columns.isEmpty ? "OK" : result.countText)
            if result.isTruncated {
                Label(
                    "truncated at \(PostgresFeature.rowLimit) rows, add a LIMIT",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(theme.tokens.statusOrange.color)
            }
            Text("·")
            Text(result.durationText)
            Text("·")
            Text(connection.label ?? "")
            Spacer()
        }
        .font(theme.font(.small))
        .foregroundStyle(theme.tokens.textSecondary.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(theme.tokens.surfaceRaised.color)
    }
}
