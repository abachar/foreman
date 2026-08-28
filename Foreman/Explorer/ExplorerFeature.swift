import AppKit
import SwiftUI

/// Entry point of the explorer: declares its panel and shortcut to the layout (architecture).
@MainActor
enum ExplorerFeature {
    static let panelID: PanelID = "explorer.tree"

    /// What other features reach: the model (explorer R15) and the actions (R20 menu entries).
    struct Registration {
        let model: ExplorerModel
        let actions: ExplorerActions
    }

    @discardableResult
    static func register(
        in layout: LayoutManager, workspace: Workspace, editor: EditorFeature, theme: ThemeService
    )
        -> Registration
    {
        let model = ExplorerModel(root: workspace.root, fsWatch: workspace.fsWatch)
        if let state = try? workspace.state.section("explorer", as: ExplorerState.self) {
            model.restore(state)
        }
        let actions = ExplorerActions(model: model, root: workspace.root, editor: editor, layout: layout)
        layout.register(
            panel: PanelDescriptor(
                id: panelID, title: "Explorer", side: .left, icon: "folder", defaultShortcut: "cmd+shift+e",
                makeView: {
                    AnyView(
                        ExplorerPanelView(
                            model: model, layout: layout, theme: theme,
                            onStateChange: { state in workspace.setState("explorer", to: state) },
                            // explorer R12, R13: pinned, or a new group on the right; never a preview.
                            onOpen: { node, mode in
                                editor.open(
                                    workspace.root.appending(path: node.relativePath), preview: false,
                                    newGroup: mode == .newGroup)
                            },
                            pathOfTab: { editor.path(of: $0) },
                            operations: actions
                        ))
                },
                // explorer R8: the first level is read when the panel is shown, off the main actor.
                activate: { model.activate() },
                deactivate: { model.deactivate() }))
        // agents R10b: `cmd+e` while the tree has the focus.
        layout.shortcuts.register(
            ShortcutAction(id: "explorer.sendToAgent", title: "Send to Agent", scope: .panel, defaultShortcut: "cmd+e")
            {
                guard layout.panels.isVisible(panelID), let node = actions.selectedNode else { return }
                actions.sendToAgent(node)
            })
        return Registration(model: model, actions: actions)
    }
}

/// explorer R16–R20: what the menu, the keys and the buttons do; every IO is off the main
/// actor and reported in the panel on failure (R19).
@MainActor
final class ExplorerActions {
    private let model: ExplorerModel
    private let root: URL
    private let editor: EditorFeature
    private let layout: LayoutManager
    /// explorer R20, git R20: set by `Git/` once it exists; `nil` hides the entry.
    var fileHistory: ((FileNode) -> Void)?
    /// explorer R20, agents R10b: set by `Agents/` once it exists; `nil` hides the entry.
    var sendToAgent: ((AgentMention) -> Void)?

    init(model: ExplorerModel, root: URL, editor: EditorFeature, layout: LayoutManager) {
        self.model = model
        self.root = root
        self.editor = editor
        self.layout = layout
    }

    var selectedNode: FileNode? {
        model.selection.flatMap { model.node(at: $0) }
    }

    /// agents R10a: a file or a folder as `@path`.
    func sendToAgent(_ node: FileNode) {
        sendToAgent?(
            .path(root.appending(path: node.relativePath), lines: nil, isDirectory: node.kind == .directory))
    }

    private var window: NSWindow? {
        NSApp.keyWindow
    }

    /// explorer R16: the name comes from a sheet; `/` makes the intermediate folders.
    func newFile(near node: FileNode?) {
        askName(title: "New File", placeholder: "name.ext or folder/name.ext") { [self] name in
            let folder = ExplorerOperations.targetFolder(forSelection: node ?? selectedNode, root: root)
            Task {
                do {
                    let url = try await ExplorerOperations.createFile(named: name, in: folder, root: root)
                    await refresh(url.deletingLastPathComponent())
                    editor.open(url, preview: false)
                } catch {
                    model.report(error)
                }
            }
        }
    }

    func newFolder(near node: FileNode?) {
        askName(title: "New Folder", placeholder: "name or a/b/c") { [self] name in
            let folder = ExplorerOperations.targetFolder(forSelection: node ?? selectedNode, root: root)
            Task {
                do {
                    let url = try await ExplorerOperations.createFolder(named: name, in: folder, root: root)
                    await refresh(url.deletingLastPathComponent())
                    model.revealRequest = Workspace.persistedPath(for: url, root: root)
                } catch {
                    model.report(error)
                }
            }
        }
    }

    /// explorer R17: called by the inline editor of the cell with the new name.
    func rename(_ node: FileNode, to name: String) {
        guard name != node.name else { return }
        let url = root.appending(path: node.relativePath)
        Task {
            do {
                let target = try await ExplorerOperations.rename(url, to: name, root: root)
                editor.fileRenamed(from: url, to: target)
                await refresh(url.deletingLastPathComponent())
                model.revealRequest = Workspace.persistedPath(for: target, root: root)
            } catch {
                model.report(error)
            }
        }
    }

    /// explorer R18: confirmation, then the Trash.
    func delete(_ node: FileNode) {
        let url = root.appending(path: node.relativePath)
        Task {
            let count = node.kind == .directory ? await ExplorerOperations.entryCount(of: url) : 0
            let alert = NSAlert()
            alert.messageText = "Move \u{201c}\(node.name)\u{201d} to the Trash?"
            if count > 0 {
                alert.informativeText = "The folder contains \(count >= 10_000 ? "10 000+" : "\(count)") items."
            }
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard let window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            do {
                try await ExplorerOperations.trash(url, root: root)
                editor.fileDeleted(url)
                await refresh(url.deletingLastPathComponent())
            } catch {
                model.report(error)
            }
        }
    }

    /// git R20: the file's history in the `git.history` panel.
    func showHistory(_ node: FileNode) {
        fileHistory?(node)
    }

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: node.relativePath)])
    }

    /// explorer R20: relative to the root, or absolute.
    func copyPath(_ node: FileNode, absolute: Bool) {
        let text = absolute ? root.appending(path: node.relativePath).path(percentEncoded: false) : node.relativePath
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The parent is read again at once rather than waiting for FSEvents, so the new entry can
    /// be selected.
    private func refresh(_ folder: URL) async {
        let path = Workspace.persistedPath(for: folder, root: root)
        await model.load(path.hasPrefix("/") ? "" : path)
    }

    private func askName(title: String, placeholder: String, _ done: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
            done(name)
        }
    }
}
