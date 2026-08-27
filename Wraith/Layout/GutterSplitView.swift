import AppKit

/// design R20: the divider is the gutter — `gutter` points wide, painted in the window ground,
/// no line drawn.
final class GutterSplitView: NSSplitView {
    var gutter: CGFloat = 8 {
        didSet { adjustSubviews() }
    }
    var gutterColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override var dividerThickness: CGFloat {
        gutter
    }

    override func drawDivider(in rect: NSRect) {
        gutterColor.setFill()
        rect.fill()
    }
}
