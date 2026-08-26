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
                workspace.watchConfig()
                applyShortcutOverrides(workspace.config)
                for await config in workspace.configChanges {
                    applyShortcutOverrides(config)
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
                ZonesView(layout: layout) {
                    // layout R29: restored panels start their work after the first frame.
                    layout.panels.activateVisible()
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
