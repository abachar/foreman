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

    /// One declared server: the command, and where it runs (editor R35, R36).
    struct Entry: Equatable, Sendable {
        let command: String
        /// A path relative to the workspace root, `nil` for the root itself (editor R36).
        ///
        /// It exists because a repository is not always a project: `typescript-language-server`
        /// looks for the `typescript` it needs from its own `cwd`, and a monorepo keeps that
        /// under `server/`, not at the root (author, 2026-08-31).
        let cwd: String?
    }

    var timeout: Duration = .seconds(LSPCatalog.defaultTimeout)
    /// Lowercased key (an extension, or a whole file name without one) → the declared server.
    var commands: [String: Entry] = [:]
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
                // A value is `"command"` or `{ "command": …, "cwd": … }` — the shape `run` R2
                // already uses for a command that does not run at the root.
                var entry: Entry?
                if let command = try? container.decode(String.self, forKey: key) {
                    entry = Entry(command: command, cwd: nil)
                } else if let detailed = try? container.decode(Detailed.self, forKey: key),
                    let command = detailed.command
                {
                    entry = Entry(command: command, cwd: detailed.cwd)
                }
                guard let entry else {
                    warnings.append(
                        "lsp.\(key.stringValue) ignored: expected a command, or an object with a command.")
                    continue
                }
                guard !entry.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    warnings.append("lsp.\(key.stringValue) ignored: the command is empty.")
                    continue
                }
                commands[key.stringValue.lowercased()] = entry
            }
        }
    }

    /// The server declared for `url`, keyed by its extension or its whole name.
    ///
    /// The key is built by `FormatterCatalog.key(for:)`: the two sections index files the same way,
    /// and one rule written twice is one rule that can drift.
    func entry(for url: URL) -> Entry? {
        commands[FormatterCatalog.key(for: url).lowercased()]
    }

    private struct Detailed: Decodable {
        var command: String?
        var cwd: String?
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
