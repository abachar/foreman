import SwiftUI

/// The palette's content: a field, the rows, a notice, the help line (editor R17; design R18).
struct PaletteView: View {
    let palette: Palette
    let theme: ThemeService

    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            TextField(palette.source?.placeholder ?? "", text: $query)
                .textFieldStyle(.plain)
                .font(theme.font(.title))
                .foregroundStyle(tokens.textPrimary.color)
                .padding(10)
                .background(tokens.surfaceSunken.color, in: RoundedRectangle(cornerRadius: 6))
                .padding(10)
                .focused($isFieldFocused)
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(palette.results.items.enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == palette.selectedIndex, tokens: tokens)
                            .id(item.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onTapGesture { palette.select(index, newGroup: false) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: palette.selectedIndex) { _, index in
                    if palette.results.items.indices.contains(index) {
                        proxy.scrollTo(palette.results.items[index].id)
                    }
                }
            }
            if let notice = palette.results.notice {
                Text(notice)
                    .font(theme.font(.small))
                    .foregroundStyle(tokens.textSecondary.color)
                    .padding(6)
            }
            tokens.separator.color.frame(height: 1)
            Text(Self.help(hasSecondary: palette.source?.secondary != nil))
                .font(theme.font(.small))
                .foregroundStyle(tokens.textDisabled.color)
                .padding(8)
        }
        .frame(width: 620, height: 420)
        .font(theme.font())
        .background(tokens.surfaceOverlay.color)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, query in
            palette.update(query: query)
        }
    }

    /// design R18: the keys, `opt+enter` only when the source has a secondary action (run R6).
    nonisolated static func help(hasSecondary: Bool) -> String {
        "↑↓ navigate · ⏎ open · ⌘⏎ new group" + (hasSecondary ? " · ⌥⏎ alternate" : "") + " · esc close"
    }

    private func row(_ item: PaletteItem, isSelected: Bool, tokens: ThemeService.Tokens) -> some View {
        HStack(spacing: 8) {
            if let icon = item.icon, let image = FileIcon.image(named: icon) {
                Image(nsImage: image)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? tokens.accentText.color : tokens.textPrimary.color)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(theme.font(.small))
                        .foregroundStyle(isSelected ? tokens.accentText.color.opacity(0.8) : tokens.textSecondary.color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? tokens.accent.color : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}
