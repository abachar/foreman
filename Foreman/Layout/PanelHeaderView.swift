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
            if side == .left, siblings.count > 1 {
                // design R17 (amended 2026-10-17, author): the left slot's tabs share its width,
                // each centred with its icon and title; its panels' actions sit in a bar at their
                // bottom (`PanelFooterView`), as Xcode's navigators do.
                // Each tab keeps its own width (no title cut in two for an equal share); the room
                // left is spread around them.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(siblings, id: \.id) { panel in
                        tab(panel, isCurrent: panel.id == current, showsTitle: true, padding: 6)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: tokens.barHeight)
            } else {
                HStack(spacing: 8) {
                    if siblings.count > 1 {
                        HStack(spacing: 2) {
                            ForEach(siblings, id: \.id) { panel in
                                tab(panel, isCurrent: panel.id == current, showsTitle: true)
                            }
                        }
                        // design R17 (amended 2026-10-17): the tabs are laid out first, the panel's own
                        // controls give way in a narrow slot. Not `fixedSize`: a header wider than its
                        // slot shifted the whole panel's content out of view.
                        .layoutPriority(1)
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
            }
            tokens.separator.color.frame(height: 1)
        }
    }

    private func tab(_ panel: PanelDescriptor, isCurrent: Bool, showsTitle: Bool, padding: CGFloat = 10) -> some View {
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
                if showsTitle {
                    Text(panel.title)
                        .lineLimit(1)
                }
                PanelCountView(badge: panel.badge(), theme: theme)
            }
            .font(theme.font(.title, weight: isCurrent ? .medium : .regular))
            .foregroundStyle((isCurrent ? tokens.textPrimary : tokens.textSecondary).color)
            .padding(.horizontal, padding)
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
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(theme.font(.small, weight: .medium))
                .foregroundStyle(tokens.status(color).color)
        case .count(let count, let color):
            Text("\(count)")
                .font(theme.font(.small, weight: .medium))
                .foregroundStyle(tokens.surface.color)
                .padding(.horizontal, 5)
                .background(tokens.status(color).color, in: Capsule())
        }
    }
}

/// design R17 (amended 2026-10-17, author): the bar at the bottom of a left-slot panel holding its
/// actions, as Xcode's navigators hold theirs — `barHeight` tall, a separator above.
struct PanelFooterView<Content: View>: View {
    let theme: ThemeService
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            tokens.separator.color.frame(height: 1)
            HStack(spacing: 10) {
                content()
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(tokens.textSecondary.color)
            .padding(.horizontal, 10)
            .frame(height: tokens.barHeight - 6)
        }
    }
}
