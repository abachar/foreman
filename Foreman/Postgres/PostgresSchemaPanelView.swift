import SwiftUI

/// The right panel `postgres.schema` (postgres R2, R5–R8): the header with the state dot, the
/// banner, the filter, the tree.
struct PostgresSchemaPanelView: View {
    let model: PostgresSchemaModel
    let connection: PostgresModel
    let feature: PostgresFeature
    let theme: ThemeService

    var body: some View {
        VStack(spacing: 0) {
            header
            banner
            if let message = connection.configMessage {
                // R2: no section, the message and the example.
                ContentUnavailableView {
                    Label("No Database Configured", systemImage: "cylinder")
                } description: {
                    Text(message)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SchemaOutlineView(model: model, feature: feature, theme: theme, font: theme.interfaceFont())
            }
        }
        .sheet(item: Bindable(model).ddl) { document in
            ddlSheet(document)
        }
    }

    private var header: some View {
        PanelHeaderView(title: connection.label ?? "Postgres", theme: theme) {
            // R5: the state dot.
            Circle()
                .fill(Color(nsColor: theme.color(for: connection.state)))
                .frame(width: 8, height: 8)
                .help(stateText)
            TextField("Filter", text: Bindable(model).filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            Toggle(isOn: Bindable(model).showsSystemSchemas) {
                Image(systemName: "gearshape")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Show system schemas")
            .onChange(of: model.showsSystemSchemas) { _, _ in
                Task { await model.refresh(nil) }
            }
            Toggle(isOn: Binding(get: { connection.allowWrites }, set: { feature.setAllowWrites($0) })) {
                Image(systemName: "pencil")
                    .foregroundStyle(
                        connection.allowWrites ? theme.tokens.statusRed.color : theme.tokens.textSecondary.color)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            // R11: the guard is a session setting, so free-form SQL that turns
            // `default_transaction_read_only` off is not stopped by it; the help text says so.
            .help(
                "Allow writes (this session only). SQL that sets default_transaction_read_only off "
                    + "escapes this guard.")
            Button {
                Task { await model.refresh(nil) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(connection.configMessage != nil)
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let error = connection.error {
            BannerView(text: error, icon: "exclamationmark.triangle", tone: .error, theme: theme)
        }
        ForEach(connection.warnings, id: \.self) { warning in
            BannerView(text: warning, icon: "exclamationmark.triangle", tone: .warning, theme: theme)
        }
    }

    private var stateText: String {
        switch connection.state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error(let message): return message
        }
    }

    private func ddlSheet(_ document: PostgresSchemaModel.DDLDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(SchemaDDL.disclaimer, systemImage: "info.circle")
                .font(theme.font())
                .foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(document.text)
                    .font(Font(theme.editorFont))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Copy") { feature.copy(document.text) }
                Button("Close") { model.ddl = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 320, idealHeight: 480)
    }
}
