import Foundation
import SwiftUI
import WebKit
import os

/// Entry point of `browser`: one `browser.page` tab per window on `config.browser.url`, a button
/// next to the agents while the section says so (browser R1–R3, R6).
@MainActor
final class BrowserFeature {
    static let tabKind = "browser.page"
    static let toolbarID = "browser.open"

    private let layout: LayoutManager
    private let workspace: Workspace
    private let theme: ThemeService
    private let agents: AgentsFeature
    /// browser R6: the private session of this window.
    private let store = WKWebsiteDataStore.nonPersistent()
    private var url: URL?
    private var tabID: TabID?
    private var tab: BrowserTab?
    private var isShown = false
    private var configWatch: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "browser")

    init(layout: LayoutManager, workspace: Workspace, theme: ThemeService, agents: AgentsFeature) {
        self.layout = layout
        self.workspace = workspace
        self.theme = theme
        self.agents = agents
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.tabKind,
                makeView: { [weak self] id, _ in self?.view(id) },
                serialize: { _ in "{}" },
                onClose: { [weak self] id in self?.closed(id) }))
        registerShortcuts()
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges() {
                guard let self else { return }
                apply(config)
            }
        }
    }

    isolated deinit {
        configWatch?.cancel()
    }

    // MARK: - Config (browser R2)

    private func apply(_ config: WorkspaceConfig) {
        let parsed: (url: URL?, warning: String?)
        do {
            parsed = BrowserConfig.parse(try config.section("browser", as: BrowserConfig.self))
        } catch {
            parsed = (nil, "browser section ignored: \(error.localizedDescription)")
        }
        if let warning = parsed.warning {
            logger.warning("\(warning, privacy: .public)")
        }
        url = parsed.url
        if let url, let tab, tab.url != url {
            tab.load(url)
        }
        show(url != nil)
    }

    /// browser R1, R2: the button and the home entry exist only with a URL.
    private func show(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            layout.register(
                toolbarItem: ToolbarItemDescriptor(
                    id: Self.toolbarID, title: "Browser", icon: "globe", placement: .center,
                    kind: .action(
                        perform: { [weak self] in self?.open() },
                        secondaryMenu: { [weak self] in self?.menu() ?? [] })))
            layout.replaceHomeEntries(
                in: .browser,
                with: [
                    HomeEntry(id: Self.toolbarID, title: "Browser", icon: "globe", section: .browser) { [weak self] in
                        self?.open()
                    }
                ])
        } else {
            layout.removeToolbarItem(Self.toolbarID)
            layout.replaceHomeEntries(in: .browser, with: [])
        }
    }

    private func menu() -> [ToolbarMenuEntry] {
        [
            ToolbarMenuEntry(id: "browser.clear", title: "Clear Website Data") { [weak self] in
                Task { await self?.tab?.clearWebsiteData() }
            }
        ]
    }

    // MARK: - The tab (browser R1, R3)

    /// browser R1: the window's tab activated, or opened in the active group.
    func open() {
        guard let url else { return }
        if let tabID, let owner = layout.model.owner(of: tabID) {
            layout.activate(tabID, in: owner)
            return
        }
        tab = BrowserTab(url: url, store: store)
        tabID = layout.openTab(kind: Self.tabKind, title: url.host() ?? "Browser", payload: "{}")
        watchTitle()
    }

    /// browser R1, R3: restored on the config URL; a second tab, or no URL, is not restored.
    private func view(_ id: TabID) -> AnyView? {
        if let tab, tabID == id {
            return AnyView(BrowserTabView(tab: tab, theme: theme))
        }
        guard tabID == nil || layout.model.owner(of: tabID ?? id) == nil, let url else { return nil }
        let tab = BrowserTab(url: url, store: store)
        self.tab = tab
        tabID = id
        watchTitle()
        return AnyView(BrowserTabView(tab: tab, theme: theme))
    }

    /// browser R1: the tab's title follows the page.
    private func watchTitle() {
        guard let tab, let tabID else { return }
        withObservationTracking {
            _ = tab.title
            _ = tab.url
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let tab = self.tab, self.tabID == tabID else { return }
                layout.update(tabID, title: BrowserTab.displayTitle(tab.title, url: tab.url), isDirty: false)
                watchTitle()
            }
        }
    }

    private func closed(_ id: TabID) {
        guard id == tabID else { return }
        tab?.close()
        tab = nil
        tabID = nil
    }

    // MARK: - Shortcuts (browser R9)

    private func registerShortcuts() {
        layout.shortcuts.register(
            ShortcutAction(id: Self.toolbarID, title: "Browser", defaultShortcut: "cmd+shift+o") { [weak self] in
                self?.open()
            })
        let actions: [(String, String, String, () -> Void)] = [
            ("browser.reload", "Reload Page", "cmd+shift+r", { [weak self] in self?.tab?.reloadOrStop() }),
            ("browser.back", "Back", "cmd+[", { [weak self] in self?.tab?.goBack() }),
            ("browser.forward", "Forward", "cmd+]", { [weak self] in self?.tab?.goForward() }),
            (
                "browser.sendToAgent", "Send to Agent", "cmd+e",
                { [weak self] in
                    guard let self, let tab else { return }
                    agents.send(.url(tab.url))
                }
            ),
        ]
        for (id, title, shortcut, perform) in actions {
            layout.shortcuts.register(
                ShortcutAction(
                    id: id, title: title, scope: .tab(kind: Self.tabKind), defaultShortcut: shortcut, perform: perform))
        }
    }
}
