import SwiftUI

/// The left panel `explorer.tree`: a header with the panel menu, the error banner, the tree.
struct ExplorerPanelView: View {
    let model: ExplorerModel
    let layout: LayoutManager
    let theme: ThemeService
    let onStateChange: (ExplorerState) -> Void
    let onOpen: (FileNode, ExplorerOpenMode) -> Void
    let pathOfTab: (TabID) -> String?
    let operations: ExplorerActions

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.error {
                // explorer R19: an IO error is shown here and leaves the tree untouched.
                BannerView(text: error.description, icon: "exclamationmark.triangle", tone: .error, theme: theme)
            }
            ExplorerOutlineView(
                model: model, theme: theme, font: theme.interfaceFont(),
                isFocused: layout.panels.focus == .panel(ExplorerFeature.panelID),
                onOpen: onOpen,
                operations: operations)
        }
        .onChange(of: model.persisted) { _, state in
            onStateChange(state)
        }
        // explorer R14: the tree follows the active tab when it shows a file under the root.
        .onChange(of: layout.model.active.active?.id) { _, id in
            guard model.followsActiveTab, let id, let path = pathOfTab(id) else { return }
            model.revealRequest = path
        }
    }

    private var header: some View {
        PanelHeaderView(panels: layout.panels, current: ExplorerFeature.panelID, theme: theme) {
            // explorer R16 (amended 2026-10-17, M22 22.7): New File and New Folder join the panel
            // menu, so three tabs and the menu fit a narrow left slot.
            Menu {
                Button("New File…") { operations.newFile(near: nil) }
                Button("New Folder…") { operations.newFolder(near: nil) }
                Divider()
                // explorer R5: persisted, default visible.
                Toggle("Hide Ignored Files", isOn: Bindable(model).hidesExcluded)
                Toggle("Follow Active Tab", isOn: Bindable(model).followsActiveTab)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
