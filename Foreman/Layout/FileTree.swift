import AppKit
import SwiftUI

/// One file a tree shows (design R23): where it is, how its name is coloured, what follows it.
nonisolated struct FileTreeEntry: Equatable, Sendable, Identifiable {
    /// Relative, `/`-separated; builds the tree.
    let path: String
    /// The name's colour, as the explorer colours a file (explorer R15); `nil` → the text colour.
    var status: GitFileStatus?
    /// A letter at the end of the row (`M`, `A`, `D`, `R`), in the status colour.
    var mark: String?
    /// Grey text after the name (a rename's origin).
    var detail: String?

    var id: String {
        path
    }

    var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// A row of a tree: a folder or a file.
///
/// A chain of single-child folders is folded into one row (explorer R23, git R6b). A class, so
/// the outline view tracks it by identity.
nonisolated final class FileTreeNode {
    /// The whole chain from the root, `src/main/java` for a folded row.
    let path: String
    /// What the row shows: the name, or `main/java` for a folded chain.
    let label: String
    /// `nil` for a folder.
    let entry: FileTreeEntry?
    fileprivate(set) var children: [FileTreeNode] = []

    init(path: String, label: String, entry: FileTreeEntry?) {
        self.path = path
        self.label = label
        self.entry = entry
    }

    var isFolder: Bool {
        entry == nil
    }

    /// The entries as a tree, folders first then names in `localizedStandardCompare` order
    /// (explorer R2); a folder whose only child is a folder joins it on one row.
    static func build(_ entries: [FileTreeEntry]) -> [FileTreeNode] {
        let root = Folder()
        for entry in entries {
            var folder = root
            for name in entry.path.split(separator: "/").dropLast() {
                folder = folder.child(String(name))
            }
            folder.files.append(entry)
        }
        return nodes(of: root, prefix: "")
    }

    private static func nodes(of folder: Folder, prefix: String) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for name in folder.folders.keys.sorted(by: isBefore) {
            guard var child = folder.folders[name] else { continue }
            var label = name
            while child.files.isEmpty, child.folders.count == 1, let only = child.folders.first {
                label += "/" + only.key
                child = only.value
            }
            let node = FileTreeNode(path: prefix + label, label: label, entry: nil)
            node.children = nodes(of: child, prefix: node.path + "/")
            result.append(node)
        }
        for entry in folder.files.sorted(by: { isBefore($0.path, $1.path) }) {
            result.append(FileTreeNode(path: entry.path, label: entry.name, entry: entry))
        }
        return result
    }

    private static func isBefore(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    /// Only alive while `build` runs.
    private nonisolated final class Folder {
        var folders: [String: Folder] = [:]
        var files: [FileTreeEntry] = []

        func child(_ name: String) -> Folder {
            if let existing = folders[name] {
                return existing
            }
            let folder = Folder()
            folders[name] = folder
            return folder
        }
    }
}

/// What every file tree of the app shares (design R3, R6, R23): the explorer's, the Changes
/// panel's, a commit's — so none of them can drift from the others.
@MainActor
enum FileTreeStyle {
    static let indentation: CGFloat = 12

    /// One column, no header, the theme's row height and ground.
    static func configure(_ outline: NSOutlineView, theme: ThemeService) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        // `.custom`: any other style makes the outline overwrite the cells' font (design R6).
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = indentation
        outline.autoresizesOutlineColumn = true
        // The only column takes the whole width from the first frame (bug: names hidden until
        // the panel was resized).
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAutomaticRowHeights = false
        outline.allowsEmptySelection = true
        outline.autosaveExpandedItems = false
        outline.backgroundColor = theme.tokens.surface.nsColor
        outline.rowHeight = theme.listRowHeight
    }

    /// design R6, R11: `true` when the theme changed under the outline, which then reloads.
    static func refresh(_ outline: NSOutlineView, theme: ThemeService) -> Bool {
        guard outline.backgroundColor != theme.tokens.surface.nsColor || outline.rowHeight != theme.listRowHeight
        else { return false }
        outline.backgroundColor = theme.tokens.surface.nsColor
        outline.rowHeight = theme.listRowHeight
        return true
    }

    /// design R3: the selection on the accent.
    static func rowView(_ outline: NSOutlineView, theme: ThemeService) -> NSTableRowView {
        let row =
            outline.makeView(withIdentifier: TokenRowView.identifier, owner: nil) as? TokenRowView ?? TokenRowView()
        row.identifier = TokenRowView.identifier
        row.tokens = theme.tokens
        return row
    }

    /// The cell of `outline`, reused or made.
    static func cell(in outline: NSOutlineView, theme: ThemeService) -> FileTreeCell {
        outline.makeView(withIdentifier: FileTreeCell.identifier, owner: nil) as? FileTreeCell
            ?? FileTreeCell(theme: theme)
    }

    /// design R23: a file's type icon, a folder open or shut.
    static func icon(file name: String) -> NSImage? {
        FileIcon.image(named: FileIcon.name(for: name))
    }

    static func icon(folderExpanded: Bool) -> NSImage? {
        FileIcon.image(named: FileIcon.folder(isExpanded: folderExpanded))
    }
}

