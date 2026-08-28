import SwiftUI

/// The empty group (layout R33, R34): agents and recent files on the left, every shortcut on the
/// right, as documentation.
///
/// Everything comes from the features (`HomeEntry`) and the shortcut table; the layout knows
/// none of them inline. Sections without entries are not shown.
struct HomeView: View {
    let layout: LayoutManager
    let theme: ThemeService

    private static let columnWidth: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 24) {
                section("Agents", entries: layout.homeEntries.filter { $0.section == .agents })
                section("Recent", entries: layout.homeEntries.filter { $0.section == .recent })
                Spacer(minLength: 0)
            }
            .frame(width: Self.columnWidth)
            shortcuts
                .frame(width: Self.columnWidth)
        }
        .padding(40)
        // Both columns as one block, centred in the group.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // design R19: the same tokens, no illustration.
        .foregroundStyle(theme.tokens.textPrimary.color)
        .background(theme.tokens.surface.color)
    }

    /// layout R33: the whole table, by feature, in registration order; a row performs the action.
    private var shortcuts: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heading("Shortcuts")
                ForEach(layout.shortcuts.documentation) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.feature.capitalized)
                            .font(theme.font(.small, weight: .medium))
                            .foregroundStyle(theme.tokens.textSecondary.color)
                        ForEach(group.rows) { row in
                            self.row(title: row.title, icon: nil, shortcut: row.shortcut, action: row.perform)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, entries: [HomeEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading(title)
                ForEach(entries) { entry in
                    row(
                        title: entry.title, icon: entry.icon,
                        shortcut: layout.shortcuts.shortcut(for: entry.id)?.description, action: entry.action)
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(theme.font(.title, weight: .medium))
            .foregroundStyle(theme.tokens.textSecondary.color)
    }

    private func row(title: String, icon: String?, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    if let icon, let image = FileIcon.image(named: icon) ?? IconImage.resolve(icon) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(theme.codeFont(.small))
                        .foregroundStyle(theme.tokens.textSecondary.color)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
