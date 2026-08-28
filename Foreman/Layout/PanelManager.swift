import Foundation
import Observation
import SwiftUI
import os

/// The three optional slots around the center zone (layout R1).
nonisolated enum PanelSide: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case left
    case right
    case bottom
}

/// Namespaced, stable id of a panel (`git.status`, `explorer.tree`), used in shortcuts and state.
nonisolated struct PanelID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, RawRepresentable,
    CodingKeyRepresentable
{
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// `CodingKeyRepresentable` so a `[PanelID: …]` encodes as a JSON object, not a flat array (layout R18).
    init?(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a feature declares for a panel (architecture: features declare, `PanelManager` decides).
///
/// `makeView` is lazy and side-effect free; `activate` starts the panel's work, `deactivate`
/// stops it (layout R4, R5).
struct PanelDescriptor {
    let id: PanelID
    let title: String
    let side: PanelSide
    /// design R15: the toolbar toggle's icon (see `IconImage`).
    let icon: String
    let defaultShortcut: String?
    let makeView: () -> AnyView
    let activate: () -> Void
    let deactivate: () -> Void

    init(
        id: PanelID,
        title: String,
        side: PanelSide,
        icon: String = "rectangle",
        defaultShortcut: String? = nil,
        makeView: @escaping () -> AnyView,
        activate: @escaping () -> Void = {},
        deactivate: @escaping () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.side = side
        self.icon = icon
        self.defaultShortcut = defaultShortcut
        self.makeView = makeView
        self.activate = activate
        self.deactivate = deactivate
    }
}

/// Where keyboard focus goes (layout R6): the active tab group, or a panel.
enum FocusTarget: Equatable {
    case center
    case panel(PanelID)
}

/// The state machine of the panels: one visible panel per slot, at most (layout R2–R6).
@Observable
@MainActor
final class PanelManager {
    /// layout R2: the whole state, a slot without entry is empty.
    private(set) var visible: [PanelSide: PanelID] = [:]
    private(set) var focus: FocusTarget = .center
    private(set) var panels: [PanelDescriptor] = []

    private var views: [PanelID: AnyView] = [:]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "layout")

    /// layout, edge cases: a duplicated id is a programming error, refused and logged as a fault.
    @discardableResult
    func register(_ descriptor: PanelDescriptor) -> Bool {
        guard self[descriptor.id] == nil else {
            logger.fault("panel \(descriptor.id.rawValue, privacy: .public) registered twice, second refused")
            return false
        }
        panels.append(descriptor)
        return true
    }

    subscript(id: PanelID) -> PanelDescriptor? {
        panels.first { $0.id == id }
    }

    func isVisible(_ id: PanelID) -> Bool {
        visible.values.contains(id)
    }

    /// layout R3: hides the panel if it is the one shown in its slot, otherwise shows it there.
    func toggle(_ id: PanelID) {
        guard let descriptor = self[id] else { return }
        if visible[descriptor.side] == id {
            hide(descriptor.side)
        } else {
            show(id)
        }
    }

    /// Shows `id` in its slot, replacing (and deactivating) the panel shown there; focus goes to
    /// the panel (layout R3, R4, R6).
    func show(_ id: PanelID) {
        guard let descriptor = self[id], visible[descriptor.side] != id else { return }
        // architecture, Performance: panel < 100 ms (M6 6.5); ends after SwiftUI's commit.
        let interval = Perf.signposter.beginInterval("panel.show", id: Perf.signposter.makeSignpostID())
        DispatchQueue.main.async {
            Perf.signposter.endInterval("panel.show", interval)
        }
        if let replaced = visible[descriptor.side] {
            self[replaced]?.deactivate()
        }
        visible[descriptor.side] = id
        descriptor.activate()
        focus = .panel(id)
    }

    /// Hides the slot; its panel is deactivated and focus returns to the center (layout R4, R6).
    func hide(_ side: PanelSide) {
        guard let id = visible.removeValue(forKey: side) else { return }
        self[id]?.deactivate()
        if focus == .panel(id) {
            focus = .center
        }
    }

    /// `escape` from a panel (layout R6): focus back to the center, the panel stays.
    func focusCenter() {
        focus = .center
    }

    func focusPanel(_ id: PanelID) {
        guard isVisible(id) else { return }
        focus = .panel(id)
    }

    /// layout R5: built on first use, then kept for the life of the window.
    func view(for id: PanelID) -> AnyView? {
        if let view = views[id] {
            return view
        }
        guard let descriptor = self[id] else { return nil }
        let view = descriptor.makeView()
        views[id] = view
        return view
    }

    /// Restores the visible panels from `state.json` without activating them (layout R29): a panel
    /// that moved to another slot since is considered hidden (edge cases).
    func restore(visible restored: [PanelSide: PanelID]) {
        visible = restored.filter { side, id in self[id]?.side == side }
    }

    /// layout R29: after the first frame, the restored panels start their work.
    func activateVisible() {
        for id in visible.values {
            self[id]?.activate()
        }
    }
}
