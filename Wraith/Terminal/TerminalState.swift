import Foundation

/// How a process ended (terminal R6, R8): its exit code, or the signal that killed it.
nonisolated enum TerminalExit: Equatable, Sendable {
    case code(Int32)
    case signal(Int32)

    /// Decodes the `wait(2)` status SwiftTerm hands over; `nil` (IO failure) counts as a kill.
    init(waitStatus: Int32?) {
        guard let status = waitStatus else {
            self = .signal(SIGKILL)
            return
        }
        let signal = status & 0x7f
        if signal == 0 {
            self = .code((status >> 8) & 0xff)
        } else {
            self = .signal(signal)
        }
    }

    /// terminal R8: `code 0`, `signal SIGINT`.
    var label: String {
        switch self {
        case .code(let code):
            return "code \(code)"
        case .signal(let signal):
            return "signal \(Self.name(of: signal))"
        }
    }

    private static func name(of signal: Int32) -> String {
        switch signal {
        case SIGHUP: return "SIGHUP"
        case SIGINT: return "SIGINT"
        case SIGKILL: return "SIGKILL"
        case SIGTERM: return "SIGTERM"
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        default: return "\(signal)"
        }
    }
}

/// terminal R6: the life of a surface, the only source of state for agents R6 and run R10.
nonisolated enum TerminalState: Equatable, Sendable {
    case idle
    case running(pid: pid_t)
    case exited(TerminalExit)
}

/// terminal R16: what `TerminalService` publishes.
nonisolated enum TerminalEvent: Equatable, Sendable {
    case started(TabID, pid: pid_t)
    case exited(TabID, TerminalExit)
    case bell(TabID)
    /// terminal R7: the tab was shown, its mark is cleared.
    case activated(TabID)
    case closed(TabID)
}

nonisolated enum TerminalError: Error, Equatable, Sendable {
    /// terminal R17
    case noSuchTab
    /// Edge cases: the persisted folder is gone; `Relaunch` stays disabled.
    case cwdMissing
}
