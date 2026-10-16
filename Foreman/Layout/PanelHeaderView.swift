import SwiftUI

/// design R17 (amended 2026-10-16): the header of a panel island — one tab per panel registered
/// on its slot (icon, title, count), the panel's own controls on the right, a separator under it.
///
/// layout R3 (amended 2026-10-16): a click on a tab shows that panel in the slot, the one it
/// replaces keeps its state (R4, R5). A slot holding one panel shows its title alone.
struct PanelHeaderView<Trailing: View>: View {
    let panels: PanelManager
    let current: PanelID
    let theme: ThemeService
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let tokens = theme.tokens
        let side = panels[current]?.side ?? .left
        let siblings = panels.panels(on: side)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if siblings.count > 1 {
                    HStack(spacing: 2) {
                        ForEach(siblings, id: \.id) { panel in
                            tab(panel, isCurrent: panel.id == current)
                        }
                    }
                } else {
                    Text(panels[current]?.title ?? "")
                        .font(theme.font(.title, weight: .medium))
                        .foregroundStyle(tokens.textPrimary.color)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                Spacer(minLength: 0)
                trailing()
                if side == .bottom {
                    // layout R3: the bottom slot hides from its own header (view 05).
                    Button {
                        panels.hide(.bottom)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Panel")
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: tokens.barHeight)
            tokens.separator.color.frame(height: 1)
        }
    }

    private func tab(_ panel: PanelDescriptor, isCurrent: Bool) -> some View {
        let tokens = theme.tokens
        return Button {
            panels.show(panel.id)
        } label: {
            HStack(spacing: 6) {
                if let image = IconImage.resolve(panel.icon) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                Text(panel.title)
                    .lineLimit(1)
                PanelCountView(badge: panel.badge(), theme: theme)
            }
            .font(theme.font(.title, weight: isCurrent ? .medium : .regular))
            .foregroundStyle((isCurrent ? tokens.textPrimary : tokens.textSecondary).color)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            // design R5: the shown tab carries the accent rule on its bottom edge.
            .overlay(alignment: .bottom) {
                if isCurrent {
                    tokens.accent.color.frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(panel.title)
    }
}

/// design R17: the number on a panel tab — a pill in the badge's state color, or plain secondary
/// text for a count without a color.
struct PanelCountView: View {
    let badge: ToolbarBadge
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        switch badge {
        case .none:
            EmptyView()
        case .dot(let color):
            Circle()
                .fill(tokens.status(color).color)
                .frame(width: 6, height: 6)
        case .count(let count, let color):
            Text("\(count)")
                .font(theme.font(.small, weight: .medium))
                .foregroundStyle(tokens.surface.color)
                .padding(.horizontal, 5)
                .background(tokens.status(color).color, in: Capsule())
        }
    }
}
