import Foundation
import Testing

@testable import Foreman

/// The token sets and the `theme` section (design R7, R9–R11; config R5, R7).
struct ThemeTokensTests {
    private func decodeOverrides(_ json: String) throws -> ThemeService.Tokens.Overrides {
        ThemeService.Tokens.overrides(from: try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8)))
    }

    @Test func parsesShortAndLongHexColorsOnly() {
        #expect(ThemeColor(parsing: "#abc") == ThemeColor(0xAABB_CC))
        #expect(ThemeColor(parsing: "#AaBbCc") == ThemeColor(0xAABB_CC))
        #expect(ThemeColor(parsing: " #4C8DF6 ") == ThemeColor(0x4C8D_F6))
        #expect(ThemeColor(parsing: "#xyz") == nil)
        #expect(ThemeColor(parsing: "4C8DF6") == nil)
        #expect(ThemeColor(parsing: "#4C8DF") == nil)
        #expect(ThemeColor(parsing: "") == nil)
    }

    @Test func contrastRatioOverKnownPairs() {
        let black = ThemeColor(0x0000_00)
        let white = ThemeColor(0xFFFF_FF)
        #expect(abs(ThemeColor.contrastRatio(black, white) - 21) < 0.01)
        #expect(ThemeColor.contrastRatio(white, black) == ThemeColor.contrastRatio(black, white))
        #expect(ThemeColor.contrastRatio(ThemeColor(0x8080_80), ThemeColor(0x8080_80)) == 1)
        // WCAG's worked example: #777777 on white is 4.48:1.
        #expect(abs(ThemeColor.contrastRatio(ThemeColor(0x7777_77), white) - 4.48) < 0.01)
    }

    @Test func theDarkSetMeetsEveryContrastPairOfR7() {
        for pair in ThemeService.Tokens.dark.contrastPairs {
            let ratio = ThemeColor.contrastRatio(pair.foreground, pair.background)
            #expect(ratio >= pair.minimum, Comment(rawValue: "\(pair.name): \(ratio) < \(pair.minimum)"))
        }
    }

    @Test func bothSetsNameEveryHighlightRole() {
        for role in HighlightRole.allCases {
            #expect(ThemeService.Tokens.dark.syntax[role] != nil)
            #expect(ThemeService.Tokens.light.syntax[role] != nil)
        }
        #expect(ThemeService.Tokens.dark != ThemeService.Tokens.light)
    }

    @Test func aMissingSectionKeepsTheDefaults() {
        let overrides = ThemeService.Tokens.overrides(from: nil)
        #expect(overrides == .none)
        #expect(ThemeService.Tokens.dark.applying(overrides) == .dark)
    }

    @Test func appliesColorsAndMetricsAndWarnsOnTheRest() throws {
        let overrides = try decodeOverrides(
            ##"{ "accent": "#4C8DF6", "islandRadius": 10, "barHeight": 500, "surface": "#xyz", "glow": "#fff", "gutter": -2, "textPrimary": 12 }"##
        )
        #expect(overrides.colors == ["accent": ThemeColor(0x4C8D_F6)])
        #expect(overrides.metrics == ["islandRadius": 10])
        #expect(overrides.warnings.count == 5)
        #expect(overrides.warnings.contains("theme.glow ignored: unknown token."))
        #expect(overrides.warnings.contains("theme.surface ignored: expected a color as #rgb or #rrggbb."))
        #expect(overrides.warnings.contains { $0.hasPrefix("theme.barHeight ignored") })
        #expect(overrides.warnings.contains { $0.hasPrefix("theme.gutter ignored") })
        #expect(overrides.warnings.contains { $0.hasPrefix("theme.textPrimary ignored") })

        let tokens = ThemeService.Tokens.dark.applying(overrides)
        #expect(tokens.accent == ThemeColor(0x4C8D_F6))
        #expect(tokens.islandRadius == 10)
        #expect(tokens.barHeight == ThemeService.Tokens.dark.barHeight)
        #expect(tokens.surface == ThemeService.Tokens.dark.surface)
    }

    @Test func appliesTheInterfaceFontKeys() throws {
        let overrides = try decodeOverrides(
            ##"{ "interfaceFont": " Helvetica Neue ", "interfaceFontSize": 14, "codeFont": "x", "interfaceFontSize2": 1 }"##
        )
        #expect(overrides.fonts == ["interfaceFont": "Helvetica Neue"])
        #expect(overrides.metrics == ["interfaceFontSize": 14])
        #expect(overrides.warnings.count == 2)

        let tokens = ThemeService.Tokens.dark.applying(overrides)
        #expect(tokens.interfaceFontName == "Helvetica Neue")
        #expect(tokens.interfaceFontSize == 14)
        #expect(ThemeService.Tokens.dark.interfaceFontName == nil)
        #expect(ThemeService.Tokens.dark.interfaceFontSize == 13)
        // design R6: small = body - 2, title = body + 1.
        #expect(ThemeService.pointSize(of: .small, body: 13) == 11)
        #expect(ThemeService.pointSize(of: .body, body: 13) == 13)
        #expect(ThemeService.pointSize(of: .title, body: 13) == 14)
        #expect(ThemeService.pointSize(of: .small, body: 10) == 9)
    }

    @Test func statusColorsFollowTheBadgeColor() {
        let tokens = ThemeService.Tokens.dark
        #expect(tokens.status(.green) == tokens.statusGreen)
        #expect(tokens.status(.red) == tokens.statusRed)
    }
}
