import AppKit
import Foundation
import Observation
import os

/// When an action is available (layout R22b).
nonisolated enum ShortcutScope: Hashable, Sendable {
    case global
    /// Only while a tab of this kind is active in the active group.
    case tab(kind: String)
    /// Only while a panel has the keyboard focus (layout R23: `escape` from a panel only).
    case panel
}

/// An action a feature or the layout binds to a shortcut (layout R22).
struct ShortcutAction {
    let id: String
    let title: String
    let scope: ShortcutScope
    let defaultShortcut: String?
    /// layout R24: a layout action's shortcut cannot be taken by a feature, only by the user.
    let isLayout: Bool
    let perform: () -> Void

    init(
        id: String,
        title: String,
        scope: ShortcutScope = .global,
        defaultShortcut: String?,
        isLayout: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.defaultShortcut = defaultShortcut
        self.isLayout = isLayout
        self.perform = perform
    }
}

/// What prevented a binding (layout R24, config R4); shown at startup and on every reload.
nonisolated enum ShortcutProblem: Equatable, Sendable, CustomStringConvertible {
    /// Two actions of overlapping scopes on one shortcut: none is bound.
    case conflict(Shortcut, ids: [String])
    /// A feature declared a layout shortcut as its default: the feature action is not bound.
    case reservedByLayout(Shortcut, id: String)
    /// `config.shortcuts` names an action that does not exist, or a shortcut that does not parse.
    case invalidOverride(id: String, text: String)

    var description: String {
        switch self {
        case .conflict(let shortcut, let ids):
            return "\(shortcut) is bound to \(ids.joined(separator: " and ")): neither is active."
        case .reservedByLayout(let shortcut, let id):
            return "\(shortcut) belongs to the layout: \(id) is not bound."
        case .invalidOverride(let id, let text):
            return "shortcuts.\(id) = \"\(text)\" is not a valid shortcut."
        }
    }
}

/// The single table `shortcut → action` of a window (layout R22–R26).
///
/// Rebuilt from scratch on every change: defaults of the layout, defaults of the features, then
/// the user's `config.shortcuts`; conflicts are reported, never resolved silently (R24).
@Observable
@MainActor
final class ShortcutRegistry {
    private(set) var actions: [ShortcutAction] = []
    private(set) var problems: [ShortcutProblem] = []
    private var bindings: [ShortcutScope: [Shortcut: String]] = [:]
    private var overrides: [String: String] = [:]
    private var monitor: Any?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "layout")

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func register(_ action: ShortcutAction) {
        guard !actions.contains(where: { $0.id == action.id }) else {
            logger.fault("action \(action.id, privacy: .public) registered twice, second refused")
            return
        }
        actions.append(action)
        rebuild()
    }

    /// config R4, layout R26: the user's `shortcuts` section, applied on every config change.
    func apply(overrides: [String: String]) {
        self.overrides = overrides
        rebuild()
    }

    /// The shortcut currently bound to `id`, for display (home screen, menus).
    func shortcut(for id: String) -> Shortcut? {
        for table in bindings.values {
            if let match = table.first(where: { $0.value == id }) {
                return match.key
            }
        }
        return nil
    }

    /// layout R22b, R25: the action for `shortcut` in the current context, if any.
    func resolve(
        _ shortcut: Shortcut, activeTabKind: String?, isTerminalFocused: Bool, isPanelFocused: Bool = false
    ) -> ShortcutAction? {
        if isTerminalFocused, !shortcut.requiresCommand {
            return nil
        }
        if isPanelFocused, let id = bindings[.panel]?[shortcut] {
            return actions.first { $0.id == id }
        }
        if let kind = activeTabKind, let id = bindings[.tab(kind: kind)]?[shortcut] {
            return actions.first { $0.id == id }
        }
        guard let id = bindings[.global]?[shortcut] else { return nil }
        return actions.first { $0.id == id }
    }

    /// layout, options: one local monitor per window, ahead of SwiftUI; `context` says what has
    /// the focus at the time of the event.
    func startMonitoring(
        window: NSWindow,
        context: @escaping () -> (activeTabKind: String?, isTerminalFocused: Bool, isPanelFocused: Bool)
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, event.window === window, let shortcut = Shortcut(event: event) else { return event }
            let focus = context()
            guard
                let action = resolve(
                    shortcut, activeTabKind: focus.activeTabKind, isTerminalFocused: focus.isTerminalFocused,
                    isPanelFocused: focus.isPanelFocused)
            else { return event }
            action.perform()
            return nil
        }
    }

    // MARK: - Table

    private func rebuild() {
        var problems: [ShortcutProblem] = []
        var requested: [(action: ShortcutAction, shortcut: Shortcut)] = []
        let layoutShortcuts = Set(
            actions.filter(\.isLayout).compactMap { $0.defaultShortcut.flatMap(Shortcut.init(parsing:)) })

        for action in actions {
            guard let text = action.defaultShortcut, let shortcut = Shortcut(parsing: text) else { continue }
            if !action.isLayout, layoutShortcuts.contains(shortcut) {
                problems.append(.reservedByLayout(shortcut, id: action.id))
                continue
            }
            requested.append((action, shortcut))
        }
        for (id, text) in overrides.sorted(by: { $0.key < $1.key }) {
            guard let action = actions.first(where: { $0.id == id }), let shortcut = Shortcut(parsing: text) else {
                problems.append(.invalidOverride(id: id, text: text))
                continue
            }
            requested.removeAll { $0.action.id == id }
            problems.removeAll { $0 == .reservedByLayout(shortcut, id: id) }
            requested.append((action, shortcut))
        }

        // layout R24: after overrides, a shortcut shared by two actions of overlapping scopes binds neither.
        var table: [ShortcutScope: [Shortcut: String]] = [:]
        for (action, shortcut) in requested {
            let sharing = requested.filter { $0.shortcut == shortcut && Self.overlap($0.action.scope, action.scope) }
            if sharing.count > 1 {
                let ids = sharing.map(\.action.id).sorted()
                if !problems.contains(.conflict(shortcut, ids: ids)) {
                    problems.append(.conflict(shortcut, ids: ids))
                }
                continue
            }
            table[action.scope, default: [:]][shortcut] = action.id
        }
        bindings = table
        self.problems = problems
        for problem in problems {
            logger.error("\(problem.description, privacy: .public)")
        }
    }

    /// layout R22b: a `tab(kind)` action masks a global one, so only equal scopes conflict.
    private static func overlap(_ first: ShortcutScope, _ second: ShortcutScope) -> Bool {
        first == second
    }
}
