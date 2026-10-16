import AppKit

/// design R22: the caret's paragraph is painted across the full width in `currentLineColor`.
///
/// `NSTextView` has no such option; drawing it in `drawBackground` keeps it under the text and
/// out of the undo, the attributes and Neon's rendering attributes.
class CurrentLineTextView: NSTextView {
    var currentLineColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    /// editor R53 (2026-10-16): the column of the print margin, `nil` for none.
    var printMarginColumn: Int? {
        didSet {
            guard printMarginColumn != oldValue else { return }
            needsDisplay = true
        }
    }
    var printMarginColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    // MARK: Reading aids (editor R54, R55)

    var guideColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var activeGuideColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var bracketColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    private var regions: [FoldRegion] = []
    private var brackets: [BracketPair] = []
    private var indentWidth = 4
    /// The levels of every line and where each line starts, kept with the text: the draw and the
    /// caret only read them.
    private var guideLevels: [Int] = []
    private(set) var lineStarts: [Int] = [0]
    /// What the caret lights up, kept to redraw only when it changes.
    private var activeGuide: (column: Int, lines: ClosedRange<Int>)?
    private var matchedBrackets: BracketPair?
    /// editor R27 (amended 2026-10-16): the caret's innermost block, whose fold markers the
    /// gutter draws brighter.
    private(set) var activeRegion: FoldRegion?

    /// The parse's regions and pairs, and the width of a level; called on every SwiftUI update.
    func setStructure(regions: [FoldRegion], brackets: [BracketPair], indentWidth: Int) {
        guard regions != self.regions || brackets != self.brackets || indentWidth != self.indentWidth else { return }
        self.regions = regions
        self.brackets = brackets
        self.indentWidth = indentWidth
        // A new parse follows every edit and every reload (which posts no change): the levels are
        // read again with it.
        rebuildLines()
        updateCaretAids(force: true)
    }

    override func didChangeText() {
        super.didChangeText()
        rebuildLines()
        needsDisplay = true
    }

    private func rebuildLines() {
        guideLevels = IndentGuides.levels(of: string, width: indentWidth)
        lineStarts = IndentGuides.lineStarts(of: string as NSString)
    }

    /// The 1-based line of a UTF-16 offset, from the cached starts.
    private func line(at offset: Int) -> Int {
        IndentGuides.line(at: offset, starts: lineStarts)
    }

    /// editor R54, R55: the active block and the matched pair follow the caret.
    private func updateCaretAids(force: Bool = false) {
        let caret = selectedRange().length == 0 ? selectedRange().location : nil
        let line = caret.map { self.line(at: $0) }
        let guide = line.flatMap {
            IndentGuides.activeGuide(regions: regions, caretLine: $0, levels: guideLevels, width: indentWidth)
        }
        let pair = caret.flatMap { BracketPair.match(brackets, caret: $0) }
        let region = line.flatMap { Folding.innermost(regions, containing: $0) }
        if region != activeRegion {
            activeRegion = region
            enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        guard
            force || guide?.column != activeGuide?.column || guide?.lines != activeGuide?.lines
                || pair != matchedBrackets
        else { return }
        activeGuide = guide
        matchedBrackets = pair
        needsDisplay = true
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
        // editor R42: a click ends the pointer's rest, whether or not it moved a pixel first.
        onPointerLeft?()
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
        updateCaretAids()
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
        drawPrintMargin(in: rect)
        drawGuides(in: rect)
        drawMatchedBrackets(in: rect)
        drawUnderlines(in: rect)
    }

    /// editor R54: a 1 pt line at each enclosing level's column of every visible line, the
    /// caret's block brighter; a folded line has no height and gets none.
    private func drawGuides(in rect: NSRect) {
        guard let font, let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
            !guideLevels.isEmpty
        else { return }
        let advance = Self.advance(of: font)
        let origin = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let start =
            layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: rect.minY - textContainerInset.height))?
            .rangeInElement.location ?? layoutManager.documentRange.location
        var line = self.line(at: contentManager.offset(from: layoutManager.documentRange.location, to: start))
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            defer { line += 1 }
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: textContainerInset.height)
            guard frame.height >= 1, line - 1 < guideLevels.count else { return frame.minY < rect.maxY }
            for column in IndentGuides.columns(level: guideLevels[line - 1], width: indentWidth) {
                let isActive = activeGuide.map { $0.column == column && $0.lines.contains(line) } ?? false
                (isActive ? activeGuideColor : guideColor).setFill()
                NSRect(
                    x: (origin + CGFloat(column) * advance).rounded(.down), y: frame.minY, width: 1,
                    height: frame.height
                )
                .fill()
            }
            return frame.maxY < rect.maxY
        }
    }

    /// editor R55: both brackets of the matched pair on a tint of the accent.
    private func drawMatchedBrackets(in rect: NSRect) {
        guard let pair = matchedBrackets else { return }
        bracketColor.setFill()
        for offset in [pair.open, pair.close] {
            guard let frame = self.rect(forCharacterAt: offset), frame.intersects(rect) else { continue }
            NSBezierPath(roundedRect: frame.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2).fill()
        }
    }

    /// editor R53: a 1 pt line at the margin's column, the full height of what is redrawn.
    private func drawPrintMargin(in rect: NSRect) {
        guard let column = printMarginColumn, let font else { return }
        let x = Self.printMarginX(
            column: column, advance: Self.advance(of: font), inset: textContainerInset.width,
            padding: textContainer?.lineFragmentPadding ?? 0)
        guard x >= rect.minX - 1, x <= rect.maxX + 1 else { return }
        printMarginColor.setFill()
        NSRect(x: x.rounded(.down), y: rect.minY, width: 1, height: rect.height).fill()
    }

    /// The width of one character of a monospaced font.
    static func advance(of font: NSFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    /// editor R53: where the margin's line goes — after `column` characters from the text's left.
    nonisolated static func printMarginX(column: Int, advance: CGFloat, inset: CGFloat, padding: CGFloat) -> CGFloat {
        inset + padding + CGFloat(column) * advance
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
