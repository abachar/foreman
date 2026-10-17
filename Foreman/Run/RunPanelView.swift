import SwiftUI

/// run (panel, 2026-10-16, M21 21.5, reference view 08): the bottom slot's Run tab — one sub-tab
/// per command run, with its state; the shown one's command and pid, *Restart*, *Stop*,
/// *Clear scrollback*; its output under them.
struct RunPanelView: View {
    let run: RunFeature
    let terminal: TerminalService
    let panels: PanelManager
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            PanelHeaderView(panels: panels, current: RunFeature.panelID, theme: theme) { EmptyView() }
            if let selected = run.selected, let session = run.sessions[selected] {
                bar(selected: selected, session: session)
                tokens.separator.color.frame(height: 1)
                // debug R11: the adapter's own words, until the command is launched again.
                if let banner = run.banners[selected] {
                    BannerView(
                        text: banner, icon: "ladybug", tone: .error, theme: theme,
                        onDismiss: { run.dismissBanner(for: selected) })
                }
                if let view = terminal.view(for: session) {
                    view
                        // One surface per session: SwiftUI must not reuse the previous one's view.
                        .id(session)
                }
            } else {
                ContentUnavailableView(
                    "No Command Run Yet", systemImage: "play",
                    description: Text("Launch one from the Run widget or with \u{2318}R.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func bar(selected: String, session: TabID) -> some View {
        let tokens = theme.tokens
        let tab = terminal.tab(session)
        let isRunning = tab?.isRunning == true
        return HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(run.sessionOrder, id: \.self) { id in
                        chip(id, isSelected: id == selected)
                    }
                }
            }
            Spacer(minLength: 12)
            if let tab {
                Text([tab.command, tab.pid.map { "pid \($0)" }].compactMap(\.self).joined(separator: " \u{00B7} "))
                    .font(theme.codeFont(.small))
                    .foregroundStyle(tokens.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            button("arrow.clockwise", help: "Restart", tint: tokens.statusGreen) { run.restartSelected() }
            button("stop.fill", help: "Stop (\u{2318}.)", tint: isRunning ? tokens.statusRed : tokens.textDisabled) {
                run.stop(selected)
            }
            .disabled(!isRunning)
            button("circle.slash", help: "Clear Scrollback", tint: tokens.textSecondary) { run.clearSelected() }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private func chip(_ id: String, isSelected: Bool) -> some View {
        let tokens = theme.tokens
        let state = run.state(ofCommand: id)
        return Button {
            run.select(id)
        } label: {
            HStack(spacing: 5) {
                RunStateIcon(icon: RunWidget.Icon(state), theme: theme)
                Text(run.command(id)?.name ?? id)
                    .lineLimit(1)
            }
            .font(theme.font(.body))
            .foregroundStyle((isSelected ? tokens.textPrimary : tokens.textSecondary).color)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isSelected ? tokens.surfaceRaised.color : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(run.command(id)?.title ?? id)
        .contextMenu {
            Button("Close") { run.close(id) }
        }
    }

    private func button(
        _ symbol: String, help: String, tint: ThemeColor, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint.color)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The state icon of a command (run R10, view 08): ✓, ✗, a dot while it runs, nothing before.
struct RunStateIcon: View {
    let icon: RunWidget.Icon
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        switch icon {
        case .none:
            EmptyView()
        case .running:
            Circle()
                .fill(tokens.statusOrange.color)
                .frame(width: 6, height: 6)
        case .succeeded:
            Image(systemName: "checkmark")
                .imageScale(.small)
                .foregroundStyle(tokens.statusGreen.color)
        case .failed:
            Image(systemName: "xmark")
                .imageScale(.small)
                .foregroundStyle(tokens.statusRed.color)
        }
    }
}
