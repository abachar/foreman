import SwiftUI

/// design R2: a zone laid on the window ground — the island's `surface`, rounded by `islandRadius`.
struct IslandView<Content: View>: View {
    let theme: ThemeService
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tokens = theme.tokens
        content()
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: tokens.islandRadius))
    }
}
