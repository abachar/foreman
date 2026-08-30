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
    /// Only while the active tab is a terminal surface, whatever its kind (terminal R12).
    case terminal
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
    /// `config.shortcuts` names an action no feature registered.
    case unknownAction(id: String)
    /// `config.shortcuts` gives an action a shortcut that does not parse.
    case invalidOverride(id: String, text: String)

    var description: String {
        switch self {
        case .conflict(let shortcut, let ids):
            return "\(shortcut) is bound to \(ids.joined(separator: " and ")): neither is active."
        case .reservedByLayout(let shortcut, let id):
            return "\(shortcut) belongs to the layout: \(id) is not bound."
        case .unknownAction(let id):
            return "shortcuts.\(id) names no action."
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
    /// Removes the monitor when its window goes away; see `startMonitoring`.
    private var windowClosing: NSObjectProtocol?
    /// What has the focus, as the monitor sees it; menus validate against the same context (R37).
    private var context: (() -> (activeTabKind: String?, isTerminalFocused: Bool, isPanelFocused: Bool))?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "layout")

    isolated deinit {
        stopMonitoring()
    }

    func register(_ action: ShortcutAction) {
        guard !actions.contains(where: { $0.id == action.id }) else {
            logger.fault("action \(action.id, privacy: .public) registered twice, second refused")
            return
        }
        actions.append(action)
        rebuild()
    }

    /// layout R36: an action withdrawn with its feature's content; its shortcut is free again.
    func unregister(_ id: String) {
        actions.removeAll { $0.id == id }
        rebuild()
    }

    /// config R4, layout R26: the user's `shortcuts` section, applied on every config change.
    func apply(overrides: [String: String]) {
        self.overrides = overrides
        rebuild()
    }

    /// layout R33: the home screen's shortcut table.
    ///
    /// Every action with a shortcut, grouped by the feature its id is namespaced under
    /// (`git.changes` → `git`), features and actions in registration order. A family of actions —
    /// same parent id, same modifiers, titles sharing a leading phrase — is one row
    /// (`Tab N · cmd+N`, `Focus Group · cmd+opt+←→↑↓`).
    var documentation: [ShortcutGroup] {
        var groups: [ShortcutGroup] = []
        for action in actions {
            guard let shortcut = shortcut(for: action.id) else { continue }
            let feature = String(action.id.prefix { $0 != "." })
            let index = groups.firstIndex { $0.feature == feature } ?? groups.count
            if index == groups.count {
                groups.append(ShortcutGroup(feature: feature, rows: []))
            }
            groups[index].add(action, shortcut)
        }
        return groups
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

    /// layout R37: whether the menu offering `id` can act right now.
    ///
    /// The same answer the monitor would give to that shortcut, so a menu never offers what the
    /// keyboard would not do — and a disabled item never fires its key equivalent.
    func isAvailable(_ id: String) -> Bool {
        guard let shortcut = shortcut(for: id) else { return false }
        let focus = context?() ?? (activeTabKind: nil, isTerminalFocused: false, isPanelFocused: false)
        return resolve(
            shortcut, activeTabKind: focus.activeTabKind, isTerminalFocused: focus.isTerminalFocused,
            isPanelFocused: focus.isPanelFocused)?.id == id
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
        if isTerminalFocused, let id = bindings[.terminal]?[shortcut] {
            return actions.first { $0.id == id }
        }
        guard let id = bindings[.global]?[shortcut] else { return nil }
        return actions.first { $0.id == id }
    }

    /// layout, options: one local monitor per window, ahead of SwiftUI; `context` says what has
    /// the focus at the time of the event.
    ///
    /// The monitor is dropped when the window closes, not in `deinit`. AppKit retains the block
    /// until `removeMonitor`, and the block holds `context`, whose captures reach back to the
    /// `LayoutManager` that owns this registry: waiting for `deinit` waits for a release that the
    /// monitor is itself preventing, and the whole layout graph of a closed window stays alive
    /// (audit C2).
    func startMonitoring(
        window: NSWindow,
        context: @escaping () -> (activeTabKind: String?, isTerminalFocused: Bool, isPanelFocused: Bool)
    ) {
        guard monitor == nil else { return }
        self.context = context
        windowClosing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopMonitoring() }
        }
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

    /// Undoes `startMonitoring`, giving the event monitor back to AppKit.
    ///
    /// `context` is released with everything it captured; calling this twice is a no-op.
    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        context = nil
        if let windowClosing {
            NotificationCenter.default.removeObserver(windowClosing)
        }
        windowClosing = nil
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
            // layout R24: the two halves of the line fail apart, so the message names the right one.
            guard let action = actions.first(where: { $0.id == id }) else {
                problems.append(.unknownAction(id: id))
                continue
            }
            guard let shortcut = Shortcut(parsing: text) else {
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

/// layout R33: one feature's bound actions, for the home screen.
struct ShortcutGroup: Identifiable {
    let feature: String
    var rows: [ShortcutRow]

    var id: String { feature }

    /// Folds `action` into the row of its family when there is one, else appends a row.
    mutating func add(_ action: ShortcutAction, _ shortcut: Shortcut) {
        let parent = action.id.split(separator: ".").dropLast().joined(separator: ".")
        if let index = rows.firstIndex(where: { $0.canFold(parent: parent, title: action.title, shortcut: shortcut) }) {
            rows[index].fold(action, shortcut)
        } else {
            rows.append(ShortcutRow(action: action, shortcut: shortcut, parent: parent))
        }
    }
}

/// One line of the home screen's shortcut table: an action, or a family of them.
struct ShortcutRow: Identifiable {
    private static let arrows: [(key: String, symbol: Character)] = [
        ("left", "←"), ("right", "→"), ("up", "↑"), ("down", "↓"),
    ]

    let id: String
    private(set) var title: String
    private let parent: String
    private let modifiers: Shortcut.Modifiers
    private var keys: [String]
    private var performs: [() -> Void]

    init(action: ShortcutAction, shortcut: Shortcut, parent: String) {
        id = action.id
        title = action.title
        self.parent = parent
        modifiers = shortcut.modifiers
        keys = [shortcut.key]
        performs = [action.perform]
    }

    /// The first action of the family.
    var perform: () -> Void { performs[0] }

    /// `cmd+w`, or for a family `cmd+N` / `cmd+opt+←→↑↓` / `cmd+shift+[]`.
    var shortcut: String {
        let base = Shortcut(key: keys[0], modifiers: modifiers).description
        guard keys.count > 1 else { return base }
        let joined: String
        if keys.allSatisfy(Self.isDigit) {
            joined = "N"
        } else if keys.allSatisfy({ key in Self.arrows.contains { $0.key == key } }) {
            joined = String(Self.arrows.filter { keys.contains($0.key) }.map(\.symbol))
        } else {
            joined = keys.joined()
        }
        return String(base.dropLast(keys[0].count)) + joined
    }

    private static func isDigit(_ key: String) -> Bool {
        key.count == 1 && key.first?.isNumber == true
    }

    fileprivate func canFold(parent: String, title: String, shortcut: Shortcut) -> Bool {
        self.parent == parent && modifiers == shortcut.modifiers && !Self.commonPrefix(self.title, title).isEmpty
    }

    fileprivate mutating func fold(_ action: ShortcutAction, _ shortcut: Shortcut) {
        title = Self.commonPrefix(title, action.title)
        keys.append(shortcut.key)
        performs.append(action.perform)
        if keys.allSatisfy(Self.isDigit) {
            title += " N"
        }
    }

    /// The leading whole words two titles share (`Focus Group Left` / `Focus Group Right` →
    /// `Focus Group`); a family that already folded carries its trailing ` N` as a word to strip.
    private static func commonPrefix(_ a: String, _ b: String) -> String {
        let wordsA = a.split(separator: " ").filter { $0 != "N" }
        let wordsB = b.split(separator: " ")
        return zip(wordsA, wordsB).prefix { $0 == $1 }.map { String($0.0) }.joined(separator: " ")
    }
}
