import SwiftUI

/// Entry point of the explorer: declares its panel and shortcut to the layout (architecture).
@MainActor
enum ExplorerFeature {
    static let panelID: PanelID = "explorer.tree"

    static func register(in layout: LayoutManager, workspace: Workspace, editor: EditorFeature) {
        let model = ExplorerModel(root: workspace.root, fsWatch: workspace.fsWatch)
        if let state = try? workspace.state.section("explorer", as: ExplorerState.self) {
            model.restore(state)
        }
        layout.register(
            panel: PanelDescriptor(
                id: panelID, title: "Explorer", side: .left, defaultShortcut: "cmd+shift+e",
                makeView: {
                    AnyView(
                        ExplorerPanelView(
                            model: model, layout: layout,
                            onStateChange: { state in workspace.setState("explorer", to: state) },
                            // explorer R12: a click opens a preview in the active group.
                            onOpen: { node in
                                editor.open(workspace.root.appending(path: node.relativePath), preview: true)
                            }
                        ))
                },
                // explorer R8: the first level is read when the panel is shown, off the main actor.
                activate: { model.activate() },
                deactivate: { model.deactivate() }))
    }
}
