import AppKit
import SwiftUI

extension ThemeService {
    /// design R6: three interface sizes, derived from the `interfaceFontSize` token.
    enum TextStyle {
        case small
        case body
        case title
    }

    /// The interface font (design R6): the system font, or the `theme.interfaceFont` of the
    /// config, at the style's size; `medium` is the only other weight.
    func interfaceFont(_ style: TextStyle = .body, weight: NSFont.Weight = .regular) -> NSFont {
        let size = Self.pointSize(of: style, body: tokens.interfaceFontSize)
        if let name = tokens.interfaceFontName, let font = Self.font(family: name, size: size, weight: weight) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    func font(_ style: TextStyle = .body, weight: NSFont.Weight = .regular) -> Font {
        Font(interfaceFont(style, weight: weight))
    }

    /// design R6 (2026-08-29): the markdown preview's type, scaled from the `readingFontSize` token
    /// (body 1, headings 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85, small 0.875).
    func readingFont(scale: CGFloat = 1, weight: NSFont.Weight = .regular) -> NSFont {
        let size = (tokens.readingFontSize * scale).rounded()
        if let name = tokens.interfaceFontName, let font = Self.font(family: name, size: size, weight: weight) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// The configured family at `weight`, or `nil` when the family does not exist: the caller then
    /// falls back on the system font. The weight travels in the descriptor, so `.medium` stays
    /// medium and `.bold` bold (`NSFontManager`'s bold trait made every non-regular weight bold);
    /// a family without the exact face gets the closest one the descriptor matching finds.
    private static func font(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        guard let font = NSFont(name: family, size: size) else { return nil }
        guard weight != .regular else { return font }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// design R6 (2026-08-29): code in the preview, the code font at 0.85 of the reading size.
    ///
    /// `scale` shrinks the whole rendering with it (editor R42, 2026-08-31): the hover popover is
    /// a tooltip, not a document, and it reads the same markdown at a smaller size.
    func readingCodeFont(scale: CGFloat = 1) -> NSFont {
        editorFont.withSize((tokens.readingFontSize * 0.85 * scale).rounded())
    }

    var readingCodeFont: NSFont {
        readingCodeFont()
    }

    /// The code font at an interface size: a sha, a line number, a ref in a list.
    func codeFont(_ style: TextStyle = .body) -> Font {
        Font(editorFont.withSize(Self.pointSize(of: style, body: tokens.interfaceFontSize)))
    }

    /// Rows of the native lists (explorer, schema): the token, or what the font needs.
    var listRowHeight: CGFloat {
        max(tokens.rowHeight, (interfaceFont().pointSize * 1.5).rounded(.up))
    }

    /// design R6: `small` two points under the body, `title` one over it.
    nonisolated static func pointSize(of style: TextStyle, body: Double) -> CGFloat {
        switch style {
        case .small: return max(9, body - 2)
        case .body: return body
        case .title: return body + 1
        }
    }
}
