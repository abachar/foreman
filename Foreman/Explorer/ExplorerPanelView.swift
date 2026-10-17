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
            footer
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
        PanelHeaderView(panels: layout.panels, current: ExplorerFeature.panelID, theme: theme) { EmptyView() }
    }

    /// explorer R16, R5 (amended 2026-10-17, author): the actions in a bar at the bottom of the
    /// panel, as in Xcode's navigators.
    private var footer: some View {
        let tokens = theme.tokens
        return PanelFooterView(theme: theme) {
            Button {
                operations.newFile(near: nil)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New File")
            Button {
                operations.newFolder(near: nil)
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Folder")
            // explorer R5: persisted, default visible; left-aligned with the others whatever the width.
            Toggle(isOn: Bindable(model).hidesExcluded) {
                Image(systemName: "eye.slash")
            }
            .toggleStyle(.button)
            .foregroundStyle((model.hidesExcluded ? tokens.accent : tokens.textSecondary).color)
            .help("Hide Ignored Files")
            Toggle(isOn: Bindable(model).followsActiveTab) {
                Image(systemName: "scope")
            }
            .toggleStyle(.button)
            .foregroundStyle((model.followsActiveTab ? tokens.accent : tokens.textSecondary).color)
            .help("Follow Active Tab")
        }
    }
}
