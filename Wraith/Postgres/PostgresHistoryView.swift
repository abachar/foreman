import SwiftUI

/// The history sheet (postgres R20, US6): search, a click reloads the query, *Pin*.
struct PostgresHistoryView: View {
    let model: PostgresHistoryModel
    let theme: ThemeService
    let onSelect: (QueryHistory.Entry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search queries", text: Bindable(model).filter)
                    .textFieldStyle(.roundedBorder)
                Button("Close") { model.presentedFor = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if !model.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                ContentUnavailableView("No Queries Yet", systemImage: "clock.arrow.circlepath")
            } else {
                List(model.entries) { entry in
                    row(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry) }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 360, idealHeight: 520)
        .task { await model.load() }
    }

    private func row(_ entry: QueryHistory.Entry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.setPinned(entry.id, !entry.isPinned)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(entry.isPinned ? theme.tokens.accent.color : theme.tokens.textSecondary.color)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Unpin" : "Pin (kept beyond the last 500)")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.subject)
                    .font(Font(theme.editorFont))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(entry.connection)
                    Text("·")
                    Text(entry.date, format: .relative(presentation: .named))
                    Text("·")
                    Text("\(entry.durationMilliseconds) ms")
                    if let error = entry.error {
                        Text("·")
                        Text(error)
                            .foregroundStyle(theme.tokens.statusRed.color)
                            .lineLimit(1)
                    } else if let rows = entry.rowCount {
                        Text("·")
                        Text(rows == 1 ? "1 row" : "\(rows) rows")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
