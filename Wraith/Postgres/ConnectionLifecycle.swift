import Foundation

/// postgres R4: when the window's single connection is kept and when it is closed.
///
/// A pure function so the rule is testable without a server: opening is never decided here,
/// the connection is lazy and opens on the first action that needs it.
nonisolated enum ConnectionLifecycle {
    enum Action: Equatable, Sendable {
        case keep
        case close
    }

    static let idleLimit: Duration = .seconds(600)

    /// `close` when no panel of the feature is visible any more, or when nothing ran for
    /// `idleLimit`; a running execution always keeps the connection.
    static func action(
        visiblePanels: Int, isBusy: Bool, idle: Duration, idleLimit: Duration = idleLimit
    ) -> Action {
        if isBusy {
            return .keep
        }
        if visiblePanels <= 0 || idle >= idleLimit {
            return .close
        }
        return .keep
    }
}
