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
    let appDelegate: WraithAppDelegate

    @Environment(\.openWindow) private var openWindow
    @State private var isFolderReachable = true
    @State private var workspace: Workspace
    @State private var layout = LayoutManager()
    @State private var theme = ThemeService()
    @State private var palette = Palette()
    @State private var editor: EditorFeature?
    @State private var terminal: TerminalService?
    @State private var agents: AgentsFeature?
    @State private var isStateLoaded = false
    @State private var hostWindow: NSWindow?

    init(folder: URL, appDelegate: WraithAppDelegate) {
        self.folder = folder
        self.appDelegate = appDelegate
        _workspace = State(initialValue: Workspace(root: folder))
    }

    var body: some View {
        content
            .frame(
                minWidth: ZoneSizing.minimumWindow.width, maxWidth: .infinity,
                minHeight: ZoneSizing.minimumWindow.height, maxHeight: .infinity
            )
            .navigationTitle(folder.lastPathComponent)
            .task(id: folder) {
                isFolderReachable = await Self.isDirectory(folder)
                await workspace.reloadConfig()
                await workspace.loadState()
                let editor = EditorFeature(layout: layout, workspace: workspace, theme: theme, palette: palette)
                self.editor = editor
                ExplorerFeature.register(in: layout, workspace: workspace, editor: editor)
                let terminal = TerminalService(layout: layout, theme: theme, root: workspace.root)
                self.terminal = terminal
                agents = AgentsFeature(layout: layout, workspace: workspace, terminal: terminal)
                restoreLayout()
                workspace.watchConfig()
                applyShortcutOverrides(workspace.config)
                theme.apply(workspace.config)
                for await config in workspace.configChanges {
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
                layout.openFolder = { appDelegate.openFolderFromPanel() }
            }
            .onChange(of: appDelegate.supersededLaunchFolder, initial: true) { _, _ in
                closeIfSuperseded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isFolderReachable {
            VStack(spacing: 0) {
                // config R7: the last valid config stays active, the error is shown with its line.
                if let error = workspace.configError {
                    Label(error.description, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                ForEach(layout.shortcuts.problems, id: \.description) { problem in
                    Label(problem.description, systemImage: "keyboard")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                if isStateLoaded {
                    ZonesView(layout: layout) {
                        // layout R29: restored panels start their work after the first frame.
                        layout.panels.activateVisible()
                    } onWindow: { window in
                        hostWindow = window
                        closeIfSuperseded()
                    }
                    // layout R27, config R8: every change of the layout is persisted, debounced.
                    .onChange(of: layout.snapshot()) { _, snapshot in
                        workspace.setState("layout", to: snapshot)
                    }
                }
            }
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
