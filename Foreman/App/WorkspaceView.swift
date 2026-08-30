import AppKit
import Foundation
import SwiftUI

/// Root view of a workspace window: one window, one folder (product R1).
///
/// M0 has nothing to show yet — zones, panels and tabs arrive with the layout tasks — so the window
/// displays the folder it is rooted at, or a clear error when that folder disappeared between two
/// openings; the persisted state of that workspace is left untouched (product, edge cases).
struct WorkspaceView: View {
    let folder: URL
    let appDelegate: ForemanAppDelegate

    @Environment(\.openWindow) private var openWindow
    @State private var isFolderReachable = true
    @State private var workspace: Workspace
    @State private var layout = LayoutManager()
    @State private var theme: ThemeService
    @State private var palette: Palette
    @State private var highlighter: Highlighter
    @State private var editor: EditorFeature?
    @State private var terminal: TerminalService?
    @State private var agents: AgentsFeature?
    @State private var browser: BrowserFeature?
    @State private var run: RunFeature?
    @State private var git: GitFeature?
    @State private var postgres: PostgresFeature?
    @State private var isStateLoaded = false
    @State private var hostWindow: NSWindow?

    init(folder: URL, appDelegate: ForemanAppDelegate) {
        self.folder = folder
        self.appDelegate = appDelegate
        _workspace = State(initialValue: Workspace(root: folder))
        let theme = ThemeService()
        _theme = State(initialValue: theme)
        _palette = State(initialValue: Palette(theme: theme))
        // architecture: shared services created once here; the editor and git both highlight.
        _highlighter = State(initialValue: Highlighter(theme: theme))
    }

    var body: some View {
        content
            .frame(
                minWidth: ZoneSizing.minimumWindow.width, maxWidth: .infinity,
                minHeight: ZoneSizing.minimumWindow.height, maxHeight: .infinity
            )
            .task(id: folder) {
                isFolderReachable = await Self.isDirectory(folder)
                await workspace.reloadConfig()
                await workspace.loadState()
                let editor = EditorFeature(
                    layout: layout, workspace: workspace, theme: theme, palette: palette, highlighter: highlighter)
                self.editor = editor
                let explorer = ExplorerFeature.register(in: layout, workspace: workspace, editor: editor, theme: theme)
                // architecture: the Keychain store is created once here and injected (postgres R3).
                // design R15: the toolbar's toggles follow the panels' registration order — Database
                // before Git and History.
                postgres = PostgresFeature(
                    layout: layout, workspace: workspace, secrets: KeychainSecretStore(), theme: theme,
                    highlighter: highlighter)
                let git = GitFeature(
                    layout: layout, workspace: workspace, editor: editor, explorer: explorer, theme: theme,
                    highlighter: highlighter)
                self.git = git
                // architecture: no EventBus; the explorer and the editor subscribe to Git's stream.
                explorer.model.watchGit(git.statusChanges())
                editor.watchGit(git.statusChanges())
                let terminal = TerminalService(layout: layout, theme: theme, root: workspace.root)
                self.terminal = terminal
                let agents = AgentsFeature(layout: layout, workspace: workspace, terminal: terminal, git: git)
                self.agents = agents
                // agents R10d: three direct calls, no provider protocol.
                editor.sendToAgent = { [weak agents] in agents?.send($0) }
                explorer.actions.sendToAgent = { [weak agents] in agents?.send($0) }
                git.sendToAgent = { [weak agents] in agents?.send($0) }
                browser = BrowserFeature(layout: layout, workspace: workspace, theme: theme, agents: agents)
                run = RunFeature(layout: layout, workspace: workspace, terminal: terminal, palette: palette)
                restoreLayout()
                workspace.watchConfig()
                applyShortcutOverrides(workspace.config)
                theme.apply(workspace.config)
                for await config in workspace.configChanges() {
                    applyShortcutOverrides(config)
                    theme.apply(config)
                }
            }
            .onDisappear {
                // config R8: whatever is still pending is written when the window closes.
                Task { await workspace.flushState() }
            }
            .onAppear {
                appDelegate.adopt(openWindow)
            }
            .onChange(of: appDelegate.supersededLaunchFolder, initial: true) { _, _ in
                closeIfSuperseded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isFolderReachable {
            let tokens = theme.tokens
            VStack(spacing: 0) {
                // config R7: the last valid config stays active, the error is shown with its line;
                // config R4: one per file, so a broken global never hides the workspace's.
                ForEach(workspace.configErrors, id: \.description) { error in
                    BannerView(text: error.description, icon: "exclamationmark.triangle", tone: .error, theme: theme)
                }
                ForEach(layout.shortcuts.problems, id: \.description) { problem in
                    BannerView(text: problem.description, icon: "keyboard", tone: .error, theme: theme)
                }
                if isStateLoaded {
                    ZonesView(layout: layout, theme: theme) {
                        // layout R29: restored panels start their work after the first frame.
                        layout.panels.activateVisible()
                        // architecture, Performance: workspace opened < 500 ms to the first frame (M6 6.5).
                        appDelegate.firstFrame(of: folder)
                    } onWindow: { window in
                        hostWindow = window
                        // layout R37: the bar follows the key window, the actions being per window.
                        appDelegate.menuBar.use(layout.shortcuts, for: window)
                        closeIfSuperseded()
                    }
                    // layout R27, config R8: every change of the layout is persisted, debounced.
                    .onChange(of: layout.snapshot()) { _, snapshot in
                        workspace.setState("layout", to: snapshot)
                    }
                    // design R2, R21: the gutter on three edges, the toolbar gap on top.
                    .padding(
                        EdgeInsets(
                            top: tokens.toolbarGap, leading: tokens.gutter, bottom: tokens.gutter,
                            trailing: tokens.gutter))
                }
            }
            .background(tokens.windowBackground.color)
            // design R10: the system's semantic colors (alerts, menus, `.secondary`) agree with the set.
            .preferredColorScheme(theme.isDark(systemIsDark: theme.systemIsDark) ? .dark : .light)
        } else {
            ContentUnavailableView(
                "Folder Not Found",
                systemImage: "questionmark.folder",
                description: Text(folder.path(percentEncoded: false))
            )
        }
    }

    /// product R1, edge cases: the `$HOME` window created at launch was replaced by the folder the
    /// app was opened for; it closes without persisting anything.
    private func closeIfSuperseded() {
        guard appDelegate.supersededLaunchFolder == folder else { return }
        workspace.disablePersistence()
        hostWindow?.close()
    }

    /// layout R29: the layout comes back before the zones are built, so the first frame is final.
    private func restoreLayout() {
        guard !isStateLoaded else { return }
        do {
            if let state = try workspace.state.section("layout", as: LayoutState.self) {
                layout.restore(state)
            }
        } catch {
            // config R9: an unreadable section is ignored, the layout starts from the default.
        }
        isStateLoaded = true
    }

    /// config R4, layout R26: the user's `shortcuts` section, at startup and on every reload.
    private func applyShortcutOverrides(_ config: WorkspaceConfig) {
        do {
            layout.shortcuts.apply(overrides: try config.section("shortcuts", as: [String: String].self) ?? [:])
        } catch {
            layout.shortcuts.apply(overrides: [:])
        }
    }

    /// Reading the folder is disk IO, so it runs off the main actor (coding rules, concurrency).
    private static func isDirectory(_ folder: URL) async -> Bool {
        let check = Task.detached {
            (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        return await check.value
    }
}
