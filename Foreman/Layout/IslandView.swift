import SwiftUI

/// design R2: a zone laid on the window ground — the island's `surface`, rounded by `islandRadius`.
struct IslandView<Content: View>: View {
    let theme: ThemeService
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tokens = theme.tokens
        content()
            // The island is the whole zone, whatever its content asks for (bug: the search panel
            // left a band of ground under itself, 2026-08-27).
            // design R2, R17: the content starts at the top of the island; an empty state fills the rest.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // design R6: the interface font, inherited by everything on the island.
            .font(theme.font())
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: tokens.islandRadius))
    }
}
