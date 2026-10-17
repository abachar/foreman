import Foundation
import JSONRPC
import LanguageServerProtocol

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

    /// One declared server: the command, where it runs, and what it is told (editor R35, R36, R57).
    struct Entry: Equatable, Sendable {
        let command: String
        /// A path relative to the workspace root, `nil` for the root itself (editor R36).
        ///
        /// It exists because a repository is not always a project: `typescript-language-server`
        /// looks for the `typescript` it needs from its own `cwd`, and a monorepo keeps that
        /// under `server/`, not at the root (author, 2026-08-31).
        let cwd: String?
        /// editor R57: the server's settings, an object kept verbatim — the user writes what the
        /// server's documentation names (`java.import.exclusions`), Foreman translates nothing.
        ///
        /// `LSPAny` is the protocol's JSON value; it stays here because the catalog is the LSP
        /// feature's own config, and the value goes to the wire untouched (architecture: a
        /// third-party type stays near its use).
        var settings: LSPAny? = nil
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
                    // editor R57: `settings` is an object or nothing; anything else is dropped
                    // with a warning and the entry stays (config R7's spirit, one level down).
                    if case .hash(let object)? = detailed.settings {
                        entry?.settings = .hash(object)
                    } else if detailed.settings != nil {
                        warnings.append("lsp.\(key.stringValue).settings ignored: expected an object.")
                    }
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
        reconcileSettings()
    }

    /// editor R36, R57: two extensions naming one server (same command, same `cwd`) share one
    /// process, so they share its settings — those of the first extension, in key order, that
    /// declares any; an extension declaring none adopts them, one declaring others is a warning,
    /// not a second process.
    private mutating func reconcileSettings() {
        var owners: [String: (extension: String, settings: LSPAny)] = [:]
        let keys = commands.keys.sorted()
        for key in keys {
            guard let entry = commands[key], let settings = entry.settings else { continue }
            let server = Self.serverIdentity(of: entry)
            if owners[server] == nil {
                owners[server] = (key, settings)
            }
        }
        for key in keys {
            guard let entry = commands[key], let owner = owners[Self.serverIdentity(of: entry)] else { continue }
            if let settings = entry.settings, settings != owner.settings {
                warnings.append(
                    "lsp.\(key).settings ignored: `\(owner.extension)` names the same server with other settings, which win."
                )
            }
            commands[key]?.settings = owner.settings
        }
    }

    /// What `LSPServers.ServerKey` is made of (R36), as one string for the pass above.
    private static func serverIdentity(of entry: Entry) -> String {
        entry.command + "\u{0}" + (entry.cwd ?? "")
    }

    /// editor R57: the settings of the server `command` runs in `cwd` — one per server (R36).
    func settings(forCommand command: String, cwd: String?) -> LSPAny? {
        commands.values.first { $0.command == command && $0.cwd == cwd }?.settings
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
        var settings: LSPAny?
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
