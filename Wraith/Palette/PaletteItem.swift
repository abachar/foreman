import Foundation

/// One line of the palette (editor R17, run R5): what is shown, and what the source gets back.
nonisolated struct PaletteItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: AttributedString
    let subtitle: String?

    init(id: String, title: AttributedString, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    /// `text` with the characters of `query` (as a case-insensitive subsequence) in bold: display
    /// only, the ranking is the fuzzy library's.
    static func highlighted(_ text: String, matching query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var needle = query.lowercased().makeIterator()
        var wanted = needle.next()
        var index = text.startIndex
        while let character = wanted, index < text.endIndex {
            if String(text[index]).lowercased() == String(character) {
                let attributedIndex = AttributedString.Index(index, within: result)
                let next = text.index(after: index)
                if let attributedIndex, let end = AttributedString.Index(next, within: result) {
                    result[attributedIndex..<end].inlinePresentationIntent = .stronglyEmphasized
                }
                wanted = needle.next()
            }
            index = text.index(after: index)
        }
        return result
    }
}

/// What a feature gives the palette: how to fill it and what to do with the choice.
struct PaletteSource {
    struct Results: Sendable {
        var items: [PaletteItem]
        /// editor R17, R18: shown under the list (truncated results, truncated index).
        var notice: String?
    }

    let placeholder: String
    let results: (String) async -> Results
    /// `newGroup` is `cmd+enter` (editor R17, run R6).
    let select: (PaletteItem, _ newGroup: Bool) -> Void
}
