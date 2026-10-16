import SwiftUI

/// editor R51 (2026-10-16, M21 21.7, views 12 and 13): the bottom slot's Problems tab — the scope
/// (current file / project), the error and warning filters with their counts, a message filter,
/// then the problems grouped per file, the *Foreman config* group first; a click opens the place.
struct ProblemsPanelView: View {
    let store: DiagnosticsStore
    @Bindable var model: ProblemsPanelModel
    let editor: EditorFeature
    let layout: LayoutManager
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        let root = editor.workspace.root
        let config = Problems.configRows(
            errors: editor.workspace.configErrors, shortcuts: layout.shortcuts.problems,
            configFile: WorkspaceConfig.file(under: root))
        let files = Array(store.files.values)
        let current = editor.activeTab?.url
        let counts = Problems.counts(files: files, config: config, scope: model.filter.scope, current: current)
        let groups = Problems.groups(files: files, config: config, filter: model.filter, current: current, root: root)
        VStack(spacing: 0) {
            PanelHeaderView(panels: layout.panels, current: EditorFeature.problemsPanelID, theme: theme) {
                EmptyView()
            }
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    pill("Current file", isOn: model.filter.scope == .currentFile) {
                        model.filter.scope = .currentFile
                    }
                    pill("Project", isOn: model.filter.scope == .project) { model.filter.scope = .project }
                }
                .padding(2)
                .background(tokens.surfaceSunken.color, in: RoundedRectangle(cornerRadius: 6))
                tokens.border.color.frame(width: 1, height: 14)
                pill(
                    counts.errors == 1 ? "1 error" : "\(counts.errors) errors", symbol: "xmark.circle",
                    tint: tokens.statusRed, isOn: model.filter.showsErrors
                ) { model.filter.showsErrors.toggle() }
                pill(
                    counts.warnings == 1 ? "1 warning" : "\(counts.warnings) warnings",
                    symbol: "exclamationmark.triangle", tint: tokens.statusOrange, isOn: model.filter.showsWarnings
                ) { model.filter.showsWarnings.toggle() }
                Spacer(minLength: 8)
                TextField("Filter messages", text: $model.filter.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            tokens.separator.color.frame(height: 1)
            if groups.isEmpty {
                ContentUnavailableView(
                    model.filter.scope == .currentFile && current == nil ? "No File" : "No Problems",
                    systemImage: "checkmark.circle",
                    description: Text(
                        model.filter.scope == .currentFile && current == nil
                            ? "The active tab is not a file." : "Nothing the language servers or the config reported.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                rowView(row)
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// design R3: a flat choice — the raised surface (or the accent's tint) when on, bare when off.
    private func pill(
        _ title: String, symbol: String? = nil, tint: ThemeColor? = nil, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        let tokens = theme.tokens
        return Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle((tint ?? tokens.textSecondary).color)
                }
                Text(title)
            }
            .foregroundStyle((isOn ? tokens.textPrimary : tokens.textSecondary).color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                isOn ? (tint == nil ? tokens.surfaceRaised.color : tokens.accent.color.opacity(0.22)) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupHeader(_ group: Problems.Group) -> some View {
        let tokens = theme.tokens
        return HStack(spacing: 6) {
            if group.isConfig {
                Image(systemName: "gearshape")
                    .foregroundStyle(tokens.textSecondary.color)
            } else if let icon = FileIcon.image(named: FileIcon.name(for: group.title)) {
                Image(nsImage: icon)
            }
            Text(group.title)
                .font(theme.font(.body, weight: .medium))
                .foregroundStyle(tokens.textPrimary.color)
            if let detail = group.detail {
                Text(detail)
                    .foregroundStyle(tokens.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text("\(group.rows.count)")
                .font(theme.font(.small))
                .foregroundStyle(tokens.textSecondary.color)
                .padding(.horizontal, 6)
                .background(tokens.surfaceRaised.color, in: Capsule())
        }
    }

    private func rowView(_ row: Problems.Row) -> some View {
        let tokens = theme.tokens
        return Button {
            guard let url = row.url else { return }
            editor.open(url, preview: true, line: row.line)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: row.isError ? "xmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle((row.isError ? tokens.statusRed : tokens.statusOrange).color)
                Text(row.message)
                    .foregroundStyle(tokens.textPrimary.color)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let source = row.source {
                    Text(source)
                        .foregroundStyle(tokens.textSecondary.color)
                        .frame(width: 90, alignment: .leading)
                }
                Text(row.line.map { line in row.column.map { "\(line):\($0)" } ?? "\(line)" } ?? "")
                    .font(theme.codeFont(.small))
                    .foregroundStyle(tokens.textSecondary.color)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.leading, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(row.message)
    }
}
