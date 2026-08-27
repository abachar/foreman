import SwiftUI

/// design R17: a one-line message on the island's raised surface, tinted by its tone.
struct BannerView: View {
    enum Tone {
        case error
        case warning
        case info
    }

    let text: String
    let icon: String
    var tone: Tone = .info
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(color(tokens))
            .lineLimit(3)
            .textSelection(.enabled)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surfaceRaised.color)
    }

    private func color(_ tokens: ThemeService.Tokens) -> Color {
        switch tone {
        case .error: return tokens.statusRed.color
        case .warning: return tokens.statusOrange.color
        case .info: return tokens.textPrimary.color
        }
    }
}
