import AppKit

/// design R22: the caret's paragraph is painted across the full width in `currentLineColor`.
///
/// `NSTextView` has no such option; drawing it in `drawBackground` keeps it under the text and
/// out of the undo, the attributes and Neon's rendering attributes.
class CurrentLineTextView: NSTextView {
    var currentLineColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    /// editor R43: `cmd+click` reports the character under the pointer and stops there.
    ///
    /// The caret is deliberately left alone: a jump that also moved the selection would lose the
    /// place the user is coming back to.
    var onCommandClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let onCommandClick else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        onCommandClick(characterIndexForInsertion(at: point))
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        // Only the two touched line rects redraw: a caret move must not repaint the whole view.
        let old = currentLineRect
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        let new = currentLineRect
        guard old != new else { return }
        if let old {
            setNeedsDisplay(old)
        }
        if let new {
            setNeedsDisplay(new)
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let line = currentLineRect, line.intersects(rect) else { return }
        currentLineColor.setFill()
        line.fill()
    }

    /// The full-width rect of the caret's paragraph; `nil` with a selection (nothing painted).
    private var currentLineRect: NSRect? {
        guard let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
            selectedRange().length == 0,
            let location = contentManager.location(
                contentManager.documentRange.location, offsetBy: selectedRange().location),
            let fragment = layoutManager.textLayoutFragment(for: location)
        else { return nil }
        let frame = fragment.layoutFragmentFrame
        return NSRect(
            x: 0, y: frame.minY + textContainerInset.height, width: bounds.width, height: max(frame.height, 1))
    }
}
