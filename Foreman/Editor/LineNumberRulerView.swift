import AppKit

/// The gutter (editor R6): one number per paragraph, drawn from TextKit 2's layout fragments.
///
/// Nothing native draws numbers on TextKit 2 and the libraries that do are whole text views,
/// so this stays: ~80 lines, redrawn on scroll and on every edit. The line starts are the text
/// view's (`CurrentLineTextView.lineStarts`), computed once per edit for the guides, the sticky
/// lines and the gutter alike (audit 2026-10-17 U2).
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font: NSFont
    private var observers: [any NSObjectProtocol] = []
    /// design R8: the numbers and the ground come from the tokens.
    var textColor = NSColor.secondaryLabelColor {
        didSet { needsDisplay = true }
    }
    /// design R9 (M25 25.3): the caret's line is the one number that steps forward.
    var currentLineTextColor = NSColor.labelColor {
        didSet { needsDisplay = true }
    }
    /// editor R27 (amended 2026-10-16): the caret's block markers, then the others.
    var activeMarkerColor = NSColor.labelColor {
        didSet { needsDisplay = true }
    }
    var markerColor = NSColor.tertiaryLabelColor {
        didSet { needsDisplay = true }
    }
    var backgroundColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    /// design R25 (2026-10-16): the 1 pt line between the gutter and the text.
    var separatorColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    /// editor R27: a chevron on the first line of every region; folded ones point right.
    var foldRegions: [FoldRegion] = [] {
        didSet { needsDisplay = true }
    }
    var foldedLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }
    var onToggleFold: ((Int) -> Void)?
    /// editor R41: a dot on every line carrying a diagnostic, in its severity's colour.
    var diagnosticDots: [Int: NSColor] = [:] {
        didSet {
            guard diagnosticDots != oldValue else { return }
            needsDisplay = true
        }
    }
    /// debug R4: a dot on every line with a breakpoint, right of the diagnostics' — filled when the
    /// adapter verified it, hollow before a session and when it refused it.
    var breakpointDots: [Int: Bool] = [:] {
        didSet {
            guard breakpointDots != oldValue else { return }
            needsDisplay = true
        }
    }
    var breakpointColor = NSColor.systemRed {
        didSet { needsDisplay = true }
    }
    /// debug R4: a click on the numbers; `nil` where the tab takes no breakpoint.
    var onToggleBreakpoint: ((Int) -> Void)?
    private static let dotDiameter: CGFloat = 6
    private static let chevronWidth: CGFloat = 14
    /// The UTF-16 offset where each line starts, line `i + 1` at `lineStarts[i]`: the draw looks
    /// numbers up in the text view's copy instead of scanning the whole text on every pass.
    private var lineStarts: [Int] {
        (textView as? CurrentLineTextView)?.lineStarts ?? [0]
    }

    init(textView: NSTextView, font: NSFont) {
        self.textView = textView
        self.font = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 1, weight: .regular)
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        // Views no longer clip by default (macOS 14): without this, the ground painted in
        // `draw(_:)` spills over the tab bar and the text (bug: invisible editor, 2026-08-27).
        clipsToBounds = true
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            })
        // design R9 (M25 25.3): the current line's number follows the caret.
        observers.append(
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            })
        if let clip = textView.enclosingScrollView?.contentView {
            observers.append(
                center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true }
                })
        }
    }

    required init(coder: NSCoder) {
        fatalError("not used: the ruler is built in code")
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
        drawHashMarksAndLabels(in: dirtyRect)
        separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let visible = textView.visibleRect
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let currentAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: currentLineTextColor]
        let caretLine = textView.selectedRange().length == 0 ? line(at: textView.selectedRange().location) : nil
        let inset = textView.textContainerInset
        let width =
            max(44, CGFloat(String(max(1, lineStarts.count)).count + 2) * font.pointSize * 0.7) + Self.chevronWidth
        if abs(ruleThickness - width) > 0.5 {
            ruleThickness = width
        }
        let markers = FoldMarkers.markers(
            regions: foldRegions, folded: foldedLines, active: (textView as? CurrentLineTextView)?.activeRegion)
        var number: Int?
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY - inset.height))?.rangeInElement
                .location ?? layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            if number == nil {
                let offset = contentManager.offset(
                    from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
                number = line(at: offset)
            }
            guard let current = number else { return false }
            number = current + 1
            // editor R26: a folded line has no height and no number.
            guard frame.height >= 1 else { return true }
            let y = frame.minY + inset.height - visible.minY
            let label = "\(current)" as NSString
            let labelAttributes = current == caretLine ? currentAttributes : attributes
            let size = label.size(withAttributes: labelAttributes)
            let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? size.height
            label.draw(
                at: NSPoint(
                    x: ruleThickness - Self.chevronWidth - size.width - 4, y: y + lineHeight / 2 - size.height / 2),
                withAttributes: labelAttributes)
            // editor R41: the dot sits left of the numbers, where nothing else draws.
            if let color = diagnosticDots[current] {
                color.setFill()
                let diameter = Self.dotDiameter
                NSBezierPath(
                    ovalIn: NSRect(
                        x: 3, y: y + lineHeight / 2 - diameter / 2, width: diameter, height: diameter)
                ).fill()
            }
            // debug R4: the breakpoint's dot, next to the diagnostics'.
            if let verified = breakpointDots[current] {
                let dot = NSRect(
                    x: 3 + Self.dotDiameter + 2, y: y + lineHeight / 2 - Self.dotDiameter / 2,
                    width: Self.dotDiameter, height: Self.dotDiameter)
                breakpointColor.setFill()
                breakpointColor.setStroke()
                if verified {
                    NSBezierPath(ovalIn: dot).fill()
                } else {
                    let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
                    ring.lineWidth = 1
                    ring.stroke()
                }
            }
            // editor R27 (amended 2026-10-16): the markers next to the code — opening on a region's
            // first line, closing on its closer's — the caret's block brighter.
            if let marker = markers[current] {
                let name =
                    switch marker.kind {
                    case .open: "chevron.down"
                    case .folded: "chevron.right"
                    case .close: "chevron.up"
                    }
                let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 3, weight: .semibold)
                    .applying(
                        NSImage.SymbolConfiguration(paletteColors: [marker.isActive ? activeMarkerColor : markerColor]))
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration)
                {
                    let rect = NSRect(
                        x: ruleThickness - Self.chevronWidth + (Self.chevronWidth - image.size.width) / 2,
                        y: y + lineHeight / 2 - image.size.height / 2, width: image.size.width,
                        height: image.size.height)
                    image.draw(
                        in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            return frame.maxY < visible.maxY + inset.height
        }
    }

    /// editor R27: a click on a marker folds or unfolds its region; debug R4: a click on the numbers,
    /// left of the markers, toggles a breakpoint.
    ///
    /// Nothing else in the gutter answers: `NSRulerView`'s own handling would offer to add a ruler marker.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let textView,
            let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let y = point.y + textView.visibleRect.minY - textView.textContainerInset.height
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return }
        let offset = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        let line = line(at: offset)
        guard point.x >= ruleThickness - Self.chevronWidth - 4 else {
            onToggleBreakpoint?(line)
            return
        }
        let markers = FoldMarkers.markers(regions: foldRegions, folded: foldedLines, active: nil)
        guard let marker = markers[line] else { return }
        onToggleFold?(marker.region.first)
    }

    /// The 1-based line containing the UTF-16 `offset`: the last cached start not past it.
    private func line(at offset: Int) -> Int {
        IndentGuides.line(at: offset, starts: lineStarts)
    }
}
