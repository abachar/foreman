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
    private static let chevronWidth: CGFloat = 14

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
        let text = textView.string as NSString
        let visible = textView.visibleRect
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let inset = textView.textContainerInset
        let width =
            max(44, CGFloat(String(max(1, lineCount(text))).count + 2) * font.pointSize * 0.7) + Self.chevronWidth
        if abs(ruleThickness - width) > 0.5 {
            ruleThickness = width
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
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
                number = lineCount(text.substring(to: offset) as NSString)
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
                at: NSPoint(x: ruleThickness - size.width - 6, y: y + lineHeight / 2 - size.height / 2),
                withAttributes: attributes)
            if foldRegions.contains(where: { $0.first == current }) {
                let name = foldedLines.contains(current) ? "chevron.right" : "chevron.down"
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: font.pointSize - 3, weight: .semibold))
                {
                    let tinted = image.copy() as? NSImage ?? image
                    tinted.isTemplate = true
                    let rect = NSRect(
                        x: 3, y: y + lineHeight / 2 - image.size.height / 2, width: image.size.width,
                        height: image.size.height)
                    textColor.set()
                    tinted.draw(
                        in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            return frame.maxY < visible.maxY + inset.height
        }
    }

    /// editor R27: a click on the chevron strip folds or unfolds that line's region.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x <= Self.chevronWidth + 6, let textView, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return super.mouseDown(with: event) }
        let y = point.y + textView.visibleRect.minY - textView.textContainerInset.height
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return }
        let offset = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        let line = lineCount((textView.string as NSString).substring(to: offset) as NSString)
        guard foldRegions.contains(where: { $0.first == line }) else { return }
        onToggleFold?(line)
    }

    /// 1 + the newlines in `text`: the number of the last paragraph.
    private func lineCount(_ text: NSString) -> Int {
        var count = 1
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            guard range.location != NSNotFound else { break }
            count += 1
            index = NSMaxRange(range)
        }
        return count
    }
}
