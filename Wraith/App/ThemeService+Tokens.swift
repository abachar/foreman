import Foundation

extension ThemeService {
    /// design R9: the four families, and nothing else; `dark` is designed (the values read off
    /// the mockups on 2026-08-27), `light` is derived and not a goal (R10).
    nonisolated struct Tokens: Equatable, Sendable {
        // Backgrounds
        var windowBackground: ThemeColor
        var surface: ThemeColor
        var surfaceRaised: ThemeColor
        var surfaceSunken: ThemeColor
        /// The palette, floating above the window (decision 2026-08-27).
        var surfaceOverlay: ThemeColor
        // Text and rules
        var textPrimary: ThemeColor
        var textSecondary: ThemeColor
        var textDisabled: ThemeColor
        var separator: ThemeColor
        var border: ThemeColor
        // Accent and states
        var accent: ThemeColor
        var accentText: ThemeColor
        var statusGreen: ThemeColor
        var statusOrange: ThemeColor
        var statusRed: ThemeColor
        var statusBlue: ThemeColor
        // Metrics
        var islandRadius: Double
        var gutter: Double
        var barHeight: Double
        var rowHeight: Double
        var contentInset: Double
        // Type (design R6, 2026-08-28): the interface font, `nil` is the system font.
        var interfaceFontName: String?
        var interfaceFontSize: Double
        /// editor R12: the highlighting colors join the set (backlog M8, 8.2).
        var syntax: [HighlightRole: ThemeColor]

        static let dark = Tokens(
            windowBackground: ThemeColor(0x2123_28), surface: ThemeColor(0x3637_3B),
            surfaceRaised: ThemeColor(0x3336_3A),
            surfaceSunken: ThemeColor(0x1E23_26), surfaceOverlay: ThemeColor(0x2326_2A),
            textPrimary: ThemeColor(0xDFE1_E5), textSecondary: ThemeColor(0x9DA0_A8),
            textDisabled: ThemeColor(0x6F73_7A),
            separator: ThemeColor(0x3D3F_44), border: ThemeColor(0x4548_4E),
            accent: ThemeColor(0x4A86_E0), accentText: ThemeColor(0xFFFF_FF), statusGreen: ThemeColor(0x5FB8_65),
            statusOrange: ThemeColor(0xE0A6_3B), statusRed: ThemeColor(0xE553_4B), statusBlue: ThemeColor(0x4A86_E0),
            islandRadius: 8, gutter: 6, barHeight: 36, rowHeight: 24, contentInset: 12,
            interfaceFontName: nil, interfaceFontSize: 16,
            syntax: [
                .keyword: ThemeColor(0xCF8E_6D), .string: ThemeColor(0x6AAB_73), .comment: ThemeColor(0x7A7E_85),
                .type: ThemeColor(0x56A8_F5), .function: ThemeColor(0x57AA_F7), .number: ThemeColor(0x2AAC_B8),
                .variable: ThemeColor(0xDFE1_E5), .punctuation: ThemeColor(0x9DA0_A8), .operator: ThemeColor(0xDFE1_E5),
                .constant: ThemeColor(0xC77D_BB), .property: ThemeColor(0xC77D_BB), .attribute: ThemeColor(0xB3AE_60),
                .tag: ThemeColor(0xD5B7_78), .label: ThemeColor(0xE8BF_6A), .markup: ThemeColor(0x6AAB_73),
            ])

        /// R10: mechanical, not designed.
        static let light = Tokens(
            windowBackground: ThemeColor(0xEBEC_F0), surface: ThemeColor(0xFFFF_FF),
            surfaceRaised: ThemeColor(0xF4F5_F7),
            surfaceSunken: ThemeColor(0xE6E8_EC), surfaceOverlay: ThemeColor(0xF7F8_FA),
            textPrimary: ThemeColor(0x1E1F_22), textSecondary: ThemeColor(0x5A5D_63),
            textDisabled: ThemeColor(0x9A9D_A3),
            separator: ThemeColor(0xD9DB_E0), border: ThemeColor(0xC9CC_D2),
            accent: ThemeColor(0x3574_F0), accentText: ThemeColor(0xFFFF_FF), statusGreen: ThemeColor(0x2E8B_3E),
            statusOrange: ThemeColor(0xB9711_A), statusRed: ThemeColor(0xC93B_34), statusBlue: ThemeColor(0x3574_F0),
            islandRadius: 8, gutter: 6, barHeight: 36, rowHeight: 24, contentInset: 12,
            interfaceFontName: nil, interfaceFontSize: 16,
            syntax: [
                .keyword: ThemeColor(0x0033_B3), .string: ThemeColor(0x067D_17), .comment: ThemeColor(0x8C8C_8C),
                .type: ThemeColor(0x0072_86), .function: ThemeColor(0x0060_A6), .number: ThemeColor(0x1750_EB),
                .variable: ThemeColor(0x1E1F_22), .punctuation: ThemeColor(0x5A5D_63), .operator: ThemeColor(0x1E1F_22),
                .constant: ThemeColor(0x871D_94), .property: ThemeColor(0x871D_94), .attribute: ThemeColor(0x8A6A_00),
                .tag: ThemeColor(0x0033_B3), .label: ThemeColor(0x9E88_0D), .markup: ThemeColor(0x067D_17),
            ])

        /// design R7: the pairs that must meet a threshold, checked by test over `dark`.
        struct ContrastPair: Sendable {
            let name: String
            let foreground: ThemeColor
            let background: ThemeColor
            let minimum: Double
        }

        var contrastPairs: [ContrastPair] {
            [
                ContrastPair(name: "textPrimary/surface", foreground: textPrimary, background: surface, minimum: 4.5),
                ContrastPair(
                    name: "textPrimary/surfaceRaised", foreground: textPrimary, background: surfaceRaised, minimum: 4.5),
                ContrastPair(
                    name: "textPrimary/windowBackground", foreground: textPrimary, background: windowBackground,
                    minimum: 4.5),
                ContrastPair(name: "textSecondary/surface", foreground: textSecondary, background: surface, minimum: 3),
                ContrastPair(
                    name: "textSecondary/surfaceRaised", foreground: textSecondary, background: surfaceRaised,
                    minimum: 3),
                ContrastPair(name: "accent/surface", foreground: accent, background: surface, minimum: 3),
                ContrastPair(
                    name: "accent/windowBackground", foreground: accent, background: windowBackground, minimum: 3),
                ContrastPair(name: "accentText/accent", foreground: accentText, background: accent, minimum: 3),
            ]
        }

        /// The color of a badge or a git status letter (design R3).
        func status(_ color: ToolbarBadge.BadgeColor) -> ThemeColor {
            switch color {
            case .green: return statusGreen
            case .orange: return statusOrange
            case .red: return statusRed
            case .blue: return statusBlue
            }
        }

        // MARK: - The `theme` section (design R11)

        static let metricRanges: [String: ClosedRange<Double>] = [
            "islandRadius": 0...32, "gutter": 0...32, "barHeight": 24...64, "rowHeight": 16...48,
            "contentInset": 0...48, "interfaceFontSize": 10...24,
        ]

        /// design R11: the font keys take a family name.
        static let fontKeys: Set<String> = ["interfaceFont"]

        struct Overrides: Equatable, Sendable {
            var colors: [String: ThemeColor] = [:]
            var metrics: [String: Double] = [:]
            var fonts: [String: String] = [:]
            var warnings: [String] = []

            static let none = Overrides()
        }

        /// Reads `[key: value]`: an unknown key, a malformed color or an out-of-range metric is a
        /// warning and the default stays (config R7); applied to both sets by `applying`.
        static func overrides(from section: [String: JSONValue]?) -> Overrides {
            var overrides = Overrides()
            for (key, value) in (section ?? [:]).sorted(by: { $0.key < $1.key }) {
                if let range = metricRanges[key] {
                    guard case .number(let number) = value, range.contains(number) else {
                        overrides.warnings.append(
                            "theme.\(key) ignored: expected a number in \(Int(range.lowerBound))…\(Int(range.upperBound))."
                        )
                        continue
                    }
                    overrides.metrics[key] = number
                } else if colorKeys.contains(key) {
                    guard case .string(let text) = value, let color = ThemeColor(parsing: text) else {
                        overrides.warnings.append("theme.\(key) ignored: expected a color as #rgb or #rrggbb.")
                        continue
                    }
                    overrides.colors[key] = color
                } else if fontKeys.contains(key) {
                    guard case .string(let name) = value, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                        overrides.warnings.append("theme.\(key) ignored: expected a font family name.")
                        continue
                    }
                    overrides.fonts[key] = name.trimmingCharacters(in: .whitespaces)
                } else {
                    overrides.warnings.append("theme.\(key) ignored: unknown token.")
                }
            }
            return overrides
        }

