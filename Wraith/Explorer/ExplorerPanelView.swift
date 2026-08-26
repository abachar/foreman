import SwiftUI

/// The left panel `explorer.tree`: a header with the panel menu, the error banner, the tree.
struct ExplorerPanelView: View {
    let model: ExplorerModel
    let layout: LayoutManager
    let onStateChange: (ExplorerState) -> Void
    let onOpen: (FileNode) -> Void

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
                model: model, isFocused: layout.panels.focus == .panel(ExplorerFeature.panelID), onOpen: onOpen)
        }
        .onChange(of: model.persisted) { _, state in
            onStateChange(state)
        }
    }

    private var header: some View {
        HStack {
            Text(model.root.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Menu {
                // explorer R5: persisted, default visible.
                Toggle("Hide Ignored Files", isOn: Bindable(model).hidesExcluded)
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
