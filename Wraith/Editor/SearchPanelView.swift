import SwiftUI

/// The bottom panel `editor.search` (editor R20, R21).
struct SearchPanelView: View {
    @Bindable var model: SearchModel
    /// A match was chosen: open the file at the line, pinned on `cmd`.
    let onOpen: (ContentSearch.Match, _ pinned: Bool) -> Void

    @FocusState private var isFieldFocused: Bool

    init(model: SearchModel, onOpen: @escaping (ContentSearch.Match, _ pinned: Bool) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search in files", text: $model.options.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit { model.search() }
                Toggle("Aa", isOn: $model.options.isCaseSensitive).help("Match case")
                Toggle("W", isOn: $model.options.isWholeWord).help("Whole word")
                Toggle(".*", isOn: $model.options.isRegex).help("Regular expression")
                TextField("Include (glob)", text: $model.options.include)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { model.search() }
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { model.cancel() }
                }
            }
            .toggleStyle(.button)
            .padding(8)
            Divider()
            content
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: model.options.isCaseSensitive) { _, _ in model.search() }
        .onChange(of: model.options.isWholeWord) { _, _ in model.search() }
        .onChange(of: model.options.isRegex) { _, _ in model.search() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else if model.groups.isEmpty {
            ContentUnavailableView(
                model.options.query.isEmpty
                    ? "Type a query and press Return" : model.isRunning ? "Searching…" : "No results",
                systemImage: "magnifyingglass",
                description: toolNote)
        } else {
            List {
                ForEach(model.groups) { group in
                    Section(group.path) {
                        ForEach(group.matches) { match in
                            row(match)
                        }
                    }
                }
                if model.isTruncated {
                    Text("Results truncated at \(ContentSearch.limit) matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }

    private var toolNote: Text? {
        if case .grep = model.tool {
            // editor, edge cases: grep is the fallback; ripgrep is faster and honors .gitignore.
            return Text("Using grep — install ripgrep (brew install ripgrep) for faster, .gitignore-aware search")
        }
        return nil
    }

    private func row(_ match: ContentSearch.Match) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(match.line)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(highlighted(match))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen(match, NSApp.currentEvent?.modifierFlags.contains(.command) == true)
        }
    }

    /// editor R21: the match is emphasized in its line.
    private func highlighted(_ match: ContentSearch.Match) -> AttributedString {
        let trimmed = String(match.text.drop { $0 == " " || $0 == "\t" })
        let removed = (match.text as NSString).length - (trimmed as NSString).length
        var text = AttributedString(trimmed)
        for range in match.ranges {
            let shifted = NSRange(location: range.location - removed, length: range.length)
            guard shifted.location >= 0, let bounds = Range(shifted, in: text) else { continue }
            text[bounds].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}
