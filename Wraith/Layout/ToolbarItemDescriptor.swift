import AppKit
import Foundation

/// An element of the window toolbar, declared by a feature (layout R30, R31).
struct ToolbarItemDescriptor {
    /// layout R30 (amended 2026-08-27, design R15): the Explorer toggle leads, the agents are
    /// centred, Run and the right panels' toggles trail.
    nonisolated enum Placement: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    enum Kind {
        /// Click runs `perform`; right click opens `secondaryMenu` when there is one.
        case action(perform: () -> Void, secondaryMenu: (() -> [ToolbarMenuEntry])?)
        /// Click opens the entries, asked for at that moment.
        case menu(entries: () -> [ToolbarMenuEntry])
    }

    let id: String
    let title: String
    /// See `IconImage`.
    let icon: String
    let placement: Placement
    let kind: Kind
}

/// One line of a toolbar menu (layout R30).
struct ToolbarMenuEntry: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var badge: ToolbarBadge = .none
    let perform: () -> Void
}

/// layout R31: a mark on an item, updated by its owner (agent running, run failed).
nonisolated enum ToolbarBadge: Equatable, Sendable {
    case none
    case dot(BadgeColor)

    nonisolated enum BadgeColor: Sendable {
        case green
        case orange
        case red
        case blue
    }
}
