import Foundation

/// The `formatter` section of `.wraith/config.json` (editor R25): one shell command per file
/// extension, plus the reserved key `timeout` (R30).
///
/// Read from `workspace.config` on every use, like `insertFinalNewline`: a change on disk takes
/// effect without anything to wire (config R6).
nonisolated struct FormatterCatalog: Decodable, Equatable, Sendable {
    static let empty = FormatterCatalog()
    static let defaultTimeout: Double = 5
    /// editor R30: seconds, clamped.
    static let timeoutRange: ClosedRange<Double> = 1...60

    var timeout: Duration = .seconds(FormatterCatalog.defaultTimeout)
    /// Lowercased key (an extension, or a whole file name without one) → the user's command (R26).
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
                    warnings.append("formatter.timeout ignored: expected a number of seconds.")
                    continue
                }
                timeout = .seconds(min(max(value, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound))
            default:
                guard let command = try? container.decode(String.self, forKey: key) else {
                    warnings.append("formatter.\(key.stringValue) ignored: expected a command string.")
                    continue
                }
                guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    warnings.append("formatter.\(key.stringValue) ignored: the command is empty.")
                    continue
                }
                commands[key.stringValue.lowercased()] = command
            }
        }
    }

    /// editor R25: the key of `url` — its extension, or its whole name when it has none (`Dockerfile`).
    static func key(for url: URL) -> String {
        let ext = url.pathExtension
        return ext.isEmpty ? url.lastPathComponent : ext
    }

    /// The command declared for `key`, case-insensitively.
    func command(forKey key: String) -> String? {
        commands[key.lowercased()]
    }

    /// The first word of a command: what is looked up in the `PATH` (`npx --no-install prettier` → `npx`).
    static func binary(of command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    /// editor R25, edge cases: whether the command's binary exists in `path` (agents R2, without
    /// launching anything); an absolute path is checked directly.
    static func isBinaryAvailable(_ command: String, inPath path: String?) -> Bool {
        let binary = binary(of: command)
        if binary.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: binary)
        }
        return !AgentCatalog.executables(among: [binary], inPath: path).isEmpty
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
