import AppKit
import Foundation
import SwiftUI

/// Entry point of the editor: the `editor.file` tab kind and `open` (editor R1–R3), called by
/// the explorer, git, the palette and the search.
@MainActor
final class EditorFeature {
    static let tabKind = "editor.file"
    static let searchPanelID: PanelID = "editor.search"

    private let layout: LayoutManager
    private let workspace: Workspace
    private let highlighter: Highlighter
    private let theme: ThemeService
    private var tabs: [TabID: EditorTab] = [:]
    /// The tab `open` is creating: `openTab` asks for its view before returning its id.
    private var opening: EditorTab?
    private var watch: Task<Void, Never>?
    private let palette: Palette
    private let index: QuickOpenIndex
    private var gitWatch: Task<Void, Never>?
    /// editor R19: most recent first, 50 at most, persisted in the `editor` section.
    private(set) var recentPaths: [String] = []

    nonisolated struct State: Codable, Equatable, Sendable {
        var recent: [String]
    }

    init(layout: LayoutManager, workspace: Workspace, theme: ThemeService, palette: Palette, highlighter: Highlighter) {
        self.layout = layout
        self.workspace = workspace
        self.theme = theme
        self.palette = palette
        self.highlighter = highlighter
        index = QuickOpenIndex(root: workspace.root)
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.tabKind,
                makeView: { [weak self] id, payload in self?.restore(id, payload: payload) },
                serialize: { [weak self] id in self?.serialize(id) },
                confirmClose: { [weak self] id in await self?.confirmClose(id) ?? true }))
        registerActions()
        recentPaths = (try? workspace.state.section("editor", as: State.self))?.recent ?? []
        publishRecents()
        watchDisk()
        registerSearchPanel()
    }

    // MARK: - Content search (editor R20–R22)

    private func registerSearchPanel() {
        let model = SearchModel(root: workspace.root)
        layout.register(
            panel: PanelDescriptor(
                id: Self.searchPanelID, title: "Search", side: .bottom, defaultShortcut: "cmd+shift+f",
                makeView: { [weak self] in
                    AnyView(
                        SearchPanelView(model: model) { match, pinned in
                            guard let self else { return }
                            // editor R21: click opens a preview at the line, `cmd` pins it.
                            self.open(
                                self.workspace.root.appending(path: match.path), preview: !pinned, line: match.line)
                        })
                },
                // editor R21: closing the panel cancels the running search.
                deactivate: { model.cancel() }))
    }

    // MARK: - Quick open (editor R17–R19)

    /// `cmd+p`: the palette over the window, fed by the index (built on first use, R18).
    private func quickOpen() {
        guard let window = NSApp.keyWindow else { return }
        let source = PaletteSource(
            placeholder: "Open file…",
            results: { [weak self] query in await self?.quickOpenResults(query) ?? PaletteSource.Results(items: []) },
            select: { [weak self] item, newGroup in
                guard let self else { return }
                open(Workspace.url(forPersistedPath: item.id, root: workspace.root), preview: false, newGroup: newGroup)
            })
        palette.present(source, over: window)
    }

    private func quickOpenResults(_ query: String) async -> PaletteSource.Results {
        if query.isEmpty {
            // editor R19: no query, the recent files.
            let existing = recentPaths.filter {
                FileManager.default.fileExists(
                    atPath: Workspace.url(forPersistedPath: $0, root: workspace.root).path(percentEncoded: false))
            }
            return PaletteSource.Results(items: existing.map { PaletteItem(id: $0, title: AttributedString($0)) })
        }
        await index.build()
        let search = await index.search(query, limit: Palette.limit)
        return PaletteSource.Results(
            items: search.paths.map { PaletteItem(id: $0, title: PaletteItem.highlighted($0, matching: query)) },
            notice: search.isIndexTruncated
                ? "Index truncated at \(QuickOpenIndex.limit) files — open a subfolder for a full search" : nil)
    }

    /// editor R19 and layout R33: the home screen's Recent section.
    private func publishRecents() {
        layout.replaceHomeEntries(
            in: .recent,
            with: recentPaths.prefix(10).map { path in
                HomeEntry(id: "editor.recent.\(path)", title: path, icon: "doc", section: .recent) { [weak self] in
                    guard let self else { return }
                    open(Workspace.url(forPersistedPath: path, root: workspace.root), preview: false)
                }
            })
    }

    isolated deinit {
        watch?.cancel()
        gitWatch?.cancel()
    }

    // MARK: - Disk (editor R9; explorer R17, R18)

    private func watchDisk() {
        watch = Task { [weak self, fsWatch = workspace.fsWatch, root = workspace.root] in
            for await batch in await fsWatch.changes(under: root) {
                guard let self else { return }
                let changed = Set(batch.map { $0.standardizedFileURL.path(percentEncoded: false) })
                for tab in tabs.values where changed.contains(tab.url.standardizedFileURL.path(percentEncoded: false)) {
                    await tab.fileChangedOnDisk()
                }
                await index.apply(batch)
            }
        }
    }

    /// explorer R17: open tabs follow the renamed file or folder.
    func fileRenamed(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path(percentEncoded: false)
        for (id, tab) in tabs {
            let path = tab.url.standardizedFileURL.path(percentEncoded: false)
            guard path == oldPath || path.hasPrefix(oldPath + "/") else { continue }
            let suffix = path.dropFirst(oldPath.count)
            let url = URL(filePath: new.standardizedFileURL.path(percentEncoded: false) + suffix)
            tab.fileRenamed(to: url, path: Workspace.persistedPath(for: url, root: workspace.root))
            if let owner = layout.model.owner(of: id) {
                layout.update(id, title: url.lastPathComponent, isDirty: tab.isDirty, isPreview: !tab.isPinned)
                retitle(group: owner)
            }
        }
    }

    /// explorer R18: the tab stays with a banner; `cmd+s` recreates the file (editor R9).
    func fileDeleted(_ url: URL) {
        let deleted = url.standardizedFileURL.path(percentEncoded: false)
        for tab in tabs.values {
            let path = tab.url.standardizedFileURL.path(percentEncoded: false)
            if path == deleted || path.hasPrefix(deleted + "/") {
                tab.fileDeleted()
            }
        }
    }

    /// editor R19: `path` becomes the most recent; the list is capped and persisted.
    nonisolated static func pushRecent(_ path: String, into recent: [String]) -> [String] {
        Array(([path] + recent.filter { $0 != path }).prefix(50))
    }

    private func noteRecent(_ path: String) {
        recentPaths = Self.pushRecent(path, into: recentPaths)
        workspace.setState("editor", to: State(recent: recentPaths))
        publishRecents()
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
            ("editor.find", "Find", "cmd+f", { [weak self] in self?.findActive(.showFindInterface) }),
            (
                "editor.togglePreview", "Toggle Markdown Preview", "cmd+shift+v",
                { [weak self] in self?.active?.tab.togglePreview() }
            ),
            (
                "editor.replace", "Find and Replace", "cmd+opt+f",
                { [weak self] in self?.findActive(.showReplaceInterface) }
            ),
        ]
        for (id, title, shortcut, perform) in actions {
            layout.shortcuts.register(
                ShortcutAction(
                    id: id, title: title, scope: .tab(kind: Self.tabKind), defaultShortcut: shortcut, perform: perform))
        }
        // editor R23: quick open is global.
        layout.shortcuts.register(
            ShortcutAction(id: "editor.quickOpen", title: "Quick Open", defaultShortcut: "cmd+p") { [weak self] in
                self?.quickOpen()
            })
        layout.register(
            homeEntry: HomeEntry(
                id: "editor.quickOpen", title: "Open File", icon: "doc.text.magnifyingglass", section: .actions
            ) {
                [weak self] in self?.quickOpen()
            })
    }

    private var active: (id: TabID, tab: EditorTab)? {
        guard let id = layout.model.active.active?.id, let tab = tabs[id] else { return nil }
        return (id, tab)
    }

    /// Test seam: the tabs the feature knows.
    var openTabCount: Int {
        tabs.count
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

    /// editor R7: NSTextFinder's own bar, driven through `performFindPanelAction`.
    private func findActive(_ action: NSTextFinder.Action) {
        guard let (_, tab) = active, let textView = tab.textView else { return }
        textView.window?.makeFirstResponder(textView)
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        textView.performFindPanelAction(sender)
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
        prune()
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

    /// editor R18: the quick open follows git's ignored entries (one table per repo, merged).
    func watchGit(_ changes: AsyncStream<GitStatusChange>) {
        gitWatch?.cancel()
        gitWatch = Task { [weak self, index] in
            var perRepo: [String: Set<String>] = [:]
            for await change in changes {
                guard self != nil else { return }
                let prefix = change.repo.id == "." ? "" : change.repo.id + "/"
                perRepo[change.repo.id] = Set(
                    change.statuses.filter { $0.value == .ignored }.keys.map {
                        prefix + ($0.hasSuffix("/") ? String($0.dropLast()) : $0)
                    })
                await index.setIgnored(perRepo.values.reduce(into: []) { $0.formUnion($1) })
            }
        }
    }

    /// editor R1–R3: shows `url` in the active group, or activates the tab already showing it.
    func open(_ url: URL, preview: Bool, newGroup: Bool = false, line: Int? = nil) {
        prune()
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
        opening = tab
        defer { opening = nil }
        guard
            layout.openTab(
                kind: Self.tabKind, title: url.lastPathComponent, payload: encode(tab.payload), newGroup: newGroup,
                isPreview: preview) != nil
        else { return }
        noteRecent(path)
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

    /// Forgets the tabs the layout closed (`cmd+w` does not tell the owner).
    private func prune() {
        let open = Set(layout.model.tree.groups.flatMap { layout.model[group: $0]?.tabs.map(\.id) ?? [] })
        tabs = tabs.filter { open.contains($0.key) }
    }

    /// The one place a tab is bound to its view: `open` (through `opening`) or the restoration.
    private func restore(_ id: TabID, payload: String) -> AnyView? {
        let tab: EditorTab
        if let existing = tabs[id] {
            tab = existing
        } else if let opening {
            tab = opening
            tabs[id] = tab
        } else {
            guard let data = payload.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(EditorTab.Payload.self, from: data)
            else { return nil }
            let url = Workspace.url(forPersistedPath: decoded.path, root: workspace.root)
            // editor R4: a file gone since is not restored (product, edge cases).
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            tab = EditorTab(
                path: decoded.path, url: url, isPinned: decoded.pinned, cursor: decoded.cursor, scroll: decoded.scroll,
                mode: decoded.mode)
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
            EditorTabView(
                tab: tab, theme: theme, highlighter: highlighter, root: workspace.root,
                onDirtyChange: { [weak self] in self?.syncDirty(id) },
                onOpenFile: { [weak self] url in self?.open(url, preview: true) }))
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
