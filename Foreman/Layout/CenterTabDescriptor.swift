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
    /// Called once the tab left the layout (`cmd+w`, group, window): the owner releases what it
    /// holds — a terminal stops its process (terminal R11).
    let onClose: (TabID) -> Void
    /// layout R25: a terminal surface takes every key that is not a `cmd+…` shortcut.
    let isTerminal: Bool
    /// design R23: the tab's title is a file name, shown with its type icon.
    let showsFileIcon: Bool

    init(
        kind: String,
        isTerminal: Bool = false,
        showsFileIcon: Bool = false,
        makeView: @escaping (TabID, String) -> AnyView?,
        serialize: @escaping (TabID) -> String?,
        confirmClose: @escaping (TabID) async -> Bool = { _ in true },
        onClose: @escaping (TabID) -> Void = { _ in }
    ) {
        self.kind = kind
        self.isTerminal = isTerminal
        self.showsFileIcon = showsFileIcon
        self.makeView = makeView
        self.serialize = serialize
        self.confirmClose = confirmClose
        self.onClose = onClose
    }
}

/// An entry of the home screen (layout R33), declared by a feature.
struct HomeEntry: Identifiable {
    enum Section: CaseIterable {
        case agents
        case recent
    }

    let id: String
    let title: String
    /// See `IconImage`.
    let icon: String
    let section: Section
    let action: () -> Void
}
