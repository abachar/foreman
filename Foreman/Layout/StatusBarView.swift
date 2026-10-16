import SwiftUI

/// layout (status bar, 2026-10-16): one item the active tab shows on the right of the status bar.
struct StatusItem: Identifiable, Equatable {
    let id: String
    let text: String
    /// A state dot before the text (a language server running, starting, failed).
    var dot: ToolbarBadge.BadgeColor?
    var help: String?
}

/// layout (status bar): the ⊗ / ⚠ counters of the active file.
nonisolated struct ProblemCounts: Equatable, Sendable {
    var errors = 0
    var warnings = 0
}

/// layout (status bar, 2026-10-16), design (status bar): the bar under the zones.
///
/// 28 pt on the window ground: the three slot toggles, the active file's counters, then the
/// active tab's items. It never hides (decision 2026-10-16).
struct StatusBarView: View {
    static let height: CGFloat = 28

    let layout: LayoutManager
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        let tab = layout.model.active.active
        let descriptor = tab.flatMap { layout.tabKinds[$0.kind] }
        HStack(spacing: 2) {
            toggle(.left, icon: "sidebar.left", help: "Left Panel")
            toggle(.bottom, icon: "rectangle.bottomthird.inset.filled", help: "Bottom Panel")
            toggle(.right, icon: "sidebar.right", help: "Right Panel")
            if let counts = tab.flatMap({ descriptor?.problemCounts($0.id) }) ?? layout.projectProblemCounts?() {
                tokens.border.color.frame(width: 1, height: 14)
                    .padding(.horizontal, 8)
                Button {
                    layout.showProblems?()
                } label: {
                    counters(counts)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if let tab, let items = descriptor?.statusItems(tab.id) {
                ForEach(items) { item in
                    HStack(spacing: 5) {
                        if let dot = item.dot {
                            Circle()
                                .fill(tokens.status(dot).color)
                                .frame(width: 6, height: 6)
                        }
                        Text(item.text)
                            .lineLimit(1)
                    }
                    .padding(.leading, 14)
                    .help(item.help ?? "")
                }
            }
        }
        .font(theme.font(.small))
        .foregroundStyle(tokens.textSecondary.color)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(tokens.windowBackground.color)
    }

    /// A slot toggle: shows its last panel or hides the slot; filled while the slot is shown.
    private func toggle(_ side: PanelSide, icon: String, help: String) -> some View {
        let tokens = theme.tokens
        let isOn = layout.panels.visible[side] != nil
        let target = layout.panels.panelToShow(on: side).flatMap { layout.panels[$0]?.title }
        return Button {
            layout.panels.toggle(side)
        } label: {
            Image(systemName: icon)
                .frame(width: 24, height: 20)
                .foregroundStyle((isOn ? tokens.textPrimary : tokens.textSecondary).color)
                .background(isOn ? tokens.border.color : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .help(target.map { "\(help): \($0)" } ?? help)
    }

    private func counters(_ counts: ProblemCounts) -> some View {
        let tokens = theme.tokens
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle((counts.errors > 0 ? tokens.statusRed : tokens.textSecondary).color)
                Text("\(counts.errors)")
            }
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle((counts.warnings > 0 ? tokens.statusOrange : tokens.textSecondary).color)
                Text("\(counts.warnings)")
            }
        }
        .help("Errors and warnings — click to open Problems")
    }
}
