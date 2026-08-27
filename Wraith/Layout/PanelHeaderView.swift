import SwiftUI

/// design R17: the header of a panel island — its title and its controls on `surfaceRaised`,
/// `barHeight` tall, a separator under it.
struct PanelHeaderView<Trailing: View>: View {
    let title: String
    let theme: ThemeService
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(theme.font(.title, weight: .medium))
                    .foregroundStyle(tokens.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 10)
            .frame(height: tokens.barHeight)
            .background(tokens.surfaceRaised.color)
            tokens.separator.color.frame(height: 1)
        }
    }
}
