import AppKit
import SwiftUI

/// editor R14: the rendered markdown; links to workspace files open in Foreman, external ones in
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
    @State private var images = MarkdownImageCache()

    /// design R6: every space in the preview is a multiple of the reading size.
    private var metrics: MarkdownMetrics {
        MarkdownMetrics(readingFontSize: theme.tokens.readingFontSize)
    }

    @State private var position = ScrollPosition(idType: Int.self)
    @State private var isRestored = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.blockSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block, theme: theme, highlighter: highlighter, metrics: metrics, images: images)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // design R6: the reading size and a looser leading than the chrome (2026-08-29).
        .font(Font(theme.readingFont()))
        .lineSpacing(4)
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

/// One markdown block, rendered (editor R14).
///
/// Internal rather than private since 2026-08-31: the hover popover shows a server's markdown
/// with the same renderer (R42).
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let theme: ThemeService
    let highlighter: Highlighter
    let metrics: MarkdownMetrics
    let images: MarkdownImageCache
    /// design R6: how many lists deep this block sits, for the marker (0 at the top level).
    var depth = 0

    private static let headingScales: [CGFloat] = [2, 1.5, 1.25, 1, 0.875, 0.85]

    /// design R6 (amended 2026-08-30): headings scale the reading size, `semibold` as GitHub's.
    private func headingFont(_ level: Int) -> Font {
        Font(theme.readingFont(scale: Self.headingScales[min(max(level, 1), 6) - 1], weight: .semibold))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        (theme.tokens.readingFontSize * Self.headingScales[min(max(level, 1), 6) - 1]).rounded()
    }

    /// Inline code runs (`inlinePresentationIntent == .code`) take the preview's code font and,
    /// since design R6 was amended (2026-08-30), its ground — GitHub's chip in our own tokens.
    ///
    /// The ground is flat: an `AttributedString` run carries a background colour but neither
    /// padding nor a corner radius, which would need a view of their own and would break the
    /// wrapping of the paragraph the run sits in.
    ///
    /// Links are underlined at rest (design R6, author's call 2026-08-30): GitHub underlines on
    /// hover, and SwiftUI's `Text` has no per-run hover to hang that on.
    private func styled(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                text[run.range].font = Font(theme.readingCodeFont)
                text[run.range].backgroundColor = theme.tokens.surfaceSunken.color
            }
            if run.link != nil {
                text[run.range].underlineStyle = .single
            }
        }
        return text
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            // design R6: 24 above every heading (the stack gives 16, the heading adds the rest),
            // and the rule GitHub draws under h1 and h2 — in our `separator`, not GitHub's grey.
            VStack(alignment: .leading, spacing: metrics.headingRuleGap(size: headingSize(level))) {
                Text(styled(text))
                    .font(headingFont(level))
                if level <= 2 {
                    theme.tokens.separator.color.frame(height: 1)
                }
            }
            .padding(.top, metrics.headingTop)
        case .paragraph(let text):
            Text(styled(text))
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, theme: theme, highlighter: highlighter, metrics: metrics)
        case .list(let ordered, let start, let items):
            // design R6: a fixed marker column, so the content lands at `listIndent` (GitHub's
            // `padding-left: 2em`) and the markers of a level line up whatever their width.
            VStack(alignment: .leading, spacing: metrics.itemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: metrics.markerGap) {
                        marker(ordered: ordered, number: start + index, checked: item.checked)
                            .foregroundStyle(.secondary)
                            .frame(width: metrics.markerColumn, alignment: .trailing)
                        VStack(alignment: .leading, spacing: metrics.itemBlockSpacing) {
                            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, child in
                                MarkdownBlockView(
                                    block: child, theme: theme, highlighter: highlighter, metrics: metrics,
                                    images: images, depth: depth + 1)
                            }
                        }
                    }
                }
            }
        case .quote(let blocks):
            HStack(spacing: metrics.quoteGap) {
                Rectangle().fill(.tertiary).frame(width: metrics.quoteBar)
                VStack(alignment: .leading, spacing: metrics.blockSpacing) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(
                            block: child, theme: theme, highlighter: highlighter, metrics: metrics, images: images,
                            depth: depth)
                    }
                }
                .foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        case .table(let header, let rows):
            // design R6 (2026-08-30): GitHub's grid — a border on every cell and every second row
            // tinted — in our own tokens. `Grid` has no cell decoration, so each cell carries its
            // own ground and its own trailing/bottom hairline, and the block draws the outer edge.
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        cellView(styled(cell), isHeader: true, isTinted: false)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            // GitHub tints `tr:nth-child(2n)`; the header is the first row.
                            cellView(styled(cell), isHeader: false, isTinted: index.isMultiple(of: 2))
                        }
                    }
                }
            }
            .overlay {
                Rectangle().strokeBorder(theme.tokens.border.color, lineWidth: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .image(let url, let alt):
            // The file is read off the main actor (coding rules: no IO in a `body`); a quiet
            // frame keeps the block's place until the bytes arrive.
            if let image = images.image(at: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 800, alignment: .leading)
                    .accessibilityLabel(alt)
            } else if images.hasFailed(url) {
                Text("[\(alt.isEmpty ? url.lastPathComponent : alt)]")
                    .font(Font(theme.readingFont(scale: 0.875)))
                    .foregroundStyle(.secondary)
            } else {
                theme.tokens.surfaceSunken.color
                    .frame(maxWidth: 800, alignment: .leading)
                    .frame(height: 120)
                    .onAppear { images.load(url) }
            }
        case .html(let raw):
            Text(raw)
                .font(Font(theme.readingCodeFont))
                .foregroundStyle(.secondary)
        }
    }

    /// design R6 (2026-08-30): one cell of a table — GitHub's `padding: 6px 13px`, its border and
    /// the tint of every second row.
    private func cellView(_ text: AttributedString, isHeader: Bool, isTinted: Bool) -> some View {
        Text(text)
            .bold(isHeader)
            .padding(.vertical, metrics.cellPadding.vertical)
            .padding(.horizontal, metrics.cellPadding.horizontal)
            // Both axes: a cell must fill its row's height or its borders float free of the grid.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isTinted ? theme.tokens.surfaceRaised.color : .clear)
            .overlay(alignment: .trailing) { theme.tokens.border.color.frame(width: 1) }
            .overlay(alignment: .bottom) { theme.tokens.border.color.frame(height: 1) }
    }

    /// design R6 (2026-08-30): the marker follows the depth, as CSS's `list-style` does.
    private func marker(ordered: Bool, number: Int, checked: Bool?) -> some View {
        Group {
            if let checked {
                Image(systemName: checked ? "checkmark.square" : "square")
            } else if ordered {
                Text("\(MarkdownBlocks.number(number, depth: depth)).")
            } else {
                Text(MarkdownBlocks.bullet(depth: depth))
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
    let metrics: MarkdownMetrics

    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal) {
            Text(highlighted ?? AttributedString(code))
                .font(Font(theme.readingCodeFont))
                .padding(metrics.codePadding)
        }
        // design R8: the sunken shade, opaque (the tint let text show through, M8 8.7).
        .background(theme.tokens.surfaceSunken.color)
        .clipShape(RoundedRectangle(cornerRadius: metrics.codeRadius))
        .task(id: code) {
            guard
                let language = Language.forFile(URL(filePath: "x.\(language ?? "")"))
                    ?? Language(rawValue: language ?? "")
            else { return }
            highlighted = await highlighter.highlight(code, language: language)
        }
    }
}

/// editor R14 — the preview's images, one read per URL for the life of the view.
///
/// The blocks only ever carry workspace files (`MarkdownLinks.image`), never a remote resource.
@MainActor
@Observable
/// Internal rather than private since 2026-08-31, with `MarkdownBlockView`: the hover popover
/// needs one to render blocks, and it renders no image (a server sends none).
final class MarkdownImageCache {
    private var images: [URL: NSImage] = [:]
    /// URLs whose file read or decode produced nothing: the alt text shows instead.
    private var failed: Set<URL> = []
    @ObservationIgnored private var loading: Set<URL> = []

    func image(at url: URL) -> NSImage? {
        images[url]
    }

    func hasFailed(_ url: URL) -> Bool {
        failed.contains(url)
    }

    /// Reads `url` off the main actor once; the observed dictionaries re-render the blocks.
    func load(_ url: URL) {
        guard images[url] == nil, !failed.contains(url), !loading.contains(url) else { return }
        loading.insert(url)
        Task {
            let data = await Self.read(url)
            loading.remove(url)
            if let image = data.flatMap(NSImage.init(data:)) {
                images[url] = image
            } else {
                failed.insert(url)
            }
        }
    }

    @concurrent
    private static func read(_ url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }
}
