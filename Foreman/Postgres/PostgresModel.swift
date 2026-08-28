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

    func apply(_ outcome: PostgresConfig.Outcome) {
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
