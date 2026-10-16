import SwiftUI

/// run R6b (amended 2026-10-16, M21 21.3), design R15: the toolbar's last widget — a rule, then on
/// one plate the current command with its last state and a chevron (the menu), ▶ (↻ while it
/// runs) and ■.
struct RunWidget: View {
    /// What the icon before the command says (reference view 08).
    nonisolated enum Icon: Equatable, Sendable {
        case none
        case running
        case succeeded
        case failed

        init(_ state: RunFeature.RunState?) {
            switch state {
            case nil, .idle: self = .none
            case .running: self = .running
            case .succeeded: self = .succeeded
            case .failed: self = .failed
            }
        }
    }

    let run: RunFeature
    let theme: ThemeService
    let openMenu: () -> Void

    var body: some View {
        let tokens = theme.tokens
        let current = run.current
        let state = current.flatMap { run.state(ofCommand: $0.id) }
        let isRunning = state == .running
        HStack(spacing: 0) {
            tokens.border.color
                .frame(width: 1, height: 18)
                .padding(.trailing, 8)
            HStack(spacing: 0) {
                Button(action: openMenu) {
                    HStack(spacing: 6) {
                        icon(Icon(state))
                        Text(current?.name ?? "Run")
                            .font(theme.font(.body, weight: .medium))
                            .foregroundStyle(tokens.textPrimary.color)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(theme.font(.small))
                            .imageScale(.small)
                            .foregroundStyle(tokens.textSecondary.color)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .help(current.map { "\($0.title) — \($0.command)" } ?? "Run a command")
                Button {
                    guard let current else { return }
                    run.launch(current.id)
                } label: {
                    Image(systemName: isRunning ? "arrow.clockwise" : "play.fill")
                        .foregroundStyle(tokens.statusGreen.color)
                        .frame(width: ToolbarButton.height, height: ToolbarButton.height)
                        .contentShape(Rectangle())
                }
                .disabled(current == nil)
                .help(isRunning ? "Restart \(current?.id ?? "")" : "Run \(current?.id ?? "")")
                Button {
                    guard let current else { return }
                    run.stop(current.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundStyle((isRunning ? tokens.statusRed : tokens.textDisabled).color)
                        .frame(width: ToolbarButton.height, height: ToolbarButton.height)
                        .contentShape(Rectangle())
                }
                .disabled(!isRunning)
                .help("Stop \(current?.id ?? "")")
            }
            .buttonStyle(.plain)
            .frame(height: ToolbarButton.height)
            .background(tokens.surfaceRaised.color, in: RoundedRectangle(cornerRadius: ToolbarButton.radius))
        }
        .fixedSize()
    }

    @ViewBuilder
    private func icon(_ icon: Icon) -> some View {
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
