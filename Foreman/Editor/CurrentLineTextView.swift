import AppKit

/// design R22: the caret's paragraph is painted across the full width in `currentLineColor`.
///
/// `NSTextView` has no such option; drawing it in `drawBackground` keeps it under the text and
/// out of the undo, the attributes and Neon's rendering attributes.
class CurrentLineTextView: NSTextView {
    var currentLineColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
            selectedRange().length == 0,
            let location = contentManager.location(
                contentManager.documentRange.location, offsetBy: selectedRange().location),
            let fragment = layoutManager.textLayoutFragment(for: location)
        else { return }
        let frame = fragment.layoutFragmentFrame
        let line = NSRect(
            x: 0, y: frame.minY + textContainerInset.height, width: bounds.width, height: max(frame.height, 1))
        guard line.intersects(rect) else { return }
        currentLineColor.setFill()
        line.fill()
    }
}
