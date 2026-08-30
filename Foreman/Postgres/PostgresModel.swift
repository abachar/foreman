import Foundation
import Observation

/// What the postgres panels read (postgres R2, R5, R11): the connection's state, the header's
/// label, the banner and the *Allow writes* toggle.
@Observable
@MainActor
final class PostgresModel {
    /// R2: `user@host/database`, `nil` when nothing is configured.
    private(set) var label: String?
    /// R2: why there is no connection to show, with the config example.
    private(set) var configMessage: String?
    /// Config warnings (R1) and `.pgpass` refusals (R3), shown once in the banner.
    private(set) var warnings: [String] = []
    private(set) var state = PostgresClient.State.disconnected
    /// R5: the last error, cleared by the next successful action.
    var error: String?
    /// R11: per session, never persisted.
    private(set) var allowWrites = false

    /// R1, R2 — what the section now says, the header's label or the reason there is none, and
    /// the config warnings.
    ///
    /// The live session is left exactly as it is.
    func setConfig(_ outcome: PostgresConfig.Outcome) {
        switch outcome {
        case .configured(let config, let warnings):
            label = config.label
            configMessage = nil
            self.warnings = warnings
        case .missing(let message):
            label = nil
            configMessage = message
            warnings = []
        }
    }

    /// R2, R11: the connection itself is being replaced, so the session starts over —
    /// disconnected, no error, read-only again.
    func apply(_ outcome: PostgresConfig.Outcome) {
        setConfig(outcome)
        state = .disconnected
        error = nil
        allowWrites = false
    }

    func setState(_ state: PostgresClient.State) {
        self.state = state
        if case .error(let message) = state {
            error = message
        }
    }

    func setAllowWrites(_ allowed: Bool) {
        allowWrites = allowed
    }

    func addWarning(_ warning: String) {
        guard !warnings.contains(warning) else { return }
        warnings.append(warning)
    }
}
