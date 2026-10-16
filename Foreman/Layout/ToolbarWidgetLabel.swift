import SwiftUI

/// design R15 (amended 2026-10-16): the face of a toolbar widget that opens a menu — a leading
/// mark, a title, an optional grey pill, a chevron — on the plate of `ToolbarButton`.
struct ToolbarWidgetLabel<Leading: View>: View {
    let theme: ThemeService
    let title: String
    var detail: String?
    var help: String = ""
    let openMenu: () -> Void
    @ViewBuilder let leading: () -> Leading

    @State private var isHovered = false

    var body: some View {
        let tokens = theme.tokens
        Button(action: openMenu) {
            HStack(spacing: 6) {
                leading()
                Text(title)
                    .font(theme.font(.body, weight: .medium))
                    .foregroundStyle(tokens.textPrimary.color)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(theme.font(.small))
                        .foregroundStyle(tokens.textSecondary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tokens.border.color, in: Capsule())
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(theme.font(.small))
                    .imageScale(.small)
                    .foregroundStyle(tokens.textSecondary.color)
            }
            .padding(.horizontal, 8)
            .frame(height: ToolbarButton.height)
            .background(
                (isHovered ? tokens.surfaceSunken : tokens.surfaceRaised).color,
                in: RoundedRectangle(cornerRadius: ToolbarButton.radius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .fixedSize()
    }
}