/// An action of a file row: a button on hover, an entry of the context menu.
struct FileTreeAction {
    let title: String
    let symbol: String
    let perform: () -> Void
}

/// The row of every file tree (design R23): the icon, the name, a grey detail, the hover
/// buttons, the mark.
final class FileTreeCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("file-tree-cell")

    let detail = NSTextField(labelWithString: "")
    let mark = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private var actions: [FileTreeAction] = []
    /// No mark, no room taken: the explorer's names run to the edge.
    private var markWidth: NSLayoutConstraint?

    init(theme: ThemeService) {
        super.init(frame: .zero)
        identifier = Self.identifier
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.isBezeled = false
        text.drawsBackground = false
        text.lineBreakMode = .byTruncatingMiddle
        text.font = theme.interfaceFont()
        detail.lineBreakMode = .byTruncatingMiddle
        detail.font = theme.interfaceFont(.small)
        detail.textColor = theme.tokens.textSecondary.nsColor
        mark.font = NSFont.monospacedSystemFont(ofSize: theme.interfaceFont(.small).pointSize, weight: .medium)
        mark.alignment = .center
        buttons.spacing = 2
        buttons.isHidden = true
        for view in [image, text, detail, buttons, mark] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = image
        textField = text
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 6),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: detail.trailingAnchor, constant: 4),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.leadingAnchor.constraint(equalTo: buttons.trailingAnchor, constant: 4),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        markWidth = mark.widthAnchor.constraint(equalToConstant: 0)
        markWidth?.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// A file or a folder of a static tree (Changes, a commit).
    func show(_ node: FileTreeNode, isExpanded: Bool, theme: ThemeService, actions: [FileTreeAction]) {
        let tokens = theme.tokens
        textField?.font = theme.interfaceFont()
        textField?.stringValue = node.label
        imageView?.alphaValue = 1
        guard let entry = node.entry else {
            imageView?.image = FileTreeStyle.icon(folderExpanded: isExpanded)
            textField?.textColor = tokens.textPrimary.nsColor
            setDetail(nil, mark: nil, markColor: nil, actions: [])
            return
        }
        let color = entry.status.map(theme.color(for:)) ?? tokens.textPrimary.nsColor
        textField?.textColor = color
        imageView?.image =
            FileTreeStyle.icon(file: entry.name) ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        imageView?.contentTintColor = color
        setDetail(entry.detail, mark: entry.mark, markColor: color, actions: actions)
    }

    /// The grey detail, the mark and the hover buttons; the explorer uses none of them.
    func setDetail(_ text: String?, mark letter: String?, markColor: NSColor?, actions: [FileTreeAction]) {
        detail.stringValue = text ?? ""
        detail.isHidden = text == nil
        mark.stringValue = letter ?? ""
        mark.isHidden = letter == nil
        markWidth?.constant = letter == nil ? 0 : 14
        mark.textColor = markColor
        self.actions = actions
        for view in buttons.arrangedSubviews {
            view.removeFromSuperview()
        }
        for (index, action) in actions.enumerated() {
            let button = NSButton(
                image: NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title) ?? NSImage(),
                target: self, action: #selector(runAction(_:)))
            button.isBordered = false
            button.tag = index
            button.toolTip = action.title
            buttons.addArrangedSubview(button)
        }
        buttons.isHidden = true
    }

    /// git R7: the actions show on the row under the pointer only.
    func setHovered(_ isHovered: Bool) {
        buttons.isHidden = !isHovered || actions.isEmpty
    }

    @objc private func runAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].perform()
    }
}

