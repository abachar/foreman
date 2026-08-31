import AppKit
import SwiftUI

/// The popover of editor R41 and R42: one component, two sources.
///
/// A diagnostic's message when the pointer is on one, the server's hover otherwise, and the
/// diagnostic first when both apply — an error you can see is more urgent than a type you asked
/// about. The body is the markdown preview's own renderer (`MarkdownBlockView`), which brings its
/// rule about the network with it: nothing is fetched, ever (`architecture.md`, security).
///
/// A borderless `NSPanel` rather than an `NSPopover` (author, 2026-08-31): the palette is already
/// a floating island — opaque `surfaceOverlay`, `islandRadius`, one shadow, no arrow (`design`
/// R18) — and a second floating surface with the system's own material and a beak would be a
/// second look for the same idea. `Palette` is the pattern this copies.
@MainActor
final class HoverPopover {
    /// Wide enough for a signature, short enough not to cover what is under it.
    static let maximumWidth: CGFloat = 420
    static let maximumHeight: CGFloat = 260
    /// The gap between the character and the panel, so the caret stays visible.
    nonisolated static let gap: CGFloat = 6

    private var panel: NSPanel?
    /// Retained with the panel: the container owns the tracking, the controller owns the view.
    private var hosting: NSHostingController<HoverPopoverView>?
    /// editor R42: the pointer left the popover itself, so there is nothing left to read.
    var onPointerLeft: (() -> Void)?

    /// Whether the pointer is over the popover — a move *into* it must not close it (author,
    /// 2026-08-31: moving onto it made it vanish, so a long doc could not be scrolled).
    var containsMouse: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    /// Shows `blocks` and `diagnostic` against `rect` in `view`; showing nothing hides it.
    func show(
        blocks: [MarkdownBlock], diagnostic: EditorDiagnostic?, relativeTo rect: NSRect, of view: NSView,
        theme: ThemeService, highlighter: Highlighter
    ) {
        guard !blocks.isEmpty || diagnostic != nil, let window = view.window else {
            hide()
            return
        }
        let body = HoverPopoverContent(
            blocks: blocks, diagnostic: diagnostic, theme: theme, highlighter: highlighter)
        // Measured on the content **without its scroll view**, at the width it will have: a
        // `ScrollView` accepts whatever size it is offered, so measuring through one always
        // answered the maximum, and every popover came out as large as the largest (author,
        // 2026-08-31). `fittingSize` on an unconstrained view is no better — it reports the
        // height of text that has not wrapped yet.
        let ideal = NSHostingController(rootView: body).sizeThatFits(
            in: NSSize(width: Self.maximumWidth, height: .greatestFiniteMagnitude))
        let size = NSSize(
            width: min(max(ideal.width.rounded(.up), 120), Self.maximumWidth),
            height: min(ideal.height.rounded(.up), Self.maximumHeight))
        let hosting = NSHostingController(
            rootView: HoverPopoverView(content: body, theme: theme))
        self.hosting = hosting
        let panel = self.panel ?? makePanel(in: window)
        self.panel = panel
        // design R18: the island's rounding lives on the hosted layer, the panel itself is clear.
        let container = HoverPanelView(frame: NSRect(origin: .zero, size: size))
        container.onExit = { [weak self] in self?.onPointerLeft?() }
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
        container.wantsLayer = true
        container.layer?.cornerRadius = theme.tokens.islandRadius
        container.layer?.masksToBounds = true
        panel.contentView = container
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(Self.origin(for: rect, of: view, size: size))
        // Never key: the pointer is resting, the user is not asking to type in it.
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        panel.contentView = nil
        hosting = nil
        self.panel = nil
    }

    private func makePanel(in window: NSWindow) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.maximumWidth, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        window.addChildWindow(panel, ordered: .above)
        return panel
    }

    /// The top-left corner, in screen coordinates: under the character, flipped above it when the
    /// screen has no room below, and pulled back inside when it would run off the right edge.
    nonisolated static func origin(for rect: NSRect, of view: NSView, size: NSSize) -> NSPoint {
        let inWindow = view.convert(rect, to: nil)
        guard let window = view.window else { return NSPoint(x: inWindow.minX, y: inWindow.minY) }
        let onScreen = window.convertToScreen(inWindow)
        var x = onScreen.minX
        var y = onScreen.minY - gap
        if let visible = window.screen?.visibleFrame {
            x = min(x, visible.maxX - size.width)
            x = max(x, visible.minX)
            // Below by default; above when the panel would fall off the bottom of the screen.
            if y - size.height < visible.minY {
                y = onScreen.maxY + gap + size.height
            }
        }
        return NSPoint(x: x, y: y)
    }
}

/// The panel's content view, which knows when the pointer leaves it (editor R42).
///
/// The text view reports the pointer leaving *it*, which happens on the way **in** here; without
/// this the popover closed exactly when the user reached for it.
private final class HoverPanelView: NSView {
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onExit?()
    }
}

/// The popover, scrolling only when what it holds does not fit (editor R42).
struct HoverPopoverView: View {
    let content: HoverPopoverContent
    let theme: ThemeService

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        // design R18: the same island as the palette — opaque overlay, nothing translucent.
        .background(theme.tokens.surfaceOverlay.color)
    }
}

/// What the popover shows (editor R41, R42).
struct HoverPopoverContent: View {
    let blocks: [MarkdownBlock]
    let diagnostic: EditorDiagnostic?
    let theme: ThemeService
    let highlighter: Highlighter

    /// editor R42: a tooltip, not a document.
    ///
    /// The prose goes smaller than the code: a signature has to stay readable as code, the
    /// sentence under it does not (author, 2026-08-31).
    static let codeScale: CGFloat = 0.85
    static let proseScale: CGFloat = 0.72

    private var metrics: MarkdownMetrics {
        MarkdownMetrics(readingFontSize: (theme.tokens.readingFontSize * Self.proseScale).rounded())
    }

    var body: some View {
        let tokens = theme.tokens
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
                    images: MarkdownImageCache(), scale: Self.codeScale)
            }
        }
        // No `maxWidth`: a greedy frame made every popover as wide as the widest one could be.
        .padding(10)
        .font(Font(theme.readingFont(scale: Self.proseScale)))
        .foregroundStyle(tokens.textPrimary.color)
        .textSelection(.enabled)
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