        static let colorKeys: Set<String> = [
            "windowBackground", "surface", "surfaceRaised", "surfaceSunken", "surfaceOverlay", "textPrimary",
            "textSecondary", "textDisabled", "separator", "border", "accent", "accentText", "statusGreen",
            "statusOrange", "statusRed", "statusBlue",
        ]

        func applying(_ overrides: Overrides) -> Tokens {
            var tokens = self
            for (key, color) in overrides.colors {
                tokens[color: key] = color
            }
            for (key, value) in overrides.metrics {
                tokens[metric: key] = value
            }
            if let name = overrides.fonts["interfaceFont"] {
                tokens.interfaceFontName = name
            }
            return tokens
        }

        private subscript(color key: String) -> ThemeColor? {
            get { nil }
            set {
                guard let newValue else { return }
                switch key {
                case "windowBackground": windowBackground = newValue
                case "surface": surface = newValue
                case "surfaceRaised": surfaceRaised = newValue
                case "surfaceSunken": surfaceSunken = newValue
                case "surfaceOverlay": surfaceOverlay = newValue
                case "textPrimary": textPrimary = newValue
                case "textSecondary": textSecondary = newValue
                case "textDisabled": textDisabled = newValue
                case "separator": separator = newValue
                case "border": border = newValue
                case "accent": accent = newValue
                case "accentText": accentText = newValue
                case "statusGreen": statusGreen = newValue
                case "statusOrange": statusOrange = newValue
                case "statusRed": statusRed = newValue
                case "statusBlue": statusBlue = newValue
                default: break
                }
            }
        }

        private subscript(metric key: String) -> Double? {
            get { nil }
            set {
                guard let newValue else { return }
                switch key {
                case "islandRadius": islandRadius = newValue
                case "gutter": gutter = newValue
                case "barHeight": barHeight = newValue
                case "rowHeight": rowHeight = newValue
                case "contentInset": contentInset = newValue
                case "interfaceFontSize": interfaceFontSize = newValue
                default: break
                }
            }
        }
    }
}

/// A JSON scalar of the `theme` section: strings are colors, numbers are metrics.
nonisolated enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .other
        }
    }
}
