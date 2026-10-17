import Foundation
import JSONRPC
import LanguageServerProtocol

/// The `debug` section of `.foreman/config.json` (debug R1): one adapter per file extension, plus
/// the reserved key `timeout`.
///
/// The twin of `LSPCatalog`: same key rule, same reserved key, same "an invalid entry is dropped,
/// never the section" (config R7). Read from `workspace.config`, so a change on disk needs no wiring.
nonisolated struct DebugCatalog: Decodable, Equatable, Sendable {
    static let empty = DebugCatalog()
    static let defaultTimeout: Double = 10
    /// debug R1: seconds, clamped.
    static let timeoutRange: ClosedRange<Double> = 1...60

    /// How the adapter is reached (debug R1).
    enum Adapter: Equatable, Sendable {
        /// Speaks DAP on stdio: the user's text, run by `$SHELL -l -c`.
        case command(String)
        /// A `workspace/executeCommand` sent to the `lsp.<extension>` server, which answers the
        /// TCP port of an adapter it hosts (M27 27.4: decoded here, not yet run).
        case server(String)
    }

    var timeout: Duration = .seconds(DebugCatalog.defaultTimeout)
    /// Lowercased extension → the declared adapter.
    var adapters: [String: Adapter] = [:]
    /// config R7: an invalid entry is dropped and reported, never the section.
    var warnings: [String] = []

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            let name = key.stringValue
            if name == "timeout" {
                guard let value = try? container.decode(Double.self, forKey: key) else {
                    warnings.append("debug.timeout ignored: expected a number of seconds.")
                    continue
                }
                timeout = .seconds(min(max(value, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound))
                continue
            }
            // A string is the short form of `{ "command": … }`, as in `lsp`.
            let detailed = (try? container.decode(String.self, forKey: key)).map { Detailed(command: $0) }
            guard let entry = detailed ?? (try? container.decode(Detailed.self, forKey: key)) else {
                warnings.append("debug.\(name) ignored: expected a command, or an object with a command or a server.")
                continue
            }
            switch (entry.command, entry.server) {
            case (let command?, nil) where !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                adapters[name.lowercased()] = .command(command)
            case (nil, let server?) where !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                adapters[name.lowercased()] = .server(server)
            case (nil, nil), (_?, _?):
                warnings.append("debug.\(name) ignored: give exactly one of \"command\" and \"server\".")
            default:
                warnings.append("debug.\(name) ignored: the command or the server is empty.")
            }
        }
    }

    private struct Detailed: Decodable {
        var command: String?
        var server: String?
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

/// The `debug` object of a command of `config.commands` (debug R2).
nonisolated struct DebugCommand: Equatable, Sendable {
    enum Request: String, Equatable, Sendable {
        case attach, launch
    }

    /// The lowercased extension naming an entry of `config.debug`.
    ///
    /// Whether one exists is `DebugFeature`'s to check: the two sections decode apart.
    let adapter: String
    let request: Request
    /// The body of the adapter's `launch` or `attach`, in the adapter's own names, passed verbatim.
    let arguments: LSPAny

    /// debug R2: the command's `debug` object, or `nil` with the reason when it is malformed.
    ///
    /// `request` missing is `attach` when `arguments` names a `port` or a `pid`, else `launch`.
    /// The command stays either way.
    static func parse(_ value: LSPAny) -> (command: DebugCommand?, warning: String?) {
        guard case .hash(let object) = value else { return (nil, "\"debug\" must be an object.") }
        guard case .string(let adapter)? = object["adapter"], !adapter.isEmpty else {
            return (nil, "\"debug.adapter\" is required: the extension of an entry of `debug`.")
        }
        var arguments: [String: LSPAny] = [:]
        if let declared = object["arguments"] {
            guard case .hash(let hash) = declared else { return (nil, "\"debug.arguments\" must be an object.") }
            arguments = hash
        }
        let request: Request
        switch object["request"] {
        case nil:
            request = arguments["port"] != nil || arguments["pid"] != nil ? .attach : .launch
        case .string(let name)?:
            guard let named = Request(rawValue: name) else {
                return (nil, "\"debug.request\" is \"attach\" or \"launch\".")
            }
            request = named
        default:
            return (nil, "\"debug.request\" is \"attach\" or \"launch\".")
        }
        return (DebugCommand(adapter: adapter.lowercased(), request: request, arguments: .hash(arguments)), nil)
    }
}
