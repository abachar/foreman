import Foundation
import JSONRPC
import LanguageServerProtocol

/// The Debug Adapter Protocol's envelope (debug R9): JSON framed by `Content-Length` like LSP, but
/// not JSON-RPC — `seq` numbers every message, a `response` names its request by `request_seq`.
///
/// `arguments` and `body` stay `LSPAny` here: the bodies Foreman reads are the `Codable` structs
/// below, decoded on demand, and a `launch` or `attach` carries the user's object verbatim (R2).
nonisolated struct DAPMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case request, response, event
    }

    var seq: Int
    var type: Kind
    /// A request's name, or the name of the request a response answers.
    var command: String?
    var event: String?
    var arguments: LSPAny?
    var body: LSPAny?
    var requestSeq: Int?
    var success: Bool?
    var message: String?

    private enum CodingKeys: String, CodingKey {
        case seq, type, command, event, arguments, body, success, message
        case requestSeq = "request_seq"
    }

    /// The body as `T`; an absent body is an empty object, so a type of optional fields decodes.
    func decodedBody<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try (body ?? .hash([:])).decoded(type)
    }

    /// The arguments of a reverse request as `T`.
    func decodedArguments<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try (arguments ?? .hash([:])).decoded(type)
    }
}

nonisolated extension LSPAny {
    init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(LSPAny.self, from: JSONEncoder().encode(value))
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

// MARK: - Requests

/// The `arguments` of a request that takes none (`configurationDone`, `threads`).
nonisolated struct DAPEmpty: Codable, Equatable, Sendable {}

nonisolated struct DAPInitializeArguments: Codable, Equatable, Sendable {
    var clientID = "foreman"
    var clientName = "Foreman"
    var adapterID: String
    var linesStartAt1 = true
    var columnsStartAt1 = true
    var pathFormat = "path"
    var supportsRunInTerminalRequest = true
    var supportsVariablePaging = true
}

/// What the adapter answers `initialize` with; Foreman reads the one capability that changes the order.
nonisolated struct DAPCapabilities: Codable, Equatable, Sendable {
    var supportsConfigurationDoneRequest: Bool?
}

nonisolated struct DAPSource: Codable, Equatable, Sendable {
    var name: String?
    var path: String?
    var sourceReference: Int?
}

nonisolated struct DAPSetBreakpointsArguments: Codable, Equatable, Sendable {
    struct Breakpoint: Codable, Equatable, Sendable {
        var line: Int
    }

    var source: DAPSource
    var breakpoints: [Breakpoint]
}

nonisolated struct DAPBreakpoint: Codable, Equatable, Sendable {
    var id: Int?
    var verified: Bool
    var line: Int?
    var message: String?
}

nonisolated struct DAPSetBreakpointsResponse: Codable, Equatable, Sendable {
    var breakpoints: [DAPBreakpoint]
}

nonisolated struct DAPThread: Codable, Equatable, Sendable {
    var id: Int
    var name: String
}

nonisolated struct DAPThreadsResponse: Codable, Equatable, Sendable {
    var threads: [DAPThread]
}

nonisolated struct DAPStackTraceArguments: Codable, Equatable, Sendable {
    var threadId: Int
    var startFrame: Int?
    var levels: Int?
}

nonisolated struct DAPStackFrame: Codable, Equatable, Sendable {
    var id: Int
    var name: String
    var source: DAPSource?
    var line: Int
    var column: Int
}

nonisolated struct DAPStackTraceResponse: Codable, Equatable, Sendable {
    var stackFrames: [DAPStackFrame]
    var totalFrames: Int?
}

nonisolated struct DAPScopesArguments: Codable, Equatable, Sendable {
    var frameId: Int
}

nonisolated struct DAPScope: Codable, Equatable, Sendable {
    var name: String
    var variablesReference: Int
    var expensive: Bool
}

nonisolated struct DAPScopesResponse: Codable, Equatable, Sendable {
    var scopes: [DAPScope]
}

nonisolated struct DAPVariablesArguments: Codable, Equatable, Sendable {
    var variablesReference: Int
    var start: Int?
    var count: Int?
}

nonisolated struct DAPVariable: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var type: String?
    var variablesReference: Int
    var indexedVariables: Int?
    var namedVariables: Int?
}

nonisolated struct DAPVariablesResponse: Codable, Equatable, Sendable {
    var variables: [DAPVariable]
}

/// `continue`, `next`, `stepIn`, `stepOut` and `pause` all take a thread and nothing else Foreman uses.
nonisolated struct DAPThreadArguments: Codable, Equatable, Sendable {
    var threadId: Int
}

nonisolated struct DAPEvaluateArguments: Codable, Equatable, Sendable {
    var expression: String
    var frameId: Int?
    var context: String?
}

nonisolated struct DAPEvaluateResponse: Codable, Equatable, Sendable {
    var result: String
    var type: String?
    var variablesReference: Int
}

nonisolated struct DAPDisconnectArguments: Codable, Equatable, Sendable {
    var terminateDebuggee: Bool
}

// MARK: - Events

nonisolated struct DAPStoppedEvent: Codable, Equatable, Sendable {
    var reason: String
    var description: String?
    var threadId: Int?
    var allThreadsStopped: Bool?
    var text: String?
}

nonisolated struct DAPContinuedEvent: Codable, Equatable, Sendable {
    var threadId: Int
    var allThreadsContinued: Bool?
}

nonisolated struct DAPOutputEvent: Codable, Equatable, Sendable {
    var category: String?
    var output: String
}

nonisolated struct DAPExitedEvent: Codable, Equatable, Sendable {
    var exitCode: Int
}

// MARK: - Reverse request

/// `runInTerminal` (debug R8), served by `DebugFeature+Launch`. `env` values may be `null`,
/// which the protocol means as "unset this variable".
nonisolated struct DAPRunInTerminalArguments: Codable, Equatable, Sendable {
    var kind: String?
    var title: String?
    var cwd: String
    var args: [String]
    var env: [String: String?]?
}

/// The reply to `runInTerminal`: the process the terminal started.
nonisolated struct DAPRunInTerminalResponse: Codable, Equatable, Sendable {
    var processId: Int?
}
