import SwiftUI

/// The palette's content: a field, the rows, a notice (editor R17).
struct PaletteView: View {
    let palette: Palette

    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(palette.source?.placeholder ?? "", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($isFieldFocused)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(palette.results.items.enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == palette.selectedIndex)
                            .id(item.id)
                            .listRowSeparator(.hidden)
                            .onTapGesture { palette.select(index, newGroup: false) }
                    }
                }
                .listStyle(.plain)
                .onChange(of: palette.selectedIndex) { _, index in
                    if palette.results.items.indices.contains(index) {
                        proxy.scrollTo(palette.results.items[index].id)
                    }
                }
            }
            if let notice = palette.results.notice {
                Divider()
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .frame(width: 620, height: 420)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, query in
            palette.update(query: query)
        }
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}
