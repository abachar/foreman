import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import Foreman

/// The `terminal` section and the palettes (terminal R14, config R5).
@MainActor
struct ThemeServiceTests {
    private let fixture = ConfigFixture()

    private func settings(_ json: String?) async throws -> ThemeService.Settings {
        var warnings: [String] = []
        return ThemeService.Settings.decode(from: try await fixture.load(after: json), warnings: &warnings)
    }

    @Test func missingSectionIsTheDefault() async throws {
        defer { fixture.remove() }
        var warnings: [String] = []
        let config = try await fixture.load(after: nil)
        #expect(ThemeService.Settings.decode(from: config, warnings: &warnings) == .defaults)
        #expect(warnings.isEmpty)
    }

    /// config R7: a section of the wrong shape defaults, but says so instead of staying silent.
    @Test func malformedSectionIsTheDefaultAndWarns() async throws {
        defer { fixture.remove() }
        var warnings: [String] = []
        let config = try await fixture.load(after: #"{ "terminal": "nope" }"#)
        #expect(ThemeService.Settings.decode(from: config, warnings: &warnings) == .defaults)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("terminal"))
    }

    @Test func codeFontDefaultsToJetBrainsMonoAndSurvivesAPartialSection() async throws {
        defer { fixture.remove() }
        #expect(ThemeService.Settings.defaults.fontName == "JetBrains Mono")
        #expect(ThemeService.Settings.defaults.fontSize == 13)
        let settings = try await settings(#"{ "terminal": { "fontSize": 14 } }"#)
        #expect(settings.fontName == "JetBrains Mono")
        #expect(settings.fontSize == 14)
    }

    @Test func eachFieldFallsBackOnItsOwn() async throws {
        defer { fixture.remove() }
        let settings = try await settings(#"{ "terminal": { "font": "Menlo", "fontSize": 80, "theme": "neon" } }"#)

        #expect(settings.fontName == "Menlo")
        #expect(settings.fontSize == 32)
        #expect(settings.mode == .system)
        #expect(ThemeService.font(for: settings).pointSize == 32)
        #expect(ThemeService.font(for: settings).familyName == "Menlo")
    }

    @Test func unknownFontFallsBackOnTheSystemMonospacedFont() async throws {
        defer { fixture.remove() }
        let settings = try await settings(#"{ "terminal": { "font": "No Such Font 42", "fontSize": 4 } }"#)

        #expect(settings.fontSize == 8)
        #expect(ThemeService.font(for: settings) == NSFont.monospacedSystemFont(ofSize: 8, weight: .regular))
    }

    @Test func modeResolvesAgainstTheSystemAppearance() async throws {
        defer { fixture.remove() }
        let theme = ThemeService()
        #expect(theme.isDark(systemIsDark: true))
        #expect(!theme.isDark(systemIsDark: false))

        theme.apply(try await fixture.load(after: #"{ "terminal": { "theme": "light" } }"#))
        #expect(!theme.isDark(systemIsDark: true))
        theme.apply(try await fixture.load(after: #"{ "terminal": { "theme": "dark" } }"#))
        #expect(theme.isDark(systemIsDark: false))
    }

    @Test func palettesHaveSixteenAnsiColors() {
        let theme = ThemeService()
        #expect(theme.terminalPalette(dark: true).ansi.count == 16)
        #expect(theme.terminalPalette(dark: false).ansi.count == 16)
        #expect(theme.terminalPalette(dark: true) != theme.terminalPalette(dark: false))
    }

    /// design R13: no boundary inside the island.
    @Test func terminalBackgroundIsTheIslandSurface() {
        let theme = ThemeService()
        #expect(theme.terminalPalette(dark: true).background == ThemeService.Tokens.dark.surface.nsColor)
        #expect(theme.terminalPalette(dark: false).background == ThemeService.Tokens.light.surface.nsColor)
        #expect(theme.terminalPalette(dark: true).foreground == ThemeService.Tokens.dark.textPrimary.nsColor)
    }

    @Test func convertsColorsForSwiftTerm() {
        let red = TerminalSurfaceView.color(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        #expect(red.red == 65535 && red.green == 0 && red.blue == 0)
    }
}

/// A temporary workspace with one `config.json`.
private struct ConfigFixture {
    let root = URL(filePath: NSTemporaryDirectory()).appending(path: "foreman-theme-\(UUID().uuidString)")

    func load(after json: String?) async throws -> WorkspaceConfig {
        if let json {
            let file = root.appending(components: ".foreman", "config.json")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try json.write(to: file, atomically: true, encoding: .utf8)
        }
        return try await WorkspaceConfig.load(root: root)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
