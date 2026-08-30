import AppKit

/// The icon a feature declares for a toolbar item or a home entry (layout R30, agents R3): an SF
/// Symbol name, the name of an image of the asset catalog, or the absolute path of an SVG/PNG file.
enum IconImage {
    /// The size of a toolbar symbol; an SVG keeps its own viewBox, so it is fitted here.
    static let pointSize: CGFloat = 18

    static func resolve(_ icon: String) -> NSImage? {
        if let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            return symbol
        }
        let image: NSImage
        // `NSImage(named:)` hands back the instance it caches for the whole app: setting
        // `isTemplate` and `size` on it changed that shared image everywhere it is drawn, at
        // whatever size the last caller wanted (audit M15).
        if let asset = NSImage(named: icon), let copy = asset.copy() as? NSImage {
            image = copy
        } else if icon.hasPrefix("/"), let file = NSImage(contentsOfFile: icon) {
            image = file
        } else {
            return nil
        }
        // Drawn like a symbol: one color, the toolbar's, at the toolbar's size.
        image.isTemplate = true
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = pointSize / max(size.width, size.height)
        image.size = NSSize(width: size.width * scale, height: size.height * scale)
        return image
    }
}
