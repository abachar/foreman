import Foundation
import PostgresNIO

/// The feature's error, one per feature (coding rules).
///
/// It wraps PostgresNIO's where it has nothing to add and never carries a password.
nonisolated enum PostgresError: Error, CustomStringConvertible {
    /// R2: no usable `postgres` section.
    case notConfigured(String)
    /// R3: the input sheet was cancelled.
    case passwordRequired
    /// R3: the server refused the credentials (`28P01`, `28000`).
    case authenticationFailed(String)
    /// R19: a server error with its `SQLSTATE` and, for a syntax error, the 1-based position.
    case server(message: String, sqlState: String?, position: Int?)
    /// R7: a Foreman-generated query exceeded its bound.
    case timeout(Duration)
    /// R13: the task was cancelled.
    case cancelled
    case underlying(Error)

    /// Turns any error thrown by PostgresNIO into the feature's own.
    static func classify(_ error: Error) -> PostgresError {
        if let own = error as? PostgresError {
            return own
        }
        if error is CancellationError {
            return .cancelled
        }
        guard let psql = error as? PSQLError else { return .underlying(error) }
        if psql.code == .queryCancelled {
            return .cancelled
        }
        if let info = psql.serverInfo {
            let state = info[.sqlState]
            let message = info[.message] ?? "server error"
            if state == "28P01" || state == "28000" {
                return .authenticationFailed(message)
            }
            return .server(message: message, sqlState: state, position: info[.position].flatMap(Int.init))
        }
        if psql.code == .authMechanismRequiresPassword {
            return .authenticationFailed("The server requires a password.")
        }
        return .underlying(psql)
    }

    var description: String {
        switch self {
        case .notConfigured(let message):
            return message
        case .passwordRequired:
            return "A password is required to connect."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .server(let message, let sqlState, _):
            return sqlState.map { "\(message) (\($0))" } ?? message
        case .timeout(let limit):
            return "No answer from the server within \(limit.components.seconds) s."
        case .cancelled:
            return "Cancelled."
        case .underlying(let error):
            if let psql = error as? PSQLError {
                // PSQLError's own description is deliberately opaque; its code is not.
                return "PostgresNIO: \(psql.code)"
            }
            return error.localizedDescription
        }
    }
}
