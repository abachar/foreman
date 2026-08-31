import Foundation

/// The `lsp` section of `.foreman/config.json` (editor R35): one shell command per file
/// extension, plus the reserved key `timeout` (R39).
///
/// The twin of `FormatterCatalog`: same key rule (an extension, or a whole file name without
/// one), same reserved key, same "an invalid entry is dropped, never the section" (config R7).
/// Read from `workspace.config` on every use, so a change on disk needs no wiring.
nonisolated struct LSPCatalog: Decodable, Equatable, Sendable {
    static let empty = LSPCatalog()
    static let defaultTimeout: Double = 10
    /// editor R39: seconds, clamped.
    static let timeoutRange: ClosedRange<Double> = 1...60

    var timeout: Duration = .seconds(LSPCatalog.defaultTimeout)
    /// Lowercased key (an extension, or a whole file name without one) → the user's command.
    var commands: [String: String] = [:]
    /// config R7: an invalid entry is dropped and reported, never the section.
    var warnings: [String] = []

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            switch key.stringValue {
            case "timeout":
                guard let value = try? container.decode(Double.self, forKey: key) else {
                    warnings.append("lsp.timeout ignored: expected a number of seconds.")
                    continue
                }
                timeout = .seconds(min(max(value, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound))
            default:
                guard let command = try? container.decode(String.self, forKey: key) else {
                    warnings.append("lsp.\(key.stringValue) ignored: expected a command string.")
                    continue
                }
                guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    warnings.append("lsp.\(key.stringValue) ignored: the command is empty.")
                    continue
                }
                commands[key.stringValue.lowercased()] = command
            }
        }
    }

    /// The command declared for `url`, keyed by its extension or its whole name.
    ///
    /// The key is built by `FormatterCatalog.key(for:)`: the two sections index files the same way,
    /// and one rule written twice is one rule that can drift.
    func command(for url: URL) -> String? {
        commands[FormatterCatalog.key(for: url).lowercased()]
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
