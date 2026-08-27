import AppKit
import SwiftUI

/// The tree itself: `NSOutlineView` with a lazy data source (explorer, technical options).
///
/// Items are `OutlineItem`s cached per relative path so the outline view keeps expansion,
/// selection and scroll across reloads (R10). A folder's level is asked to the model at its
/// first expansion (R7); the model's `version` tells this view what to reload.
/// explorer R12, R13: how a file is opened from the tree.
enum ExplorerOpenMode {
    case preview
    case pinned
    case newGroup
}

struct ExplorerOutlineView: NSViewRepresentable {
    let model: ExplorerModel
    let isFocused: Bool
    let onOpen: (FileNode, ExplorerOpenMode) -> Void
    let operations: ExplorerActions

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onOpen: onOpen, operations: operations)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = KeyboardOutlineView()
        outline.onKey = { [coordinator = context.coordinator] key in coordinator.handle(key) }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 12
        outline.autoresizesOutlineColumn = true
        // The only column takes the whole width from the first frame (bug: names hidden until
        // the panel was resized).
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAutomaticRowHeights = false
        outline.allowsEmptySelection = true
        outline.autosaveExpandedItems = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.action = #selector(Coordinator.clicked)
        outline.doubleAction = #selector(Coordinator.doubleClicked)
        // explorer R20: the context menu, built for the clicked row.
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.sync(version: model.version, hidesExcluded: model.hidesExcluded)
        context.coordinator.outline?.sizeLastColumnToFit()
        if let path = model.revealRequest {
            model.revealRequest = nil
            context.coordinator.reveal(path)
        }
        if isFocused, let window = scroll.window, let outline = context.coordinator.outline,
            window.firstResponder !== outline
        {
            window.makeFirstResponder(outline)
        }
    }

    /// One row; reference type so the outline view can track it by identity.
    final class OutlineItem {
        enum Kind {
            case node(FileNode)
            /// explorer R8: the "… and N more" row of a truncated folder.
            case more(folder: String, count: Int)
        }

        let kind: Kind

        init(_ kind: Kind) {
            self.kind = kind
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        private let model: ExplorerModel
        private let onOpen: (FileNode, ExplorerOpenMode) -> Void
        private let operations: ExplorerActions
        private var items: [String: OutlineItem] = [:]
        private var reveal: Task<Void, Never>?
        private var moreItems: [String: OutlineItem] = [:]
        private var version = -1
        private var hidesExcluded: Bool

        init(model: ExplorerModel, onOpen: @escaping (FileNode, ExplorerOpenMode) -> Void, operations: ExplorerActions)
        {
            self.model = model
            self.onOpen = onOpen
            self.operations = operations
            hidesExcluded = model.hidesExcluded
        }

        /// explorer R12, R13: a click opens a preview; with `opt`, in a new group on the right.
        @objc func clicked() {
            guard let node = clickedFile() else { return }
            let isOption = NSApp.currentEvent?.modifierFlags.contains(.option) == true
            onOpen(node, isOption ? .newGroup : .preview)
        }

        /// explorer R12: a double click pins the tab.
        @objc func doubleClicked() {
            guard let node = clickedFile() else { return }
            onOpen(node, .pinned)
        }

        /// explorer R21: `space` previews, `cmd+↓` opens pinned, `enter` renames, `cmd+delete`
        /// deletes; anything else is the outline's.
        func handle(_ key: KeyboardOutlineView.Key) -> Bool {
            guard let outline, outline.selectedRow >= 0 else { return false }
            switch key {
            case .space:
                guard let node = file(atRow: outline.selectedRow) else { return false }
                onOpen(node, .preview)
            case .commandDown:
                guard let node = file(atRow: outline.selectedRow) else { return false }
                onOpen(node, .pinned)
            case .enter:
                guard node(atRow: outline.selectedRow) != nil else { return false }
                outline.editColumn(0, row: outline.selectedRow, with: nil, select: true)
            case .commandDelete:
                guard let node = node(atRow: outline.selectedRow) else { return false }
                operations.delete(node)
            }
            return true
        }

        /// explorer R17: the cell's inline editor ended with a new name.
        @objc func renamed(_ sender: NSTextField) {
            guard let outline else { return }
            let row = outline.row(for: sender)
            guard row >= 0, let node = node(atRow: row) else { return }
            let name = sender.stringValue.trimmingCharacters(in: .whitespaces)
            sender.stringValue = node.name
            guard !name.isEmpty else { return }
            operations.rename(node, to: name)
        }

        private func node(atRow row: Int) -> FileNode? {
            guard let outline, let item = outline.item(atRow: row) as? OutlineItem, case .node(let node) = item.kind
            else { return nil }
            return node
        }

        // MARK: - NSMenuDelegate (explorer R20)

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let clicked = outline.flatMap { $0.clickedRow >= 0 ? node(atRow: $0.clickedRow) : nil }
            menu.addItem(withTitle: "New File", action: #selector(menuNewFile), keyEquivalent: "").target = self
            menu.addItem(withTitle: "New Folder", action: #selector(menuNewFolder), keyEquivalent: "").target = self
            guard clicked != nil else { return }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Rename", action: #selector(menuRename), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move to Trash", action: #selector(menuDelete), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Reveal in Finder", action: #selector(menuReveal), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Copy Path", action: #selector(menuCopyPath), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Copy Absolute Path", action: #selector(menuCopyAbsolutePath), keyEquivalent: "")
                .target = self
            if operations.fileHistory != nil, clicked?.kind == .file {
                menu.addItem(.separator())
                menu.addItem(withTitle: "Git History", action: #selector(menuHistory), keyEquivalent: "").target = self
            }
        }

        private var clickedNode: FileNode? {
            guard let outline, outline.clickedRow >= 0 else { return nil }
            return node(atRow: outline.clickedRow)
        }

        @objc private func menuNewFile() { operations.newFile(near: clickedNode) }
        @objc private func menuNewFolder() { operations.newFolder(near: clickedNode) }
        @objc private func menuRename() {
            guard let outline, outline.clickedRow >= 0 else { return }
            outline.editColumn(0, row: outline.clickedRow, with: nil, select: true)
        }
        @objc private func menuDelete() { clickedNode.map { operations.delete($0) } }
        @objc private func menuReveal() { clickedNode.map { operations.revealInFinder($0) } }
        @objc private func menuHistory() { clickedNode.map { operations.showHistory($0) } }
        @objc private func menuCopyPath() { clickedNode.map { operations.copyPath($0, absolute: false) } }
        @objc private func menuCopyAbsolutePath() { clickedNode.map { operations.copyPath($0, absolute: true) } }

        /// explorer R14: expands the folders down to `path` and selects it, scrolling only when
        /// it is not already visible.
        func reveal(_ path: String) {
            guard let folders = ExplorerModel.foldersToExpand(toReach: path) else { return }
            reveal?.cancel()
            reveal = Task { [weak self] in
                for folder in folders {
                    guard let self, !Task.isCancelled else { return }
                    if model.level(folder) == nil {
                        await model.load(folder)
                    }
                    guard let item = items[folder] else { return }
                    outline?.expandItem(item)
                }
                guard let self, let outline, let item = items[path] else { return }
                let row = outline.row(forItem: item)
                guard row >= 0 else { return }
                outline.selectRowIndexes([row], byExtendingSelection: false)
                if !outline.visibleRect.contains(outline.rect(ofRow: row)) {
                    outline.scrollRowToVisible(row)
                }
            }
        }

        private func clickedFile() -> FileNode? {
            guard let outline, outline.clickedRow >= 0 else { return nil }
            return file(atRow: outline.clickedRow)
        }

        private func file(atRow row: Int) -> FileNode? {
            guard let outline, let item = outline.item(atRow: row) as? OutlineItem, case .node(let node) = item.kind,
                !node.isExpandable, node.kind != .directory
            else { return nil }
            return node
        }

        func sync(version: Int, hidesExcluded: Bool) {
            guard let outline else { return }
            if hidesExcluded != self.hidesExcluded {
                self.hidesExcluded = hidesExcluded
                self.version = version
                outline.reloadData()
                restoreExpansion(under: "")
                return
            }
            guard version != self.version else { return }
            // Several levels may have changed since the last update (explorer R9, a burst):
            // then everything is reloaded; items keep their identity so nothing is lost (R10).
            let path = version - self.version == 1 ? model.lastLoaded ?? "" : ""
            self.version = version
            outline.reloadItem(path.isEmpty ? nil : items[path], reloadChildren: true)
            restoreExpansion(under: path)
        }

        /// explorer R11: the persisted folders open once their parent is read.
        private func restoreExpansion(under folder: String) {
            guard let outline, let children = model.children(of: folder) else { return }
            for node in children where model.isRestoredExpanded(node) {
                outline.expandItem(item(for: node))
            }
        }

        private func item(for node: FileNode) -> OutlineItem {
            if let item = items[node.id], case .node(let existing) = item.kind, existing == node {
                return item
            }
            let item = OutlineItem(.node(node))
            items[node.id] = item
            return item
        }

        private func moreItem(folder: String, count: Int) -> OutlineItem {
            if let item = moreItems[folder], case .more(_, let existing) = item.kind, existing == count {
                return item
            }
            let item = OutlineItem(.more(folder: folder, count: count))
            moreItems[folder] = item
            return item
        }

        private func path(of item: Any?) -> String? {
            guard let item = item as? OutlineItem else { return "" }
            guard case .node(let node) = item.kind else { return nil }
            return node.id
        }

        private func rows(of folder: String) -> [OutlineItem] {
            guard let level = model.level(folder) else { return [] }
            var rows = level.visibleNodes(hidingExcluded: hidesExcluded).map(item(for:))
            if level.truncatedCount > 0 {
                rows.append(moreItem(folder: folder, count: level.truncatedCount))
            }
            return rows
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            path(of: item).map { rows(of: $0).count } ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            rows(of: path(of: item) ?? "")[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem, case .node(let node) = item.kind else { return false }
            return node.isExpandable
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? OutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("cell")
            let cell =
                outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier)
            switch item.kind {
            case .node(let node):
                cell.textField?.isEditable = true
                cell.textField?.stringValue = node.name
                cell.textField?.textColor = node.isExcluded ? .tertiaryLabelColor : .labelColor
                cell.imageView?.image = NSImage(systemSymbolName: Self.symbol(for: node), accessibilityDescription: nil)
                cell.imageView?.contentTintColor = node.isExcluded ? .tertiaryLabelColor : .secondaryLabelColor
            case .more(_, let count):
                cell.textField?.isEditable = false
                cell.textField?.stringValue = "… and \(count) more (click to load all)"
                cell.textField?.textColor = .secondaryLabelColor
                cell.imageView?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
                cell.imageView?.contentTintColor = .secondaryLabelColor
            }
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            switch item.kind {
            case .node:
                return true
            case .more(let folder, _):
                Task { await model.load(folder, all: true) }
                return false
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outline else { return }
            model.selection = path(of: outline.item(atRow: outline.selectedRow))
        }

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let path = expandedPath(notification) else { return }
            // explorer R7: read at the first expansion, and only then.
            if model.level(path) == nil {
                Task { await model.load(path) }
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let path = expandedPath(notification) else { return }
            model.setExpanded(path, true)
            restoreExpansion(under: path)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let path = expandedPath(notification) else { return }
            model.setExpanded(path, false)
            // explorer R9: a collapsed folder is read again at its next expansion.
            model.forget(path)
        }

        private func expandedPath(_ notification: Notification) -> String? {
            path(of: notification.userInfo?["NSObject"])
        }

        private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            // explorer R17: the label doubles as the inline rename editor.
            text.isBezeled = false
            text.drawsBackground = false
            text.target = self
            text.action = #selector(renamed(_:))
            text.lineBreakMode = .byTruncatingMiddle
            text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private static func symbol(for node: FileNode) -> String {
            if node.isUnreadable {
                return "lock"
            }
            switch node.kind {
            case .file:
                return "doc"
            case .directory:
                return "folder"
            case .symlink:
                return "link"
            }
        }
    }
}

/// `NSOutlineView` that hands a few keys to its owner (explorer R21) before its own handling.
final class KeyboardOutlineView: NSOutlineView {
    enum Key {
        case space
        case commandDown
        case enter
        case commandDelete
    }

    var onKey: (Key) -> Bool = { _ in false }

    override func keyDown(with event: NSEvent) {
        let key: Key?
        if event.charactersIgnoringModifiers == " ",
            event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        {
            key = .space
        } else if event.keyCode == 125, event.modifierFlags.contains(.command) {
            key = .commandDown
        } else if event.keyCode == 36 || event.keyCode == 76 {
            key = .enter
        } else if event.keyCode == 51, event.modifierFlags.contains(.command) {
            key = .commandDelete
        } else {
            key = nil
        }
        if let key, onKey(key) {
            return
        }
        super.keyDown(with: event)
    }
}
