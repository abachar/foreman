import AppKit
import Foundation
import SwiftUI

/// An sRGB color of the token set (design R8, R9): a value type so the sets are `Sendable` and
/// testable; `nsColor` / `color` at the boundary with AppKit and SwiftUI.
nonisolated struct ThemeColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`.
    init(_ hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// design R11: `#rgb` or `#rrggbb`, case-insensitive; anything else is `nil`.
    init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var digits = String(trimmed.dropFirst())
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(value)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    func nsColor(alpha: Double) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// design R7: WCAG 2.x relative luminance.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// design R7: the WCAG contrast ratio, from 1 (identical) to 21 (black on white).
    static func contrastRatio(_ a: ThemeColor, _ b: ThemeColor) -> Double {
        let lighter = max(a.relativeLuminance, b.relativeLuminance)
        let darker = min(a.relativeLuminance, b.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
