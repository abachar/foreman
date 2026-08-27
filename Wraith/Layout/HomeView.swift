import SwiftUI

/// The empty group (layout R33, R34): agents, main actions with their shortcuts, recent files.
///
/// Everything comes from the features (`HomeEntry`) and the shortcut table; the layout only
/// lists its own actions. Sections without entries are not shown.
struct HomeView: View {
    let layout: LayoutManager
    let theme: ThemeService

    private static let layoutActionIDs = ["layout.split.vertical", "layout.split.horizontal"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("Agents", entries: layout.homeEntries.filter { $0.section == .agents })
            actions
            section("Recent", entries: layout.homeEntries.filter { $0.section == .recent })
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // design R19: the same tokens, no illustration.
        .foregroundStyle(theme.tokens.textPrimary.color)
        .background(theme.tokens.surface.color)
    }

    @ViewBuilder
    private var actions: some View {
        let entries = layout.homeEntries.filter { $0.section == .actions }
        let layoutActions = layout.shortcuts.actions.filter { Self.layoutActionIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)
                .foregroundStyle(theme.tokens.textSecondary.color)
            ForEach(entries) { entry in
                row(
                    title: entry.title, icon: entry.icon, shortcut: layout.shortcuts.shortcut(for: entry.id),
                    action: entry.action)
            }
            ForEach(layoutActions, id: \.id) { action in
                row(
                    title: action.title, icon: "rectangle.split.2x1",
                    shortcut: layout.shortcuts.shortcut(for: action.id),
                    action: action.perform)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, entries: [HomeEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.tokens.textSecondary.color)
                ForEach(entries) { entry in
                    row(
                        title: entry.title, icon: entry.icon, shortcut: layout.shortcuts.shortcut(for: entry.id),
                        action: entry.action)
                }
            }
        }
    }

    private func row(title: String, icon: String, shortcut: Shortcut?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    if let image = FileIcon.image(named: icon) ?? IconImage.resolve(icon) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                Spacer()
                if let shortcut {
                    Text(shortcut.description)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.tokens.textSecondary.color)
                }
            }
            .frame(maxWidth: 360)
        }
        .buttonStyle(.plain)
    }
}
