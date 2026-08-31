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

    /// editor R41: one range to underline, with the colour of its severity.
    struct Underline: Equatable {
        let range: NSRange
        let color: NSColor
    }

    /// editor R41: the ranges to underline, drawn here rather than set as attributes.
    ///
    /// The same reason the current line is: Neon owns the text's attributes and reapplies them on
    /// every parse, so an underline put there would be wiped by the next keystroke.
    var underlines: [Underline] = [] {
        didSet {
            guard underlines != oldValue else { return }
            needsDisplay = true
        }
    }

    /// editor R42: the pointer came to rest logic lives in the feature; the view only reports
    /// where it is, and when it leaves.
    var onPointerMoved: ((Int) -> Void)?
    var onPointerLeft: (() -> Void)?
    private var pointerTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let onPointerMoved else { return }
        onPointerMoved(characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerLeft?()
    }

    /// editor R42: the rect of one character, where the popover is anchored.
    func rect(forCharacterAt location: Int) -> NSRect? {
        guard let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
            let start = contentManager.location(layoutManager.documentRange.location, offsetBy: location),
            let end = contentManager.location(start, offsetBy: 1),
            let range = NSTextRange(location: start, end: end)
        else { return nil }
        var found: NSRect?
        layoutManager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
            found = frame.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
            return false
        }
        return found
    }

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
        if let line = currentLineRect, line.intersects(rect) {
            currentLineColor.setFill()
            line.fill()
        }
        drawUnderlines(in: rect)
    }

    /// editor R41: a wave under each diagnostic's range, clipped to what is being redrawn.
    private func drawUnderlines(in rect: NSRect) {
        guard !underlines.isEmpty, let layoutManager = textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        for underline in underlines {
            let origin = layoutManager.documentRange.location
            guard let start = contentManager.location(origin, offsetBy: underline.range.location),
                let end = contentManager.location(start, offsetBy: underline.range.length),
                let range = NSTextRange(location: start, end: end)
            else { continue }
            underline.color.setStroke()
            layoutManager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                var frame = frame
                frame.origin.x += textContainerInset.width
                frame.origin.y += textContainerInset.height
                guard frame.width > 0, frame.intersects(rect) else { return true }
                Self.wave(under: frame).stroke()
                return true
            }
        }
    }

    /// The wave itself: a 1 pt line zigzagging over a 4 pt period, one point above the baseline's
    /// descent so it reads as an underline rather than as a border.
    private static func wave(under frame: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1
        let period: CGFloat = 4
        let amplitude: CGFloat = 1.5
        let base = frame.maxY - amplitude
        path.move(to: NSPoint(x: frame.minX, y: base))
        var x = frame.minX
        var up = true
        while x < frame.maxX {
            x = min(x + period / 2, frame.maxX)
            path.line(to: NSPoint(x: x, y: base + (up ? amplitude : -amplitude)))
            up.toggle()
        }
        return path
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
