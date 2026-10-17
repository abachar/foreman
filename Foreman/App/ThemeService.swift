import AppKit
import Foundation
import Observation
import os

/// Fonts and colors, created once in `App` and injected (architecture: shared services).
///
/// terminal R14: the monospaced font, its size and the terminal theme come from the `terminal`
/// section of `.foreman/config.json`, reloaded with it; nothing is hard-coded in a feature
/// (coding rules, UI). design R8, R9: every color and metric of the chrome is a token of `tokens`,
/// the `dark` or `light` set (R10) with the `theme` section's overrides (R11).
@Observable
@MainActor
final class ThemeService {
    /// The `terminal` section (terminal R14, config R3).
    nonisolated struct Settings: Equatable, Sendable {
        enum Mode: String, Decodable, Sendable {
            case light
            case dark
            case system
        }

        static let sizeRange: ClosedRange<CGFloat> = 8...32
        /// JetBrains Mono at 13 (design decision 2026-08-28); the system monospaced font when absent.
        static let defaults = Settings(fontName: "JetBrains Mono", fontSize: 13, mode: .system)

        /// `nil` is the system monospaced font.
        var fontName: String?
        var fontSize: CGFloat
        var mode: Mode

        private struct Section: Decodable {
            var font: String?
            var fontSize: CGFloat?
            var theme: String?
        }

        /// Decodes the section; a missing or invalid one is the defaults, each field falling
        /// back on its own (config R5, R7: nothing here breaks the workspace).
        ///
        /// A section of the wrong shape also defaults, but is reported in `warnings` like a bad
        /// theme key.
        static func decode(from config: WorkspaceConfig, warnings: inout [String]) -> Settings {
            let section: Section?
            do {
                section = try config.section("terminal", as: Section.self)
            } catch {
                warnings.append("\"terminal\" ignored: expected an object (font, fontSize, theme).")
                return defaults
            }
            guard let section else { return defaults }
            var settings = defaults
            if let font = section.font, !font.isEmpty {
                settings.fontName = font
            }
            if let size = section.fontSize {
                settings.fontSize = min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
            }
            settings.mode = section.theme.flatMap(Mode.init(rawValue:)) ?? .system
            return settings
        }
    }

    /// terminal R14: what a surface paints with, resolved for one appearance.
    struct TerminalPalette: Equatable {
        let foreground: NSColor
        let background: NSColor
        let cursor: NSColor
        let selection: NSColor
        /// The 16 ANSI colors, normal then bright.
        let ansi: [NSColor]
    }

