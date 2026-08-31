import AppKit
import Foundation
import SwiftUI
import os

/// Entry point of the editor: the `editor.file` tab kind and `open` (editor R1–R3), called by
/// the explorer, git, the palette and the search.
@MainActor
final class EditorFeature {
    static let tabKind = "editor.file"
    static let searchPanelID: PanelID = "editor.search"

    private let layout: LayoutManager
    let workspace: Workspace
    let highlighter: Highlighter
    let theme: ThemeService
    private var tabs: [TabID: EditorTab] = [:]
    /// The tab `open` is creating: `openTab` asks for its view before returning its id.
    private var opening: EditorTab?
    private var watch: Task<Void, Never>?
    private var lspConfigWatch: Task<Void, Never>?
    private let palette: Palette
    private let index: QuickOpenIndex
    /// editor R35–R39: the workspace's language servers, created here and stopped with it.
    let lsp: LSPServers
    /// editor R47: the workspace's stylesheets, indexed at the first `cmd+click` that needs them.
    let selectors: SelectorIndex
    /// editor R41, R42: one popover for the whole window, whichever tab asked for it.
    let hoverPopover = HoverPopover()
    /// editor R42: the pending hover, cancelled by the next movement.
    var hoverTask: Task<Void, Never>?
    /// editor R42: the character the popover is about; a move within it asks nothing again.
    var hoverLocation: Int?
    private var gitWatch: Task<Void, Never>?
    /// editor R19: most recent first, 50 at most, persisted in the `editor` section.
    private(set) var recentPaths: [String] = []
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "editor")

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
        selectors = SelectorIndex(root: workspace.root)
        // editor R35: the section is read on every use, like the formatter's — a config change
        // needs no wiring. R46: the login environment, the same one the formatters run in.
        lsp = LSPServers(
            root: workspace.root,
            config: { [weak workspace] in
                guard let workspace, let catalog = try? workspace.config.section("lsp", as: LSPCatalog.self) else {
                    return .empty
                }
                return catalog
            },
            environment: { [weak workspace] in await workspace?.loginEnvironment() ?? [:] })
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.tabKind,
                showsFileIcon: true,
                makeView: { [weak self] id, payload in self?.restore(id, payload: payload) },
                serialize: { [weak self] id in self?.serialize(id) },
                confirmClose: { [weak self] id in await self?.confirmClose(id) ?? true },
                onClose: { [weak self] id in self?.tabClosed(id) }))
        registerActions()
        // layout R38: the double click of the tab bar and of the home screen; the layout has
        // already activated the group when this runs.
        layout.onNewTab = { [weak self] in Task { await self?.newFile() } }
        routeDiagnostics()
        bindHoverPopover()
        watchConfigForLSP()
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
                makeView: { [weak self, theme] in
                    AnyView(
                        SearchPanelView(model: model, theme: theme) { match, pinned in
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
                guard let self, let url = Workspace.url(forPersistedPath: item.id, root: workspace.root) else {
                    return
                }
                open(url, preview: false, newGroup: newGroup)
            })
        palette.present(source, over: window)
    }

    private func quickOpenResults(_ query: String) async -> PaletteSource.Results {
        if query.isEmpty {
            // editor R19: no query, the recent files.
            let existing = recentPaths.filter { path in
                guard let url = Workspace.url(forPersistedPath: path, root: workspace.root) else { return false }
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            }
            return PaletteSource.Results(
                items: existing.map {
                    PaletteItem(
                        id: $0, title: AttributedString($0),
                        icon: FileIcon.name(for: ($0 as NSString).lastPathComponent))
                })
        }
        await index.build()
        let search = await index.search(query, limit: Palette.limit)
        return PaletteSource.Results(
            items: search.paths.map {
                PaletteItem(
                    id: $0, title: PaletteItem.highlighted($0, matching: query),
                    icon: FileIcon.name(for: ($0 as NSString).lastPathComponent))
            },
            notice: search.isIndexTruncated
                ? "Index truncated at \(QuickOpenIndex.limit) files — open a subfolder for a full search" : nil)
    }

    /// editor R19 and layout R33: the home screen's Recent section.
    private func publishRecents() {
        layout.replaceHomeEntries(
            in: .recent,
            with: recentPaths.prefix(10).map { path in
                HomeEntry(
                    id: "editor.recent.\(path)", title: path,
                    icon: FileIcon.name(for: (path as NSString).lastPathComponent),
                    section: .recent
                ) { [weak self] in
                    guard let self, let url = Workspace.url(forPersistedPath: path, root: workspace.root) else {
                        return
                    }
                    open(url, preview: false)
                }
            })
    }

    isolated deinit {
        watch?.cancel()
        gitWatch?.cancel()
    }

    // MARK: - Disk (editor R9; explorer R17, R18)

    /// editor R35, R36: the servers follow the `lsp` section when it changes on disk.
    private func watchConfigForLSP() {
        lspConfigWatch = Task { [weak self, workspace] in
            for await _ in workspace.configChanges() {
                guard let self else { return }
                lspConfigChanged()
            }
        }
    }

    private func watchDisk() {
        watch = Task { [weak self, fsWatch = workspace.fsWatch, root = workspace.root] in
            for await batch in await fsWatch.changes(under: root) {
                guard let self else { return }
                let changed = Set(batch.map { $0.standardizedFileURL.path(percentEncoded: false) })
                for tab in tabs.values where changed.contains(tab.url.standardizedFileURL.path(percentEncoded: false)) {
                    await tab.fileChangedOnDisk()
                }
                await index.apply(batch)
                // editor R47: a stylesheet that changed is re-read, on the index's own actor.
                await selectors.apply(batch)
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

    // MARK: - Untitled tabs (editor R34)

    /// editor R34: opens an untitled tab — an ordinary file tab on a new, empty scratch file.
    func newFile(newGroup: Bool = false) async {
        do {
            open(try await Scratch.create(root: workspace.root), preview: false, newGroup: newGroup)
        } catch {
            logger.error("scratch not created: \(error.description, privacy: .public)")
        }
    }

    /// editor R34, R8: `cmd+s` on an untitled tab asks where to write it, the workspace root by
    /// default; the file is named here and nowhere else (decision 2026-08-30).
    private func saveScratch(_ id: TabID, _ tab: EditorTab) async -> Bool {
        // Naming needs a panel (R8): it falls back to the key window when the view is detached.
        guard let window = tab.textView?.window ?? NSApp.keyWindow else { return false }
        let panel = NSSavePanel()
        panel.directoryURL = workspace.root
        panel.nameFieldStringValue = tab.url.lastPathComponent
        panel.canCreateDirectories = true
        panel.message = "Save the file in the workspace."
        guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else { return false }
        return await saveScratch(id, to: destination)
    }

    /// editor R34: the draft is written, the scratch moved to `destination`, and the tab becomes an
    /// ordinary file tab — title (R5), highlighting (R11) and recent files (R19) follow the path.
    ///
    /// Apart from the panel, so the transformation is tested without AppKit.
    @discardableResult
    func saveScratch(_ id: TabID, to destination: URL) async -> Bool {
        guard let tab = tabs[id], tab.isScratch else { return false }
        await tab.writeScratch()
        do {
            try await Scratch.move(tab.url, to: destination)
        } catch {
            logger.error("scratch not saved: \(error.description, privacy: .public)")
            tab.message = error.description
            return false
        }
        let path = Workspace.persistedPath(for: destination, root: workspace.root)
        tab.fileRenamed(to: destination, path: path)
        // The document was read from the scratch: reading the file again is what makes the tab
        // clean and its modification date the saved one (editor R10).
        await tab.reload()
        syncDirty(id)
        if let owner = layout.model.owner(of: id) {
            layout.update(id, title: destination.lastPathComponent, isDirty: false, isPreview: !tab.isPinned)
            retitle(group: owner)
        }
        noteRecent(path)
        return true
    }

    /// editor R34: the scratch goes with its tab (layout R15 already asked, R8 already offered to
    /// name it); a scratch saved away is no longer one.
    private func tabClosed(_ id: TabID) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        tab.textCoordinator = nil
        // editor R37: the last tab on this file closes the document, and R36 the server with it.
        lsp.closed(tab.url)
        guard tab.isScratch else { return }
        Task { await Scratch.remove(tab.url) }
    }

    /// editor R19: `path` becomes the most recent; the list is capped and persisted.
    nonisolated static func pushRecent(_ path: String, into recent: [String]) -> [String] {
        Array(([path] + recent.filter { $0 != path }).prefix(50))
    }

    private func noteRecent(_ path: String) {
        // editor R34: a scratch is not a file the user opened; it has no place in the recents.
        guard !Scratch.isScratch(path: path) else { return }
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
            ("editor.format", "Format File", "cmd+shift+l", { [weak self] in self?.formatActive() }),
            (
                "editor.togglePreview", "Toggle Markdown Preview", "cmd+shift+v",
                { [weak self] in self?.active?.tab.togglePreview() }
            ),
            (
                "editor.replace", "Find and Replace", "cmd+opt+f",
                { [weak self] in self?.findActive(.showReplaceInterface) }
            ),
            ("editor.sendToAgent", "Send to Agent", "cmd+e", { [weak self] in self?.sendActiveToAgent() }),
            (
                "editor.goToDefinition", "Go to Definition", "ctrl+cmd+j",
                { [weak self] in self?.goToDefinitionAtCursor() }
            ),
            ("editor.fold", "Fold Region", "cmd+opt+[", { [weak self] in self?.foldAtCursor(true) }),
            ("editor.unfold", "Unfold Region", "cmd+opt+]", { [weak self] in self?.foldAtCursor(false) }),
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
        // editor R34: an untitled tab opens from anywhere, the home screen of an empty group included.
        layout.shortcuts.register(
            ShortcutAction(id: "editor.newFile", title: "New File", defaultShortcut: "cmd+n") { [weak self] in
                Task { await self?.newFile() }
            })
    }

    /// agents R10b, R10d: set by `Agents/` once it exists.
    var sendToAgent: ((AgentMention) -> Void)?

    /// editor R27: the region around the cursor.
    private func foldAtCursor(_ folded: Bool) {
        guard let (_, tab) = active, let textView = tab.textView else { return }
        let line = TextEditing.position(at: textView.selectedRange().location, in: textView.string as NSString).line
        tab.setFold(atLine: line, folded: folded)
    }

    /// agents R10b: the selection's lines, or the file.
    private func sendActiveToAgent() {
        guard let (_, tab) = active, let sendToAgent else { return }
        let lines = tab.textView.flatMap {
            TextEditing.selectedLines($0.selectedRange(), in: $0.string as NSString)
        }
        sendToAgent(.path(tab.url, lines: lines, isDirectory: false))
    }

    /// Every editor tab that has its text (editor R35: only those are declared to a server).
    func tabs(showingAnyFile: Bool) -> [EditorTab] {
        tabs.values.filter { $0.document != nil }
    }

    /// editor R40: every open tab on `url` — the same file can be open in two groups (R1).
    func tabsShowing(_ url: URL) -> [EditorTab] {
        tabs.values.filter { $0.url == url }
    }

    /// The tab the editor's commands act on; `nil` when the active tab is not the editor's.
    var activeTab: EditorTab? {
        active?.tab
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

    // MARK: - Formatting (editor R24–R30, R32)

    /// Read on every use, like `insertFinalNewline`: a config change needs no wiring.
    private var formatterCatalog: FormatterCatalog {
        do {
            let catalog = try workspace.config.section("formatter", as: FormatterCatalog.self) ?? .empty
            for warning in catalog.warnings {
                logger.warning("\(warning, privacy: .public)")
            }
            return catalog
        } catch {
            logger.warning("formatter section ignored: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    /// editor R25, R32: why the tab is not formatted, `nil` when it can be.
    nonisolated static func formatRefusal(
        isReadOnly: Bool, isPreview: Bool, key: String, command: String?, isBinaryAvailable: Bool
    ) -> String? {
        if isReadOnly {
            return "Read-only or over 2 MB: not formatted"
        }
        if isPreview {
            return "Markdown preview: switch to the source (⌘⇧V) to format"
        }
        guard let command else {
            return "No formatter for `.\(key)` in .foreman/config.json"
        }
        guard isBinaryAvailable else {
            return "`\(FormatterCatalog.binary(of: command))` not found in PATH"
        }
        return nil
    }

    /// editor R30: the banner's wording for what the run returned; `nil` when applied or unchanged.
    nonisolated static func formatMessage(for result: FormatterLaunch.Result, timeout: Duration) -> String? {
        switch result {
        case .formatted, .unchanged:
            return nil
        case .failed(let status, let stderr):
            return stderr.isEmpty ? "Formatter exited with status \(status)" : "Formatter (status \(status)): \(stderr)"
        case .timedOut:
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            return
                "Formatter stopped after \(seconds.formatted()) s — raise formatter.timeout in .foreman/config.json"
        }
    }

    /// `cmd+shift+l` (editor R24).
    private func formatActive() {
        guard let (_, tab) = active else { return }
        // editor R30: a second trigger while one runs is ignored, never queued.
        guard tab.beginFormatting() else {
            NSSound.beep()
            return
        }
        Task {
            defer { tab.endFormatting() }
            tab.message = await format(tab)
        }
    }

    /// editor R25–R30, R32: runs the formatter of the tab's file and applies the result in the
    /// view; returns what the banner should say, `nil` when applied or unchanged.
    private func format(_ tab: EditorTab) async -> String? {
        guard let textView = tab.textView, let document = tab.document else { return nil }
        let catalog = formatterCatalog
        let key = FormatterCatalog.key(for: tab.url)
        let command = catalog.command(forKey: key)
        let environment = await workspace.loginEnvironment()
        if let refusal = Self.formatRefusal(
            isReadOnly: document.isReadOnly, isPreview: tab.mode == .preview, key: key, command: command,
            isBinaryAvailable: command.map { FormatterCatalog.isBinaryAvailable($0, inPath: environment["PATH"]) }
                ?? false)
        {
            return refusal
        }
        guard let command else { return nil }
        let text = textView.string
        let result = await FormatterLaunch.run(
            text, command: command, cwd: tab.url.deletingLastPathComponent(), environment: environment,
            timeout: catalog.timeout)
        if case .formatted(let formatted) = result, let textView = tab.textView, textView.string == text {
            apply(formatted, to: textView)
        }
        return Self.formatMessage(for: result, timeout: catalog.timeout)
    }

    /// editor R29: one undoable replacement, the cursor back by line and column, the scroll kept.
    private func apply(_ formatted: String, to textView: NSTextView) {
        let old = textView.string as NSString
        let position = TextEditing.position(at: textView.selectedRange().location, in: old)
        let scroll = textView.enclosingScrollView
        let origin = scroll?.contentView.bounds.origin
        let whole = NSRange(location: 0, length: old.length)
        guard textView.isEditable, textView.shouldChangeText(in: whole, replacementString: formatted) else { return }
        textView.replaceCharacters(in: whole, with: formatted)
        textView.didChangeText()
        textView.setSelectedRange(
            NSRange(location: TextEditing.location(of: position, in: textView.string as NSString), length: 0))
        if let scroll, let origin {
            // TextKit 2 lays out lazily: without this the clip view clamps the target (see EditorTextView).
            if let layoutManager = textView.textLayoutManager {
                layoutManager.ensureLayout(for: layoutManager.documentRange)
            }
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
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

    /// editor R34: writes every pending scratch draft now, for the quit path (`cmd+q` chains no
    /// confirmation, so the debounced write of the last second would be lost).
    func flushScratches() async {
        for tab in tabs.values where tab.isScratch {
            await tab.writeScratch()
        }
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

    /// editor R8, R10 and edge cases — read-only offers the Finder, a stale file asks before
    /// overwriting, an IO error is shown.
    ///
    /// Only the prompts need a window: a dirty tab whose view is detached is still written, and
    /// stays dirty when a prompt cannot be shown.
    private func save(_ id: TabID, _ tab: EditorTab, force: Bool = false) async -> Bool {
        // editor R34: an untitled tab has no name yet; saving is where it gets one.
        if tab.isScratch {
            return await saveScratch(id, tab)
        }
        let window = tab.textView?.window
        if tab.document?.isReadOnly == true {
            guard let window else { return false }
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
            // editor R10: overwriting a file changed on disk needs consent; with no window to
            // ask in, the tab stays dirty.
            guard let window else { return false }
            let alert = NSAlert()
            alert.messageText = "\(tab.url.lastPathComponent) changed on disk"
            alert.informativeText = "Overwrite the file with your version?"
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Cancel")
            guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return false }
            return await save(id, tab, force: true)
        } catch {
            guard let window else {
                logger.error("save failed: \(error.description, privacy: .private)")
                return false
            }
            let alert = NSAlert()
            alert.messageText = "Could not save"
            alert.informativeText = error.description
            await alert.beginSheetModal(for: window)
            return false
        }
    }

    /// layout R15: a dirty tab asks before closing; saving counts as consent.
    private func confirmClose(_ id: TabID) async -> Bool {
        guard let tab = tabs[id], tab.isDirty else { return true }
        // A detached view does not waive the consent: the prompt falls back to the key window,
        // and with no window at all the close is refused.
        guard let window = tab.textView?.window ?? NSApp.keyWindow else { return false }
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
            // Through the layout, so the close hooks run: the tab is forgotten, its coordinator
            // dropped, and a replaced scratch preview removes its file (R34).
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
        for (id, tab) in tabs where !open.contains(id) {
            tab.textCoordinator = nil
        }
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
                let decoded = try? JSONDecoder().decode(EditorTab.Payload.self, from: data),
                let url = Workspace.url(forPersistedPath: decoded.path, root: workspace.root)
            else { return nil }
            // editor R4: a file gone since is not restored (product, edge cases).
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            tab = EditorTab(
                path: decoded.path, url: url, isPinned: decoded.pinned, cursor: decoded.cursor, scroll: decoded.scroll,
                mode: decoded.mode, previewBlock: decoded.previewBlock)
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
        bindLSP(tab)
        return AnyView(
            EditorTabView(
                tab: tab, theme: theme, highlighter: highlighter, root: workspace.root,
                onDirtyChange: { [weak self] in self?.syncDirty(id) },
                onOpenFile: { [weak self] url in self?.open(url, preview: true) }))
    }

    /// editor R36: every server goes when the window's work is flushed at quit.
    func stopLanguageServers() async {
        await lsp.stopAll()
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
