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
            Divider()
            banner
            if let message = connection.configMessage {
                // R2: no section, the message and the example.
                ContentUnavailableView {
                    Label("No Database Configured", systemImage: "cylinder")
                } description: {
                    Text(message)
                        .textSelection(.enabled)
                }
            } else {
                SchemaOutlineView(model: model, feature: feature, theme: theme)
            }
        }
        .sheet(item: Bindable(model).ddl) { document in
            ddlSheet(document)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // R5: the state dot.
            Circle()
                .fill(Color(nsColor: theme.color(for: connection.state)))
                .frame(width: 8, height: 8)
                .help(stateText)
            Text(connection.label ?? "Postgres")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
                    .foregroundStyle(connection.allowWrites ? .red : .secondary)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Allow writes (this session only)")
            Button {
                Task { await model.refresh(nil) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(connection.configMessage != nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var banner: some View {
        if let error = connection.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .lineLimit(3)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        ForEach(connection.warnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
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
                .font(.callout)
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
