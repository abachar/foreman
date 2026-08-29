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
        if let name = tokens.interfaceFontName, let font = NSFont(name: name, size: size) {
            return weight == .regular ? font : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
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
        if let name = tokens.interfaceFontName, let font = NSFont(name: name, size: size) {
            return weight == .regular ? font : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// design R6 (2026-08-29): code in the preview, the code font at 0.85 of the reading size.
    var readingCodeFont: NSFont {
        editorFont.withSize((tokens.readingFontSize * 0.85).rounded())
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
