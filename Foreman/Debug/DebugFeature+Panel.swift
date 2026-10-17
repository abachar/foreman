import SwiftUI
import os

/// The Debug panel and the controls of a paused session (debug R6, R7, M27 27.3).
extension DebugFeature {
    // MARK: - Panel (debug R6)

    /// debug R6, layout R36: the panel exists while an adapter is declared and a command carries a
    /// `debug` object naming one.
    nonisolated static func wantsPanel(catalog: DebugCatalog, commands: [RunCommand]) -> Bool {
        commands.contains { $0.debug.map { catalog.adapters[$0.adapter] != nil } ?? false }
    }

    func updatePanel() {
        let wanted = Self.wantsPanel(catalog: catalog, commands: run.commands)
        guard wanted != isPanelRegistered else { return }
        isPanelRegistered = wanted
        guard wanted else {
            layout.unregister(panel: Self.panelID)
            return
        }
        layout.register(
            panel: PanelDescriptor(
                id: Self.panelID, title: "Debug", side: .bottom, icon: "ladybug", order: 4,
                defaultShortcut: "cmd+shift+y",
                makeView: { [weak self, theme, panels = layout.panels] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(DebugPanelView(debug: self, model: model, panels: panels, theme: theme))
                }))
    }

    func updateStepShortcuts() {
        DebugStep.sync(isPaused: model.state.isPaused, in: layout.shortcuts) { [weak self] in self?.resume($0) }
    }

    // MARK: - Controls (debug R6, R7)

    /// `continue`, `next`, `stepIn` or `stepOut` of the stopping thread; the next `stopped` refreshes the panel.
    func resume(_ step: DebugStep) {
        guard let session, model.state.isPaused, let thread = model.stoppedThread else { return }
        mark.clear()
        model.resumed()
        refreshTabs()
        Task { [model, logger] in
            do {
                try await session.send(step.request, DAPThreadArguments(threadId: thread))
            } catch {
                logger.error("\(step.request, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                model.report(DebugPanelModel.describe(error))
            }
        }
    }

    /// `pause`: the thread of the last stop, else the first the adapter lists.
    func pause() {
        guard let session, model.state.canPause else { return }
        Task { [model, logger] in
            do {
                let thread: Int
                if let known = model.stoppedThread {
                    thread = known
                } else {
                    let list = try await session.send("threads", DAPEmpty(), as: DAPThreadsResponse.self)
                    guard let first = list.threads.first else { return }
                    thread = first.id
                }
                try await session.send("pause", DAPThreadArguments(threadId: thread))
            } catch {
                logger.error("pause failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// debug R5, R6: a frame selected in the panel is opened and marked like the top one.
    func select(_ frame: DebugFrame) {
        guard frame.isSelectable, session != nil else { return }
        model.select(frame: frame.id)
        Task { [model] in await model.loadScopes(of: frame.id) }
        Task { await show(frame.frame) }
    }
}
