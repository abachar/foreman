import Foundation
import JSONRPC
import LanguageServerProtocol

/// Where the session is, in words (debug R6), and which controls and shortcuts that allows (R7).
nonisolated enum DebugState: Equatable, Sendable {
    case none
    /// `attaching to localhost:5005`, `launching /path/to/program`.
    case starting(String)
    case paused(frame: String, line: Int)
    case running
    case ended
    /// debug R11: the adapter's own words.
    case failed(String)

    var text: String {
        switch self {
        case .none: return ""
        case .starting(let what): return what
        case .paused(let frame, let line): return "paused in \(frame) line \(line)"
        case .running: return "running"
        case .ended: return "ended"
        case .failed(let message): return message
        }
    }

    /// Continue and the three steps, and the shortcuts bound to them.
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var canPause: Bool {
        self == .running
    }

    var canStop: Bool {
        switch self {
        case .starting, .paused, .running: return true
        case .none, .ended, .failed: return false
        }
    }

    /// debug R6: what the control row says while the adapter connects, from the command's own `arguments`.
    static func connecting(_ request: DebugCommand.Request, arguments: LSPAny) -> DebugState {
        guard case .hash(let object) = arguments else {
            return .starting(request == .attach ? "attaching" : "launching")
        }
        switch request {
        case .attach:
            if case .number(let port)? = object["port"] {
                var host = "localhost"
                if case .string(let name)? = object["hostName"] { host = name }
                return .starting("attaching to \(host):\(Int(port))")
            }
            if case .number(let pid)? = object["pid"] { return .starting("attaching to pid \(Int(pid))") }
            return .starting("attaching")
        case .launch:
            if case .string(let program)? = object["program"] { return .starting("launching \(program)") }
            if case .string(let main)? = object["mainClass"] { return .starting("launching \(main)") }
            return .starting("launching")
        }
    }

    /// An event of the adapter: `continued` runs again, `terminated` and `exited` end the session.
    mutating func handle(event name: String) {
        switch (name, self) {
        case ("continued", .paused): self = .running
        case ("terminated", .failed), ("exited", .failed): break
        case ("terminated", _), ("exited", _): self = .ended
        default: break
        }
    }
}

/// The four requests that run the program again (debug R7), with the shortcut each is bound to
/// while — and only while — a session is paused.
nonisolated enum DebugStep: CaseIterable, Sendable {
    case resume, stepOver, stepInto, stepOut

    /// The DAP request, which takes the stopping thread.
    var request: String {
        switch self {
        case .resume: return "continue"
        case .stepOver: return "next"
        case .stepInto: return "stepIn"
        case .stepOut: return "stepOut"
        }
    }

    var actionID: String {
        switch self {
        case .resume: return "debug.continue"
        case .stepOver: return "debug.stepOver"
        case .stepInto: return "debug.stepInto"
        case .stepOut: return "debug.stepOut"
        }
    }

    var title: String {
        switch self {
        case .resume: return "Continue"
        case .stepOver: return "Step Over"
        case .stepInto: return "Step Into"
        case .stepOut: return "Step Out"
        }
    }

    var shortcut: String {
        switch self {
        case .resume: return "ctrl+cmd+y"
        case .stepOver: return "f6"
        case .stepInto: return "f7"
        case .stepOut: return "f8"
        }
    }

    /// debug R7: bound while paused, withdrawn otherwise; calling it twice with the same answer does nothing.
    @MainActor
    static func sync(isPaused: Bool, in registry: ShortcutRegistry, perform: @escaping (DebugStep) -> Void) {
        for step in allCases {
            let isBound = registry.actions.contains { $0.id == step.actionID }
            if isPaused, !isBound {
                registry.register(
                    ShortcutAction(id: step.actionID, title: step.title, defaultShortcut: step.shortcut) {
                        perform(step)
                    })
            } else if !isPaused, isBound {
                registry.unregister(step.actionID)
            }
        }
    }
}

/// The console column (debug R6): the adapter's `output` events by category, the most recent 2 000 lines.
nonisolated struct DebugConsole: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case plain, error, secondary
    }

    struct Line: Equatable, Identifiable, Sendable {
        let id: Int
        let text: String
        let kind: Kind
    }

    /// The Search panel's cap (`ContentSearch.limit`): the oldest lines go.
    static let limit = 2000

    private(set) var lines: [Line] = []
    private var nextID = 0

    /// One event may carry several lines.
    ///
    /// `stderr` is an error, `console` is the adapter talking, `telemetry` is not for the user, the
    /// rest (`stdout`, `important`, none) is plain.
    mutating func append(_ output: String, category: String?) {
        let kind: Kind
        switch category {
        case "telemetry": return
        case "stderr": kind = .error
        case "console": kind = .secondary
        default: kind = .plain
        }
        append(output, kind: kind)
    }

    mutating func append(_ output: String, kind: Kind) {
        // `isNewline` takes "\r\n", one Character in Swift, for one break.
        var rows = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if rows.last == "" { rows.removeLast() }
        for row in rows {
            lines.append(Line(id: nextID, text: row, kind: kind))
            nextID += 1
        }
        if lines.count > Self.limit {
            lines.removeFirst(lines.count - Self.limit)
        }
    }
}
