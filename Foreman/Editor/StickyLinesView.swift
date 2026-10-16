import AppKit

/// editor R56 (2026-10-16, M21 21.11, view 02): the first lines of the blocks the top of the
/// editor is in — class, method… — pinned over the text, on the editor's ground, a separator
/// under them; a click scrolls to the line.
///
/// An `NSView` over the scroll view, drawing the text view's own layout fragments, so the pinned
/// lines keep the highlighting and the font; nothing native does it.
final class StickyLinesView: NSView {
    weak var textView: NSTextView?
    var regions: [FoldRegion] = [] {
        didSet {
            guard regions != oldValue else { return }
            refresh()
        }
    }
    var background: NSColor = .clear
    var separator: NSColor = .clear
    var numberColor: NSColor = .secondaryLabelColor
    var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    /// The UTF-16 offset where each line starts, from the text view's text.
    var lineStarts: () -> [Int] = { [0] }

    private var pinned: [(line: Int, fragment: NSTextLayoutFragment)] = []

    override var isFlipped: Bool {
        true
    }

    /// Recomputed on every scroll, edit and parse.
    func refresh() {
        guard let textView, let scroll = textView.enclosingScrollView, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let visible = scroll.contentView.bounds
        let starts = lineStarts()
        guard
            let top = layoutManager.textLayoutFragment(
                for: CGPoint(x: 0, y: visible.minY - textView.textContainerInset.height + 1))
        else {
            setPinned([])
            return
        }
        let topLine = IndentGuides.line(
            at: contentManager.offset(from: layoutManager.documentRange.location, to: top.rangeInElement.location),
            starts: starts)
        let lines = StickyLines.lines(topLine: topLine, regions: regions)
        setPinned(
            lines.compactMap { line in
                guard line - 1 < starts.count,
                    let location = contentManager.location(
                        layoutManager.documentRange.location, offsetBy: starts[line - 1]),
                    let fragment = layoutManager.textLayoutFragment(for: location)
                else { return nil }
                return (line, fragment)
            })
    }

    private func setPinned(_ pinned: [(line: Int, fragment: NSTextLayoutFragment)]) {
        self.pinned = pinned
        let height = pinned.reduce(0) { $0 + $1.fragment.layoutFragmentFrame.height }
        isHidden = pinned.isEmpty
        if let superview {
            let total = pinned.isEmpty ? 0 : height + 1
            // Pinned to the top of the scroll view, which is not flipped.
            frame = NSRect(
                x: 0, y: superview.isFlipped ? 0 : superview.bounds.height - total, width: superview.bounds.width,
                height: total)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let context = NSGraphicsContext.current?.cgContext else { return }
        background.setFill()
        bounds.fill()
        let ruler = textView.enclosingScrollView?.verticalRulerView?.ruleThickness ?? 0
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
        var y: CGFloat = 0
        for (line, fragment) in pinned {
            let height = fragment.layoutFragmentFrame.height
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruler - 14 - size.width - 4, y: y + (height - size.height) / 2),
                withAttributes: attributes)
            fragment.draw(
                at: CGPoint(x: ruler + textView.textContainerInset.width + fragment.layoutFragmentFrame.minX, y: y),
                in: context)
            y += height
        }
        separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// editor R56: a click on a pinned line puts that line at the top of the editor.
    override func mouseDown(with event: NSEvent) {
        guard let textView, let scroll = textView.enclosingScrollView else { return }
        let point = convert(event.locationInWindow, from: nil)
        var y: CGFloat = 0
        for (_, fragment) in pinned {
            let height = fragment.layoutFragmentFrame.height
            if point.y < y + height {
                let target = fragment.layoutFragmentFrame.minY + textView.textContainerInset.height
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: max(target, 0)))
                scroll.reflectScrolledClipView(scroll.contentView)
                refresh()
                return
            }
            y += height
        }
    }
}
