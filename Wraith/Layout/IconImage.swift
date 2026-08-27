import AppKit

/// The icon a feature declares for a toolbar item or a home entry (layout R30, agents R3): an SF
/// Symbol name, the name of an image of the asset catalog, or the absolute path of an SVG/PNG file.
enum IconImage {
    static func resolve(_ icon: String) -> NSImage? {
        if let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            return symbol
        }
        if let asset = NSImage(named: icon) {
            return asset
        }
        guard icon.hasPrefix("/"), let file = NSImage(contentsOfFile: icon) else { return nil }
        // Drawn like a symbol: one color, the toolbar's.
        file.isTemplate = true
        return file
    }
}
