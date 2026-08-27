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
        wantsLayer = true
        layer?.cornerRadius = Self.radius
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

    private func paint() {
        let fill = isHovered || isHighlighted ? tokens.surfaceSunken : tokens.surfaceRaised
        layer?.backgroundColor = fill.nsColor.cgColor
        layer?.borderWidth = isOutlined ? 1 : 0
        layer?.borderColor = tokens.accent.nsColor.cgColor
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
