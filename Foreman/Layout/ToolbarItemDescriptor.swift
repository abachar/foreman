import AppKit
import Foundation
import SwiftUI

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
        /// layout R30 (amended 2026-10-16): a widget drawn by its feature in SwiftUI — the project,
        /// the branch, Run. `view` gets the closure that opens `menu` under the widget; `menu` is
        /// asked for at that moment.
        case widget(view: (_ openMenu: @escaping () -> Void) -> AnyView, menu: () -> ToolbarMenu)
    }

    let id: String
    let title: String
    /// See `IconImage`.
    let icon: String
    let placement: Placement
    let kind: Kind
    /// layout R30 (amended 2026-10-16): the agents and the browser are icons alone, their name in
    /// the tooltip (reference views 01–13).
    var showsTitle = true
}

/// What a widget's menu holds (layout R30, git branch menu).
struct ToolbarMenu {
    var entries: [ToolbarMenuEntry]
    /// A filter field on top, with this placeholder, that hides the entries not containing its
    /// text (`ToolbarMenuFilter`); `nil` for none.
    var filter: String?
}

/// One line of a toolbar menu (layout R30).
struct ToolbarMenuEntry: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var badge: ToolbarBadge = .none
    /// layout R37: written next to the entry; shown, never bound.
    var shortcut: Shortcut?
    /// A submenu (`Open Recent ▸`, a worktree's actions); `perform` is not called for it.
    var children: [ToolbarMenuEntry] = []
    var isEnabled = true
    /// A check mark before the title (the current branch).
    var isChecked = false
    /// A heading line, greyed and inert (`Worktrees`, `Local`).
    var isHeader = false
    /// The entry is preceded by a separator.
    var startsSection = false
    let perform: () -> Void
}

/// layout R31: a mark on an item, updated by its owner (agent running, run failed).
nonisolated enum ToolbarBadge: Equatable, Sendable {
    case none
    case dot(BadgeColor)
    /// agents R6: a dot carrying a number (two agents running or more).
    case count(Int, BadgeColor)
    /// run R10 (amended 2026-10-17): a symbol in a state colour (✓, ✗), on a panel tab only.
    case symbol(String, BadgeColor)

    nonisolated enum BadgeColor: Sendable {
        case green
        case orange
        case red
        case blue
    }
}
