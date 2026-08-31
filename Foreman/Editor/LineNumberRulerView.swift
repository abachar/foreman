import AppKit

/// The gutter (editor R6): one number per paragraph, drawn from TextKit 2's layout fragments.
///
/// Nothing native draws numbers on TextKit 2 and the libraries that do are whole text views,
/// so this stays: ~80 lines, redrawn on scroll and on every edit.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font: NSFont
    private var observers: [any NSObjectProtocol] = []
    /// design R8: the numbers and the ground come from the tokens.
    var textColor = NSColor.secondaryLabelColor {
        didSet { needsDisplay = true }
    }
    var backgroundColor: NSColor = .clear {
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
    private static let dotDiameter: CGFloat = 6
    private static let chevronWidth: CGFloat = 14
    /// The UTF-16 offset where each line starts, line `i + 1` at `lineStarts[i]`: the draw looks
    /// numbers up here instead of scanning the whole text on every pass.
    private var lineStarts: [Int] = [0]

    init(textView: NSTextView, font: NSFont) {
        self.textView = textView
        self.font = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 1, weight: .regular)
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        // Views no longer clip by default (macOS 14): without this, the ground painted in
        // `draw(_:)` spills over the tab bar and the text (bug: invisible editor, 2026-08-27).
        clipsToBounds = true
        rebuildLineStarts()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildLineStarts() }
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
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let visible = textView.visibleRect
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let inset = textView.textContainerInset
        let width =
            max(44, CGFloat(String(max(1, lineStarts.count)).count + 2) * font.pointSize * 0.7) + Self.chevronWidth
        if abs(ruleThickness - width) > 0.5 {
            ruleThickness = width
        }
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
            let size = label.size(withAttributes: attributes)
            let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? size.height
            label.draw(
                at: NSPoint(
                    x: ruleThickness - Self.chevronWidth - size.width - 4, y: y + lineHeight / 2 - size.height / 2),
                withAttributes: attributes)
            // editor R41: the dot sits left of the numbers, where nothing else draws.
            if let color = diagnosticDots[current] {
                color.setFill()
                let diameter = Self.dotDiameter
                NSBezierPath(
                    ovalIn: NSRect(
                        x: 3, y: y + lineHeight / 2 - diameter / 2, width: diameter, height: diameter)
                ).fill()
            }
            // editor R27: the chevron next to the code, in the numbers' color (author, 2026-08-28).
            if foldRegions.contains(where: { $0.first == current }) {
                let name = foldedLines.contains(current) ? "chevron.right" : "chevron.down"
                let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 3, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [textColor]))
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

    /// editor R27: a click on the chevron strip folds or unfolds that line's region.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x >= ruleThickness - Self.chevronWidth - 4, let textView,
            let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return super.mouseDown(with: event) }
        let y = point.y + textView.visibleRect.minY - textView.textContainerInset.height
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return }
        let offset = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        let line = line(at: offset)
        guard foldRegions.contains(where: { $0.first == line }) else { return }
        onToggleFold?(line)
    }

    /// Re-reads the line starts from the text; the edit observer calls it on every change, and
    /// the reload path must call it too — a programmatic `string` set posts no notification.
    func rebuildLineStarts() {
        guard let text = textView.map({ $0.string as NSString }) else { return }
        var starts = [0]
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            guard range.location != NSNotFound else { break }
            starts.append(NSMaxRange(range))
            index = NSMaxRange(range)
        }
        lineStarts = starts
        needsDisplay = true
    }

    /// The 1-based line containing the UTF-16 `offset`: the last cached start not past it.
    private func line(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }
}
