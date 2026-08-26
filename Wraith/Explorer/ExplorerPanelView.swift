import SwiftUI

/// The left panel `explorer.tree`: a header with the panel menu, the error banner, the tree.
struct ExplorerPanelView: View {
    let model: ExplorerModel
    let layout: LayoutManager
    let onStateChange: (ExplorerState) -> Void
    let onOpen: (FileNode, ExplorerOpenMode) -> Void
    let pathOfTab: (TabID) -> String?
    let operations: ExplorerActions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.error {
                // explorer R19: an IO error is shown here and leaves the tree untouched.
                Label(error.description, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            ExplorerOutlineView(
                model: model, isFocused: layout.panels.focus == .panel(ExplorerFeature.panelID), onOpen: onOpen,
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
        HStack {
            Text(model.root.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button {
                operations.newFile(near: nil)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New File")
            Button {
                operations.newFolder(near: nil)
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New Folder")
            Menu {
                // explorer R5: persisted, default visible.
                Toggle("Hide Ignored Files", isOn: Bindable(model).hidesExcluded)
                Toggle("Follow Active Tab", isOn: Bindable(model).followsActiveTab)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
