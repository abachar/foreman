import AppKit

/// design R3: the selected row of a native list sits on the accent — full when the list has the
/// keyboard, faded when it does not — instead of the system selection color.
final class TokenRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("token-row")

    var tokens = ThemeService.Tokens.dark {
        didSet { needsDisplay = true }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        (isEmphasized ? tokens.accent.nsColor : tokens.accent.nsColor(alpha: 0.35)).setFill()
        bounds.intersection(dirtyRect).fill()
    }
}
