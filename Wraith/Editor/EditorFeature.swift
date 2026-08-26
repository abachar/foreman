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
                serialize: { [weak self] id in self?.serialize(id) }))
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
        return AnyView(EditorTabView(tab: tab, theme: theme, highlighter: highlighter))
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
