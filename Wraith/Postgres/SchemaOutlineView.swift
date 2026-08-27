import AppKit
import SwiftUI

/// The tree itself (postgres R6–R8): `NSOutlineView` with a lazy data source, like the explorer.
///
/// Items are cached per node id so the outline keeps expansion and selection across reloads; a
/// level is asked to the model at its first expansion (R7).
struct SchemaOutlineView: NSViewRepresentable {
    let model: PostgresSchemaModel
    let feature: PostgresFeature
    let theme: ThemeService

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, feature: feature, theme: theme)
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
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAutomaticRowHeights = false
        outline.allowsEmptySelection = true
        outline.autosaveExpandedItems = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked)
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        outline.backgroundColor = theme.tokens.surface.nsColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let outline = context.coordinator.outline, outline.backgroundColor != theme.tokens.surface.nsColor {
            outline.backgroundColor = theme.tokens.surface.nsColor
            outline.reloadData()
        }
        context.coordinator.sync(version: model.version, filter: model.filter)
        context.coordinator.outline?.sizeLastColumnToFit()
    }

    /// One row; a reference type so the outline view tracks it by identity.
    final class OutlineItem {
        let node: SchemaNode

        init(_ node: SchemaNode) {
            self.node = node
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        private let model: PostgresSchemaModel
        private let feature: PostgresFeature
        private let theme: ThemeService
        private var items: [String: OutlineItem] = [:]
        private var version = -1
        private var filter = ""

        init(model: PostgresSchemaModel, feature: PostgresFeature, theme: ThemeService) {
            self.model = model
            self.feature = feature
            self.theme = theme
        }

        func sync(version: Int, filter: String) {
            guard let outline else { return }
            if filter != self.filter {
                self.filter = filter
                self.version = version
                outline.reloadData()
                if !filter.isEmpty {
                    outline.expandItem(nil, expandChildren: true)
                }
                return
            }
            guard version != self.version else { return }
            let loaded = version - self.version == 1 ? model.lastLoaded : nil
            self.version = version
            if let loaded, loaded != model.root?.id, let item = items[loaded] {
                outline.reloadItem(item, reloadChildren: true)
            } else {
                outline.reloadData()
            }
        }

        private func item(for node: SchemaNode) -> OutlineItem {
            if let item = items[node.id], item.node == node {
                return item
            }
            let item = OutlineItem(node)
            items[node.id] = item
            return item
        }

        private func node(of item: Any?) -> SchemaNode? {
            (item as? OutlineItem)?.node
        }

        private func rows(under item: Any?) -> [SchemaNode] {
            guard let item else { return model.root.map { [$0] } ?? [] }
            guard let node = node(of: item) else { return [] }
            return model.visibleChildren(of: node)
        }

        // MARK: - Actions (R8)

        /// R8, US7: a double click on a relation runs `SELECT * LIMIT 500`.
        @objc func doubleClicked() {
            guard let outline, outline.clickedRow >= 0, let node = node(of: outline.item(atRow: outline.clickedRow))
            else { return }
            feature.selectAll(node)
        }

        private var clickedNode: SchemaNode? {
            guard let outline, outline.clickedRow >= 0 else { return nil }
            return node(of: outline.item(atRow: outline.clickedRow))
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let node = clickedNode else { return }
            if node.qualifiedName != nil {
                menu.addItem(withTitle: "Copy Qualified Name", action: #selector(menuCopyName), keyEquivalent: "")
                    .target = self
                if feature.insertIntoEditor != nil {
                    menu.addItem(withTitle: "Insert Name into Editor", action: #selector(menuInsert), keyEquivalent: "")
                        .target = self
                }
            }
            if SchemaQueries.selectAll(node) != nil, feature.runQuery != nil {
                menu.addItem(withTitle: "SELECT * LIMIT 500", action: #selector(menuSelectAll), keyEquivalent: "")
                    .target = self
            }
            switch node.kind {
            case .relation, .function, .detail:
                menu.addItem(withTitle: "View the DDL", action: #selector(menuDDL), keyEquivalent: "").target = self
            case .database, .schema, .category, .sequence, .type, .section, .column, .truncated:
                break
            }
            if node.isExpandable {
                if menu.items.count > 0 {
                    menu.addItem(.separator())
                }
                menu.addItem(withTitle: "Refresh", action: #selector(menuRefresh), keyEquivalent: "").target = self
            }
        }

        @objc private func menuCopyName() { clickedNode.map { feature.copyQualifiedName($0) } }
        @objc private func menuInsert() { clickedNode.map { feature.insertName($0) } }
        @objc private func menuSelectAll() { clickedNode.map { feature.selectAll($0) } }
        @objc private func menuDDL() {
            guard let node = clickedNode else { return }
            Task { await model.showDDL(of: node) }
        }
        @objc private func menuRefresh() {
            guard let node = clickedNode else { return }
            Task { await model.refresh(node) }
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            rows(under: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            self.item(for: rows(under: item)[index])
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            node(of: item)?.isExpandable ?? false
        }

        // MARK: - NSOutlineViewDelegate

        /// design R3: the selection on the accent.
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row =
                outlineView.makeView(withIdentifier: TokenRowView.identifier, owner: nil) as? TokenRowView
                ?? TokenRowView()
            row.identifier = TokenRowView.identifier
            row.tokens = theme.tokens
            return row
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = node(of: item) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("cell")
            let cell =
                outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier)
            let isLoading = model.loading.contains(node.id)
            let text = NSMutableAttributedString(
                string: node.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: theme.tokens.textPrimary.nsColor,
                ])
            if let subtitle = node.subtitle {
                text.append(
                    NSAttributedString(
                        string: "  " + subtitle,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
                            .foregroundColor: theme.tokens.textSecondary.nsColor,
                        ]))
            }
            cell.textField?.attributedStringValue = text
            cell.textField?.toolTip = node.subtitle ?? node.title
            cell.imageView?.image = NSImage(systemSymbolName: Self.symbol(for: node), accessibilityDescription: nil)
            cell.imageView?.contentTintColor =
                isLoading ? theme.tokens.textDisabled.nsColor : theme.schemaTint(for: node)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let node = node(of: item) else { return false }
            if case .truncated(let parent) = node.kind {
                Task { await model.loadAll(parent: parent) }
                return false
            }
            return true
        }

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let node = node(of: notification.userInfo?["NSObject"]) else { return }
            // R7: read at the first expansion, and only then.
            if model.level(node.id) == nil {
                Task { await model.load(node) }
            }
        }

        private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingTail
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

        private static func symbol(for node: SchemaNode) -> String {
            switch node.kind {
            case .database: return "cylinder"
            case .schema: return "folder"
            case .category(let category, _):
                switch category {
                case .tables: return "tablecells"
                case .views, .materializedViews: return "eye"
                case .functions: return "function"
                case .sequences: return "number"
                case .types: return "t.square"
                }
            case .relation(_, _, let kind):
                switch kind {
                case .table: return "tablecells"
                case .view, .materializedView: return "eye"
                }
            case .function: return "function"
            case .sequence: return "number"
            case .type: return "t.square"
            case .section(let section, _, _, _):
                switch section {
                case .columns: return "list.bullet"
                case .indexes: return "bolt"
                case .constraints: return "checkmark.shield"
                case .incomingForeignKeys: return "arrow.turn.down.left"
                case .definition: return "doc.text"
                }
            case .column(let column): return column.isPrimaryKey ? "key" : "circle"
            case .detail: return "doc.text"
            case .truncated: return "ellipsis"
            }
        }
    }
}
