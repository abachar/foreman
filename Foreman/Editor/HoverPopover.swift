import AppKit
import SwiftUI

/// The popover of editor R41 and R42: one component, two sources.
///
/// A diagnostic's message when the pointer is on one, the server's hover otherwise, and the
/// diagnostic first when both apply — an error you can see is more urgent than a type you asked
/// about. The body is the markdown preview's own renderer (`MarkdownBlockView`), which brings its
/// rule about the network with it: nothing is fetched, ever (`architecture.md`, security).
@MainActor
final class HoverPopover {
    /// Wide enough for a signature, short enough not to cover what is under it.
    static let maximumWidth: CGFloat = 460
    static let maximumHeight: CGFloat = 320

    private let popover = NSPopover()

    init() {
        popover.behavior = .transient
        popover.animates = false
    }

    var isShown: Bool {
        popover.isShown
    }

    /// Shows `blocks` and `diagnostic` against `rect` in `view`; showing nothing hides it.
    func show(
        blocks: [MarkdownBlock], diagnostic: EditorDiagnostic?, relativeTo rect: NSRect, of view: NSView,
        theme: ThemeService, highlighter: Highlighter
    ) {
        guard !blocks.isEmpty || diagnostic != nil else {
            hide()
            return
        }
        let content = HoverPopoverView(
            blocks: blocks, diagnostic: diagnostic, theme: theme, highlighter: highlighter)
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = NSSize(
            width: min(controller.view.fittingSize.width, Self.maximumWidth),
            height: min(controller.view.fittingSize.height, Self.maximumHeight))
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    func hide() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}

/// What the popover shows (editor R41, R42).
private struct HoverPopoverView: View {
    let blocks: [MarkdownBlock]
    let diagnostic: EditorDiagnostic?
    let theme: ThemeService
    let highlighter: Highlighter

    private var metrics: MarkdownMetrics {
        MarkdownMetrics(readingFontSize: theme.tokens.readingFontSize)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.blockSpacing) {
                if let diagnostic {
                    // editor R41: the diagnostic comes first, in its severity's colour.
                    Label {
                        Text(diagnostic.message)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: Self.symbol(for: diagnostic.severity))
                    }
                    .foregroundStyle(color(for: diagnostic.severity))
                    if !blocks.isEmpty {
                        Divider()
                    }
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block, theme: theme, highlighter: highlighter, metrics: metrics,
                        images: MarkdownImageCache())
                }
            }
            .frame(maxWidth: HoverPopover.maximumWidth, alignment: .leading)
            .padding(12)
        }
        .font(Font(theme.readingFont()))
        .foregroundStyle(theme.tokens.textPrimary.color)
        .textSelection(.enabled)
        .scrollBounceBehavior(.basedOnSize)
    }

    private static func symbol(for severity: EditorDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .information: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private func color(for severity: EditorDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return theme.tokens.statusRed.color
        case .warning: return theme.tokens.statusOrange.color
        case .information: return theme.tokens.statusBlue.color
        case .hint: return theme.tokens.textSecondary.color
        }
    }
}
