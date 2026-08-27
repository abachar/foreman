import AppKit
import SwiftUI

/// editor R14: the rendered markdown; links to workspace files open in Wraith, external ones in
/// the browser on `cmd+clic`; images are the workspace's only.
struct MarkdownPreviewView: View {
    let text: String
    let file: URL
    let root: URL
    let theme: ThemeService
    let highlighter: Highlighter
    /// editor R4: the block at the top, owned by the tab so it survives the view's rebuild.
    @Binding var firstBlock: Int
    let onOpenFile: (URL) -> Void

    @State private var blocks: [MarkdownBlock] = []
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var isRestored = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block, theme: theme, highlighter: highlighter)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position, anchor: .top)
        .foregroundStyle(theme.tokens.textPrimary.color)
        .tint(theme.tokens.accent.color)
        .background(theme.tokens.surface.color)
        .onChange(of: position.viewID(type: Int.self)) { _, id in
            // The first layout of a rebuilt view reports block 0: ignored until restored.
            guard isRestored, let id else { return }
            firstBlock = id
        }
        .textSelection(.enabled)
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.isFileURL {
                    onOpenFile(url)
                    return .handled
                }
                // editor R14: an external link needs `cmd+clic`.
                guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return .discarded }
                return .systemAction
            }
        )
        .task(id: text) {
            blocks = await MarkdownBlocks.make(text, file: file, root: root)
            guard !isRestored else { return }
            if firstBlock > 0, firstBlock < blocks.count {
                position.scrollTo(id: firstBlock, anchor: .top)
            }
            isRestored = true
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let theme: ThemeService
    let highlighter: Highlighter

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? .largeTitle : level == 2 ? .title : level == 3 ? .title2 : .headline)
                .bold()
                .padding(.top, level <= 2 ? 8 : 4)
        case .paragraph(let text):
            Text(text)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, theme: theme, highlighter: highlighter)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(ordered: ordered, number: start + index, checked: item.checked)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, child in
                                MarkdownBlockView(block: child, theme: theme, highlighter: highlighter)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 8)
        case .quote(let blocks):
            HStack(spacing: 10) {
                Rectangle().fill(.tertiary).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child, theme: theme, highlighter: highlighter)
                    }
                }
                .foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in Text(cell).bold() }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(cell) }
                    }
                }
            }
        case .image(let url, let alt):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 800, alignment: .leading)
                    .accessibilityLabel(alt)
            } else {
                Text("[\(alt.isEmpty ? url.lastPathComponent : alt)]").foregroundStyle(.secondary)
            }
        case .html(let raw):
            Text(raw)
                .font(Font(theme.editorFont))
                .foregroundStyle(.secondary)
        }
    }

    private func marker(ordered: Bool, number: Int, checked: Bool?) -> some View {
        Group {
            if let checked {
                Image(systemName: checked ? "checkmark.square" : "square")
            } else if ordered {
                Text("\(number).")
            } else {
                Text("•")
            }
        }
    }
}

/// editor R14: a code block colored through `Highlight/` when its language is known (R11).
private struct CodeBlockView: View {
    let language: String?
    let code: String
    let theme: ThemeService
    let highlighter: Highlighter

    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal) {
            Text(highlighted ?? AttributedString(code))
                .font(Font(theme.editorFont))
                .padding(10)
        }
        // design R8: the sunken shade, opaque (the tint let text show through, M8 8.7).
        .background(theme.tokens.surfaceSunken.color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: code) {
            guard
                let language = Language.forFile(URL(filePath: "x.\(language ?? "")"))
                    ?? Language(rawValue: language ?? "")
            else { return }
            highlighted = await highlighter.highlight(code, language: language)
        }
    }
}
