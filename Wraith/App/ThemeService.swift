import AppKit
import Foundation
import Observation

/// Fonts and colors, created once in `App` and injected (architecture: shared services).
///
/// Minimal until `terminal` R14 brings the full theme (M2): a monospaced font and one system
/// color per highlighting role, so nothing is hard-coded in a feature (coding rules, UI).
@Observable
@MainActor
final class ThemeService {
    let editorFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    /// editor R12: the attributes of a highlighting capture; empty for an uncolored one.
    func attributes(forCapture capture: String) -> [NSAttributedString.Key: Any] {
        guard let role = HighlightRole(capture: capture) else { return [:] }
        return [.foregroundColor: color(for: role)]
    }

    func color(for role: HighlightRole) -> NSColor {
        switch role {
        case .keyword:
            return .systemPurple
        case .string:
            return .systemRed
        case .comment:
            return .secondaryLabelColor
        case .type:
            return .systemTeal
        case .function:
            return .systemBlue
        case .number, .constant:
            return .systemOrange
        case .variable, .operator:
            return .labelColor
        case .punctuation:
            return .secondaryLabelColor
        case .property:
            return .systemIndigo
        case .attribute:
            return .systemBrown
        case .tag:
            return .systemBlue
        case .label:
            return .systemPink
        case .markup:
            return .systemGreen
        }
    }
}
