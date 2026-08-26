import AppKit
import SwiftUI

/// The tree itself: `NSOutlineView` with a lazy data source (explorer, technical options).
///
/// Items are `OutlineItem`s cached per relative path so the outline view keeps expansion,
/// selection and scroll across reloads (R10). A folder's level is asked to the model at its
/// first expansion (R7); the model's `version` tells this view what to reload.
struct ExplorerOutlineView: NSViewRepresentable {
    let model: ExplorerModel
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 12
        outline.autoresizesOutlineColumn = true
        outline.usesAutomaticRowHeights = false
        outline.allowsEmptySelection = true
        outline.autosaveExpandedItems = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.sync(version: model.version, hidesExcluded: model.hidesExcluded)
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
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outline: NSOutlineView?
        private let model: ExplorerModel
        private var items: [String: OutlineItem] = [:]
        private var moreItems: [String: OutlineItem] = [:]
        private var version = -1
        private var hidesExcluded: Bool

        init(model: ExplorerModel) {
            self.model = model
            hidesExcluded = model.hidesExcluded
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
            self.version = version
            let path = model.lastLoaded ?? ""
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
                cell.textField?.stringValue = node.name
                cell.textField?.textColor = node.isExcluded ? .tertiaryLabelColor : .labelColor
                cell.imageView?.image = NSImage(systemSymbolName: Self.symbol(for: node), accessibilityDescription: nil)
                cell.imageView?.contentTintColor = node.isExcluded ? .tertiaryLabelColor : .secondaryLabelColor
            case .more(_, let count):
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