/// An outline that says which row the pointer is over (the hover buttons) and passes the scroll
/// wheel up when it is sized to its rows (the Changes panel scrolls, not each tree).
final class FileTreeOutlineView: NSOutlineView {
    var onHover: (Int) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHover(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(-1)
    }
}

/// A scroll view that never scrolls itself: the tree is as tall as its rows, the panel around it
/// scrolls.
final class PassThroughScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// A file tree as tall as its rows, for a list that scrolls around it (the Changes panel).
struct FittedFileTreeView: View {
    let entries: [FileTreeEntry]
    let theme: ThemeService
    let open: (FileTreeEntry, _ pinned: Bool) -> Void
    var actions: (FileTreeEntry) -> [FileTreeAction] = { _ in [] }
    var menu: (FileTreeEntry) -> [FileTreeAction] = { _ in [] }
    @State private var height: CGFloat = 0

    var body: some View {
        FileTreeView(
            entries: entries, theme: theme, font: theme.interfaceFont(), onHeight: { height = $0 }, open: open,
            actions: actions, menu: menu
        )
        .frame(height: height)
    }
}

/// A read-only tree of files (git R6b, R19b): everything open at first, a click on a folder
/// folds it (not persisted), a click on a file selects it, a double click opens it.
struct FileTreeView: NSViewRepresentable {
    let entries: [FileTreeEntry]
    let theme: ThemeService
    /// design R6, R11: read here so a font change re-enters `updateNSView`.
    let font: NSFont
    /// Sized to its rows instead of scrolling; the height is reported on every change.
    var onHeight: ((CGFloat) -> Void)?
    /// A click (`pinned` false) or a double click (`pinned` true) on a file.
    let open: (FileTreeEntry, _ pinned: Bool) -> Void
    /// The buttons a file row shows on hover.
    var actions: (FileTreeEntry) -> [FileTreeAction] = { _ in [] }
    /// The context menu of a file row.
    var menu: (FileTreeEntry) -> [FileTreeAction] = { _ in [] }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = FileTreeOutlineView()
        FileTreeStyle.configure(outline, theme: theme)
        let coordinator = context.coordinator
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.action = #selector(Coordinator.clicked)
        outline.doubleAction = #selector(Coordinator.doubleClicked)
        outline.onHover = { [weak coordinator] row in coordinator?.hover(row) }
        let menu = NSMenu()
        menu.delegate = coordinator
        outline.menu = menu
        coordinator.outline = outline
        let scroll: NSScrollView = onHeight == nil ? NSScrollView() : PassThroughScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = onHeight == nil
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let outline = coordinator.outline else { return }
        let themeChanged = FileTreeStyle.refresh(outline, theme: theme) || coordinator.appliedFont != font
        coordinator.appliedFont = font
        if entries != coordinator.entries || themeChanged {
            coordinator.load(entries)
        }
        outline.sizeLastColumnToFit()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        var parent: FileTreeView?
        var appliedFont: NSFont?
        private(set) var entries: [FileTreeEntry]?
        private var roots: [FileTreeNode] = []
        /// Folded by a click; kept across reloads, never persisted (git R6b).
        private var collapsed: Set<String> = []
        private var hoveredRow = -1

