import AppKit

/// design R15: a flat toolbar button — `surfaceRaised` at rest, `surfaceSunken` under the mouse
/// and while pressed, a 1 pt accent outline when it stands for a visible panel (layout R30).
final class ToolbarButton: NSButton {
    static let height: CGFloat = 26
    static let radius: CGFloat = 6

    var tokens = ThemeService.Tokens.dark {
        didSet { paint() }
    }
    var isOutlined = false {
        didSet { paint() }
    }
    private var isHovered = false {
        didSet { paint() }
    }
    private var trackingArea: NSTrackingArea?
    private var widthConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        paint()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Sizes to the content plus horizontal room; called after the image or title changed.
    ///
    /// An icon alone is centred, an icon with a name sits at its left (design R15, the mockups).
    func fit() {
        let isIconOnly = title.trimmingCharacters(in: .whitespaces).isEmpty
        imagePosition = isIconOnly ? .imageOnly : .imageLeading
        paint()
        // A toggle is a square (author, 2026-08-27); a named button fits its content.
        let width = isIconOnly ? Self.height : intrinsicContentSize.width + 20
        if let widthConstraint {
            widthConstraint.constant = width
        } else {
            widthConstraint = widthAnchor.constraint(equalToConstant: width)
            widthConstraint?.isActive = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        paint()
    }

    /// The toolbar gives its items more height than `height`: the plate is drawn here, `height`
    /// tall and centred, so a toggle stays a square whatever frame the item gets (author, 2026-08-28).
    override func draw(_ dirtyRect: NSRect) {
        let plate = NSRect(
            x: 0, y: (bounds.height - Self.height) / 2, width: bounds.width, height: Self.height)
        let path = NSBezierPath(roundedRect: plate, xRadius: Self.radius, yRadius: Self.radius)
        (isHovered || isHighlighted ? tokens.surfaceSunken : tokens.surfaceRaised).nsColor.setFill()
        path.fill()
        if isOutlined {
            tokens.accent.nsColor.setStroke()
            NSBezierPath(roundedRect: plate.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
                .stroke()
        }
        super.draw(dirtyRect)
    }

    private func paint() {
        needsDisplay = true
        contentTintColor = tokens.textPrimary.nsColor
        let name = attributedTitle.string.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            // NSButton has no image-to-title spacing: the space in the title is that gap.
            attributedTitle = NSAttributedString(
                string: image == nil ? name : " " + name,
                attributes: [
                    .foregroundColor: tokens.textPrimary.nsColor, .font: font ?? NSFont.systemFont(ofSize: 13),
                ])
        }
    }
}
