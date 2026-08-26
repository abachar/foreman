import Foundation
import SwiftUI

/// What a feature declares for a kind of center tab (architecture: feature registration).
///
/// The layout never reads the payload: it is the feature's own JSON string, produced by
/// `serialize` and given back to `makeView` at restoration (layout R28).
struct CenterTabDescriptor {
    let kind: String
    /// The view of a tab, or `nil` when the payload cannot be restored (R28: the tab is ignored).
    let makeView: (TabID, String) -> AnyView?
    /// The payload to persist for a tab, `nil` for a tab that is not persisted.
    let serialize: (TabID) -> String?
    /// layout R15: the owner asks in its own words; `true` closes.
    let confirmClose: (TabID) async -> Bool

    init(
        kind: String,
        makeView: @escaping (TabID, String) -> AnyView?,
        serialize: @escaping (TabID) -> String?,
        confirmClose: @escaping (TabID) async -> Bool = { _ in true }
    ) {
        self.kind = kind
        self.makeView = makeView
        self.serialize = serialize
        self.confirmClose = confirmClose
    }
}

/// An entry of the home screen (layout R33), declared by a feature.
struct HomeEntry: Identifiable {
    enum Section: CaseIterable {
        case agents
        case actions
        case recent
    }

    let id: String
    let title: String
    let icon: String
    let section: Section
    let action: () -> Void
}