        func load(_ entries: [FileTreeEntry]) {
            guard let outline else { return }
            self.entries = entries
            let selected = (outline.item(atRow: outline.selectedRow) as? FileTreeNode)?.path
            roots = FileTreeNode.build(entries)
            hoveredRow = -1
            outline.reloadData()
            expand(roots)
            if let selected, let row = row(of: selected) {
                outline.selectRowIndexes([row], byExtendingSelection: false)
            }
            reportHeight()
        }

        private func expand(_ nodes: [FileTreeNode]) {
            for node in nodes where node.isFolder && !collapsed.contains(node.path) {
                outline?.expandItem(node)
                expand(node.children)
            }
        }

        private func row(of path: String) -> Int? {
            guard let outline else { return nil }
            return (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? FileTreeNode)?.path == path }
        }

        private func reportHeight() {
            guard let outline, let onHeight = parent?.onHeight else { return }
            let rows = outline.numberOfRows
            let height = rows == 0 ? 0 : outline.rect(ofRow: rows - 1).maxY
            // Never during SwiftUI's own update of the view that asks.
            Task { @MainActor in onHeight(height) }
        }

        private func node(atRow row: Int) -> FileTreeNode? {
            guard let outline, row >= 0 else { return nil }
            return outline.item(atRow: row) as? FileTreeNode
        }

        @objc func clicked() {
            guard let outline, let node = node(atRow: outline.clickedRow) else { return }
            guard let entry = node.entry else {
                // git R6b: a click on a folder folds it.
                if outline.isItemExpanded(node) {
                    outline.collapseItem(node)
                } else {
                    outline.expandItem(node)
                }
                return
            }
            parent?.open(entry, false)
        }

        @objc func doubleClicked() {
            guard let outline, let entry = node(atRow: outline.clickedRow)?.entry else { return }
            parent?.open(entry, true)
        }

        func hover(_ row: Int) {
            guard row != hoveredRow, let outline else { return }
            for old in [hoveredRow, row] where old >= 0 && old < outline.numberOfRows {
                (outline.view(atColumn: 0, row: old, makeIfNecessary: false) as? FileTreeCell)?.setHovered(old == row)
            }
            hoveredRow = row
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? FileTreeNode)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? FileTreeNode)?.children[index] ?? roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileTreeNode)?.isFolder ?? false
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            guard let theme = parent?.theme else { return nil }
            return FileTreeStyle.rowView(outlineView, theme: theme)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileTreeNode, let parent else { return nil }
            let cell = FileTreeStyle.cell(in: outlineView, theme: parent.theme)
            cell.show(
                node, isExpanded: outlineView.isItemExpanded(node), theme: parent.theme,
                actions: node.entry.map(parent.actions) ?? [])
            return cell
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            folded(notification, false)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            folded(notification, true)
        }

        private func folded(_ notification: Notification, _ isCollapsed: Bool) {
            guard let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
            if isCollapsed {
                collapsed.insert(node.path)
            } else {
                collapsed.remove(node.path)
            }
            // design R23: the folder icon opens and shuts.
            outline?.reloadItem(node)
            reportHeight()
        }

        // MARK: - NSMenuDelegate

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, let entry = node(atRow: outline.clickedRow)?.entry, let parent else { return }
            for action in parent.menu(entry) {
                let item = menu.addItem(withTitle: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = MenuAction(action.perform)
            }
        }

        @objc private func menuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuAction)?.perform()
        }

        private final class MenuAction {
            let perform: () -> Void

            init(_ perform: @escaping () -> Void) {
                self.perform = perform
            }
        }
    }
}