    private(set) var settings = Settings.defaults
    private(set) var editorFont = ThemeService.font(for: .defaults)
    /// design R11: the user's `theme` section, applied over both sets.
    private(set) var overrides = Tokens.Overrides.none
    /// The system appearance, observed so `tokens` follows it without a view in the loop.
    private(set) var systemIsDark: Bool {
        didSet { refreshTokens() }
    }
    /// design R10: the set of the current mode, with the overrides.
    ///
    /// Stored, refreshed in `apply` and on an appearance change: Neon reads it per token (audit
    /// 2026-10-17 U5).
    private(set) var tokens: Tokens
    private var appearanceObservation: NSKeyValueObservation?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "theme")

    init() {
        let dark = Self.isDark(NSApp?.effectiveAppearance)
        systemIsDark = dark
        tokens = (dark ? Tokens.dark : Tokens.light).applying(.none)
        appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, change in
            let dark = Self.isDark(change.newValue)
            Task { @MainActor in self?.systemIsDark = dark }
        }
    }

    nonisolated static func isDark(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// config R6: called at startup and on every accepted reload.
    func apply(_ config: WorkspaceConfig) {
        var terminalWarnings: [String] = []
        let decoded = Settings.decode(from: config, warnings: &terminalWarnings)
        for warning in terminalWarnings {
            logger.warning("\(warning, privacy: .public)")
        }
        if decoded != settings {
            settings = decoded
            editorFont = Self.font(for: decoded)
        }
        let section = (try? config.section("theme", as: [String: JSONValue].self)) ?? nil
        let themeOverrides = Tokens.overrides(from: section)
        let overridesChanged = themeOverrides != overrides
        if overridesChanged {
            overrides = themeOverrides
        }
        // The mode or the overrides may have changed; the warnings below read the fresh set.
        refreshTokens()
        guard overridesChanged else { return }
        for warning in themeOverrides.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        // design, edge cases: a user value that breaks R7 is applied anyway, and said once.
        for pair in tokens.contrastPairs
        where ThemeColor.contrastRatio(pair.foreground, pair.background) < pair.minimum {
            logger.warning("theme: \(pair.name, privacy: .public) is under the contrast R7 asks for")
        }
    }

    /// Assigned only on a real change, so a reload that changes nothing redraws nothing.
    private func refreshTokens() {
        let fresh = (isDark(systemIsDark: systemIsDark) ? Tokens.dark : Tokens.light).applying(overrides)
        guard fresh != tokens else { return }
        tokens = fresh
    }

    /// terminal R14: `system` follows the window's appearance; `light`/`dark` force one.
    func isDark(systemIsDark: Bool) -> Bool {
        switch settings.mode {
        case .light: return false
        case .dark: return true
        case .system: return systemIsDark
        }
    }

    /// design R10, R13: a view of the token set — the surface, the text and the accent are the
    /// island's, the 16 ANSI colors stay the set validated on four agents in M2 (decision 8.8).
    func terminalPalette(dark: Bool) -> TerminalPalette {
        let tokens = (dark ? Tokens.dark : Tokens.light).applying(overrides)
        return TerminalPalette(
            foreground: tokens.textPrimary.nsColor, background: tokens.surface.nsColor,
            cursor: tokens.textPrimary.nsColor, selection: tokens.accent.nsColor(alpha: 0.35),
            ansi: dark ? Self.darkAnsi : Self.lightAnsi)
    }

    /// The palette of the current mode and appearance.
    var terminalPalette: TerminalPalette {
        terminalPalette(dark: isDark(systemIsDark: systemIsDark))
    }

    /// Edge cases: an unknown font name falls back on the system monospaced font.
    nonisolated static func font(for settings: Settings) -> NSFont {
        if let name = settings.fontName, let font = NSFont(name: name, size: settings.fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
    }

    // MARK: - Highlighting (editor R12)

    /// editor R12: the attributes of a highlighting capture; empty for an uncolored one.
    func attributes(forCapture capture: String) -> [NSAttributedString.Key: Any] {
        guard let role = HighlightRole(capture: capture) else { return [:] }
        return [.foregroundColor: color(for: role)]
    }

    /// design R9: the role's token; `codeText` for a role the set does not name — `variable`,
    /// `operator` and `punctuation` are the code's own text (M25 25.3, 2026-10-17).
    func color(for role: HighlightRole) -> NSColor {
        (tokens.syntax[role] ?? tokens.codeText).nsColor
    }

    // MARK: - Code surfaces (design R6, R9; M25 25.3)

    /// The paragraph style of every code text view.
    ///
    /// The line height is `codeLineHeight` times the font's. Set as the view's default style
    /// **and** in its typing attributes — Neon
    /// re-applies the typing attributes under every token it colours, so a style kept anywhere
    /// else would be wiped at the first highlight.
    var codeParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = tokens.codeLineHeight
        return style
    }

    /// The height of one code line in points, for the surfaces that lay their lines out
    /// themselves (the diff's rows): the font's line height times `codeLineHeight`.
    var codeLinePitch: CGFloat {
        Self.linePitch(of: editorFont, multiple: tokens.codeLineHeight)
    }

    /// The extra space between two lines of `font` that `codeLineHeight` asks for — what a
    /// SwiftUI `Text` takes as `lineSpacing` to match the text views.
    func codeLineSpacing(for font: NSFont) -> CGFloat {
        Self.linePitch(of: font, multiple: tokens.codeLineHeight) - Self.linePitch(of: font, multiple: 1)
    }

    /// A font's line height times `multiple`, the way TextKit lays it out: ascender, descender
    /// and leading rounded **up** to the point first (`NSLayoutManager.defaultLineHeight`), the
    /// multiple applied after — so a text view's fragments and a SwiftUI row agree to the point.
    nonisolated static func linePitch(of font: NSFont, multiple: Double) -> CGFloat {
        (font.ascender - font.descender + font.leading).rounded(.up) * multiple
    }

    // MARK: - Git (git R6, explorer R15)

    /// The color of a status letter and of an explorer badge.
    func color(for status: GitFileStatus) -> NSColor {
        switch status {
        case .modified: return tokens.statusOrange.nsColor
        case .added, .untracked: return tokens.statusGreen.nsColor
        case .deleted, .conflicted: return tokens.statusRed.nsColor
        case .renamed: return tokens.statusBlue.nsColor
        case .ignored: return tokens.textDisabled.nsColor
        }
    }

    /// git R13: the tint behind an added or a removed diff line.
    func diffLineBackground(added: Bool) -> NSColor {
        (added ? tokens.statusGreen : tokens.statusRed).nsColor(alpha: 0.16)
    }

    // MARK: - Postgres (postgres R5, R6)

    /// R5: the header's dot.
    func color(for state: PostgresClient.State) -> NSColor {
        switch state {
        case .disconnected: return tokens.textDisabled.nsColor
        case .connecting: return tokens.statusOrange.nsColor
        case .connected: return tokens.statusGreen.nsColor
        case .error: return tokens.statusRed.nsColor
        }
    }

    /// R6: the icon tint of a schema row.
    func schemaTint(for node: SchemaNode) -> NSColor {
        switch node.kind {
        case .database, .schema, .category, .section, .truncated, .detail: return tokens.textSecondary.nsColor
        case .relation, .sequence, .type: return tokens.statusBlue.nsColor
        case .function: return (tokens.syntax[.keyword] ?? tokens.textPrimary).nsColor
        case .column(let column): return (column.isPrimaryKey ? tokens.statusOrange : tokens.textSecondary).nsColor
        }
    }

    // MARK: - Palettes (terminal R14)

    private static let lightAnsi = [
        rgb(0x00, 0x00, 0x00), rgb(0xC9, 0x1B, 0x00), rgb(0x00, 0xC2, 0x00), rgb(0xC7, 0xC4, 0x00),
        rgb(0x02, 0x25, 0xC7), rgb(0xCA, 0x30, 0xC7), rgb(0x00, 0xC5, 0xC7), rgb(0xC7, 0xC7, 0xC7),
        rgb(0x68, 0x68, 0x68), rgb(0xFF, 0x6E, 0x67), rgb(0x5F, 0xF9, 0x67), rgb(0xFE, 0xFB, 0x67),
        rgb(0x68, 0x71, 0xFF), rgb(0xFF, 0x77, 0xFF), rgb(0x60, 0xFD, 0xFF), rgb(0xFF, 0xFF, 0xFF),
    ]

    private static let darkAnsi = [
        rgb(0x1E, 0x1E, 0x1E), rgb(0xF1, 0x4C, 0x4C), rgb(0x23, 0xD1, 0x8B), rgb(0xF5, 0xF5, 0x43),
        rgb(0x3B, 0x8E, 0xEA), rgb(0xD6, 0x70, 0xD6), rgb(0x29, 0xB8, 0xDB), rgb(0xCC, 0xCC, 0xCC),
        rgb(0x66, 0x66, 0x66), rgb(0xF1, 0x4C, 0x4C), rgb(0x23, 0xD1, 0x8B), rgb(0xF5, 0xF5, 0x43),
        rgb(0x3B, 0x8E, 0xEA), rgb(0xD6, 0x70, 0xD6), rgb(0x29, 0xB8, 0xDB), rgb(0xE5, 0xE5, 0xE5),
    ]

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
