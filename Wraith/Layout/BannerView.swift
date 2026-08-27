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
        Label {
            Text(text)
                .foregroundStyle(tokens.textPrimary.color)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color(tokens))
        }
        .font(theme.font())
        .lineLimit(3)
        .textSelection(.enabled)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The state token tints the band (mockup 08, first visual review 2026-08-27); `info` stays flat.
        .background(color(tokens).opacity(tone == .info ? 0 : Self.tintOpacity))
        .background(tokens.surfaceRaised.color)
    }

    static let tintOpacity = 0.18

    private func color(_ tokens: ThemeService.Tokens) -> Color {
        switch tone {
        case .error: return tokens.statusRed.color
        case .warning: return tokens.statusOrange.color
        case .info: return tokens.textPrimary.color
        }
    }
}
