import AppKit
import Foundation
import SwiftUI

/// Entry point of the editor: the `editor.file` tab kind and `open` (editor R1–R3), called by
/// the explorer, git, the palette and the search.
@MainActor
final class EditorFeature {
    static let tabKind = "editor.file"

    private let layout: LayoutManager
    private let workspace: Workspace
    private let highlighter: Highlighter
    private let theme: ThemeService
    private var tabs: [TabID: EditorTab] = [:]

    init(layout: LayoutManager, workspace: Workspace, theme: ThemeService) {
        self.layout = layout
        self.workspace = workspace
        self.theme = theme
        highlighter = Highlighter(theme: theme)
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.tabKind,
                makeView: { [weak self] id, payload in self?.restore(id, payload: payload) },
                serialize: { [weak self] id in self?.serialize(id) },
                confirmClose: { [weak self] id in await self?.confirmClose(id) ?? true }))
        registerActions()
    }

    // MARK: - Editing (editor R6, R8, R10, R23)

    /// editor R23: every command is scoped to the active `editor.file` tab.
    private func registerActions() {
        let actions: [(String, String, String, () -> Void)] = [
            ("editor.save", "Save", "cmd+s", { [weak self] in self?.saveActive() }),
            ("editor.saveAll", "Save All", "cmd+opt+s", { [weak self] in self?.saveAll() }),
            ("editor.indent", "Indent", "cmd+]", { [weak self] in self?.indentActive(outdent: false) }),
            ("editor.outdent", "Outdent", "cmd+[", { [weak self] in self?.indentActive(outdent: true) }),
            ("editor.comment", "Toggle Comment", "cmd+/", { [weak self] in self?.toggleCommentActive() }),
            ("editor.moveLine.up", "Move Line Up", "opt+up", { [weak self] in self?.moveLinesActive(up: true) }),
            ("editor.moveLine.down", "Move Line Down", "opt+down", { [weak self] in self?.moveLinesActive(up: false) }),
            ("editor.goToLine", "Go to Line…", "cmd+l", { [weak self] in self?.goToLineActive() }),
            ("editor.keepOpen", "Keep Open", "cmd+k", { [weak self] in self?.keepOpenActive() }),
        ]
        for (id, title, shortcut, perform) in actions {
            layout.shortcuts.register(
                ShortcutAction(
                    id: id, title: title, scope: .tab(kind: Self.tabKind), defaultShortcut: shortcut, perform: perform))
        }
    }

    private var active: (id: TabID, tab: EditorTab)? {
        guard let id = layout.model.active.active?.id, let tab = tabs[id] else { return nil }
        return (id, tab)
    }

    private func apply(_ edit: TextEditing.Edit?, to textView: NSTextView) {
        guard let edit, textView.isEditable,
            textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
        else { return }
        textView.insertText(edit.replacement, replacementRange: edit.range)
        textView.setSelectedRange(edit.selection)
    }

    private func indentActive(outdent: Bool) {
        guard let (_, tab) = active, let textView = tab.textView else { return }
        apply(
            TextEditing.indent(
                textView.selectedRange(), in: textView.string as NSString, unit: tab.indentUnit, outdent: outdent),
            to: textView)
    }

    private func toggleCommentActive() {
        guard let (_, tab) = active, let textView = tab.textView, let prefix = tab.language?.lineCommentPrefix else {
            return
        }
        apply(
            TextEditing.toggleComment(textView.selectedRange(), in: textView.string as NSString, prefix: prefix),
            to: textView)
    }

    private func moveLinesActive(up: Bool) {
        guard let (_, tab) = active, let textView = tab.textView else { return }
        apply(TextEditing.moveLines(textView.selectedRange(), in: textView.string as NSString, up: up), to: textView)
    }

    private func goToLineActive() {
        guard let (_, tab) = active, let textView = tab.textView, let window = textView.window else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, let line = Int(field.stringValue), line > 0 else { return }
            tab.requestedLine = line
        }
    }

    private func keepOpenActive() {
        guard let (id, tab) = active else { return }
        pin(id, tab)
    }

    /// The dirty marker follows the tab (editor R1, R5); the first edit pins a preview (R2).
    func syncDirty(_ id: TabID) {
        guard let tab = tabs[id], let owner = layout.model.owner(of: id),
            let layoutTab = layout.model[group: owner]?.tabs.first(where: { $0.id == id })
        else { return }
        if tab.isDirty, !tab.isPinned {
            tab.isPinned = true
        }
        if layoutTab.isDirty != tab.isDirty || layoutTab.isPreview != !tab.isPinned {
            layout.update(id, title: layoutTab.title, isDirty: tab.isDirty, isPreview: !tab.isPinned)
        }
    }

    private var insertFinalNewline: Bool {
        struct Section: Decodable {
            var insertFinalNewline: Bool?
        }
        return (try? workspace.config.section("editor", as: Section.self))?.insertFinalNewline ?? true
    }

    private func saveActive() {
        guard let (id, tab) = active else { return }
        Task { _ = await save(id, tab) }
    }

    /// editor R8: `cmd+opt+s`.
    private func saveAll() {
        Task {
            for (id, tab) in tabs where tab.isDirty {
                _ = await save(id, tab)
            }
        }
    }

    /// editor R8, R10 and edge cases: read-only offers the Finder, a stale file asks before
    /// overwriting, an IO error is shown.
    private func save(_ id: TabID, _ tab: EditorTab, force: Bool = false) async -> Bool {
        guard let window = tab.textView?.window else { return false }
        if tab.document?.isReadOnly == true {
            let alert = NSAlert()
            alert.messageText = "\(tab.url.lastPathComponent) is read-only"
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "Cancel")
            if await alert.beginSheetModal(for: window) == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([tab.url])
            }
            return false
        }
        do {
            if try await tab.save(insertFinalNewline: insertFinalNewline, force: force) {
                syncDirty(id)
                return true
            }
            let alert = NSAlert()
            alert.messageText = "\(tab.url.lastPathComponent) changed on disk"
            alert.informativeText = "Overwrite the file with your version?"
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Cancel")
            guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return false }
            return await save(id, tab, force: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save"
            alert.informativeText = error.description
            await alert.beginSheetModal(for: window)
            return false
        }
    }

    /// layout R15: a dirty tab asks before closing; saving counts as consent.
    private func confirmClose(_ id: TabID) async -> Bool {
        guard let tab = tabs[id], tab.isDirty, let window = tab.textView?.window else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(tab.url.lastPathComponent)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch await alert.beginSheetModal(for: window) {
        case .alertFirstButtonReturn:
            return await save(id, tab)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    /// editor R1–R3: shows `url` in the active group, or activates the tab already showing it.
    func open(_ url: URL, preview: Bool, newGroup: Bool = false, line: Int? = nil) {
        let path = Workspace.persistedPath(for: url, root: workspace.root)
        if !newGroup, let existing = layout.model.active.tabs.first(where: { tabs[$0.id]?.path == path }) {
            if let tab = tabs[existing.id] {
                tab.requestedLine = line
                if !preview {
                    pin(existing.id, tab)
                }
            }
            layout.activate(existing.id, in: layout.model.activeGroup)
            return
        }
        // editor R2: one preview per group, replaced by the next one.
        let replaced = preview && !newGroup ? layout.model.active.tabs.first { tabs[$0.id]?.isPinned == false } : nil
        let tab = EditorTab(path: path, url: url, isPinned: !preview, line: line)
        guard
            let id = layout.openTab(
                kind: Self.tabKind, title: url.lastPathComponent, payload: encode(tab.payload), newGroup: newGroup,
                isPreview: preview)
        else { return }
        tabs[id] = tab
        if let replaced {
            tabs[replaced.id] = nil
            Task { await layout.closeTab(replaced.id) }
        }
        retitle(group: layout.model.activeGroup)
    }

    /// explorer R14: the file of a tab, `nil` for a tab that is not the editor's.
    func path(of id: TabID) -> String? {
        tabs[id]?.path
    }

    /// editor R2: a preview becomes pinned (double click, `cmd+k enter`, first edit).
    private func pin(_ id: TabID, _ tab: EditorTab) {
        guard !tab.isPinned, let owner = layout.model.owner(of: id),
            let title = layout.model[group: owner]?.tabs.first(where: { $0.id == id })?.title
        else { return }
        tab.isPinned = true
        layout.update(id, title: title, isDirty: false, isPreview: false)
    }

    private func restore(_ id: TabID, payload: String) -> AnyView? {
        let tab: EditorTab
        if let existing = tabs[id] {
            tab = existing
        } else {
            guard let data = payload.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(EditorTab.Payload.self, from: data)
            else { return nil }
            let url = Workspace.url(forPersistedPath: decoded.path, root: workspace.root)
            // editor R4: a file gone since is not restored (product, edge cases).
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            tab = EditorTab(path: decoded.path, url: url, isPinned: decoded.pinned)
            tabs[id] = tab
            if !decoded.pinned {
                // The layout inserts the tab right after this call; the italic follows.
                Task { [layout] in
                    guard let owner = layout.model.owner(of: id),
                        let title = layout.model[group: owner]?.tabs.first(where: { $0.id == id })?.title
                    else { return }
                    layout.update(id, title: title, isDirty: false, isPreview: true)
                }
            }
        }
        return AnyView(
            EditorTabView(tab: tab, theme: theme, highlighter: highlighter) { [weak self] in self?.syncDirty(id) })
    }

    private func serialize(_ id: TabID) -> String? {
        tabs[id].map { encode($0.payload) }
    }

    private func encode(_ payload: EditorTab.Payload) -> String {
        // A two-field Codable struct always encodes.
        String(decoding: (try? JSONEncoder().encode(payload)) ?? Data(), as: UTF8.self)
    }

    /// editor R5: titles of a group, deduplicated with the parent folder.
    private func retitle(group: GroupID) {
        guard let tabsInGroup = layout.model[group: group]?.tabs else { return }
        let editorTabs = tabsInGroup.compactMap { tab in tabs[tab.id].map { (tab, $0) } }
        let titles = EditorTitles.titles(for: editorTabs.map(\.1.path))
        for ((tab, editorTab), title) in zip(editorTabs, titles) where tab.title != title {
            layout.update(tab.id, title: title, isDirty: tab.isDirty, isPreview: !editorTab.isPinned)
        }
    }
}
