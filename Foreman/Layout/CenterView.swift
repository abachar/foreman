import SwiftUI

/// The center zone: the split tree rendered with equal shares (layout R8), one `TabGroupView`
/// per leaf (product R3).
struct CenterView: View {
    let layout: LayoutManager
    let theme: ThemeService

    var body: some View {
        node(layout.model.tree)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                layout.centerSize = $0
            }
    }

    private func node(_ node: LayoutNode) -> AnyView {
        switch node {
        case .group(let id):
            return AnyView(TabGroupView(layout: layout, theme: theme, groupID: id))
        case .split(.vertical, let first, let second):
            // design R21: a 1 pt line inside the island, no inner gutter.
            return AnyView(
                HStack(spacing: 0) {
                    self.node(first)
                    theme.tokens.separator.color.frame(width: 1)
                    self.node(second)
                })
        case .split(.horizontal, let first, let second):
            return AnyView(
                VStack(spacing: 0) {
                    self.node(first)
                    theme.tokens.separator.color.frame(height: 1)
                    self.node(second)
                })
        }
    }
}

/// One tab group: its tab bar and the active tab, or the home screen when empty (layout R33).
struct TabGroupView: View {
    let layout: LayoutManager
    let theme: ThemeService
    let groupID: GroupID

    var body: some View {
        let group = layout.model[group: groupID] ?? TabGroup(id: groupID)
        let isActive = layout.model.activeGroup == groupID
        let tokens = theme.tokens
        VStack(spacing: 0) {
            if !group.isEmpty {
                TabBarView(layout: layout, theme: theme, group: group, isActiveGroup: isActive)
                // design R16: a thin separator under the bar only.
                tokens.separator.color.frame(height: 1)
            }
            content(of: group)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // layout R17, design R3 (amended 2026-10-16): no stroke around the active group any more;
        // its active tab's accent rule says which group is active (`TabButton`).
        .contentShape(Rectangle())
        .onTapGesture {
            layout.activateGroup(groupID)
        }
    }

    @ViewBuilder
    private func content(of group: TabGroup) -> some View {
        if let tab = group.active, let view = layout.view(for: tab) {
            // Two tabs of the same kind have the same view structure: without an identity SwiftUI
            // keeps the previous tab's native views (an `NSTextView` kept showing the last file
            // opened, 2026-08-28). The id makes a switch a rebuild, as it is meant to be.
            view.id(tab.id)
        } else {
            HomeView(layout: layout, theme: theme, groupID: groupID)
        }
    }
}

/// layout R16: one component, scrollable, active tab kept visible, tabs never under a minimum width.
struct TabBarView: View {
    let layout: LayoutManager
    let theme: ThemeService
    let group: TabGroup
    let isActiveGroup: Bool

    /// layout R38: the width the bar has, so the empty part after the tabs is a view of its own.
    @State private var width: CGFloat = 0

    var body: some View {
        let tokens = theme.tokens
        HStack(spacing: 0) {
            tabs
            trailingButtons
        }
        .frame(height: tokens.barHeight)
        // design R16 (amended 2026-10-16, view 02): the bar lies on the island's own surface.
        .background(tokens.surface.color)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }

    /// layout R16 (amended 2026-10-17, M22 22.3, view 02): *Split Right* and the *…* menu at the
    /// right end of the bar, acting on this group.
    private var trailingButtons: some View {
        let tokens = theme.tokens
        let active = group.activeTab
        return HStack(spacing: 2) {
            Button {
                layout.activateGroup(group.id)
                layout.split(.vertical)
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.tabs.count < 2)
            .help(Self.help("Split Right", layout.shortcuts.shortcut(for: "layout.split.vertical")))
            Menu {
                ForEach(Self.moreEntries(group), id: \.title) { entry in
                    Button(entry.title) {
                        guard let active else { return }
                        layout.activateGroup(group.id)
                        switch entry.action {
                        case .close: Task { await layout.closeTab(active) }
                        case .closeTabs(let selection): Task { await layout.closeTabs(selection, around: active) }
                        case .split(let orientation): layout.split(orientation)
                        }
                    }
                    .disabled(!entry.isEnabled)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .foregroundStyle(tokens.textSecondary.color)
        .padding(.horizontal, 6)
    }

    /// One entry of the *…* menu.
    struct MoreEntry: Equatable {
        enum Action: Equatable {
            case close
            case closeTabs(TabCloseSelection)
            case split(SplitOrientation)
        }

        let title: String
        let action: Action
        let isEnabled: Bool
    }

    /// layout R16 (amended 2026-10-17): the *…* menu around the group's active tab — the closing
    /// entries of the tab menu (R35), then the two splits (R9: two tabs at least).
    static func moreEntries(_ group: TabGroup) -> [MoreEntry] {
        guard let active = group.activeTab else { return [] }
        let canSplit = group.tabs.count > 1
        return [MoreEntry(title: "Close", action: .close, isEnabled: true)]
            + TabCloseSelection.allCases.map { selection in
                MoreEntry(
                    title: selection.title, action: .closeTabs(selection),
                    isEnabled: !group.tabs(toClose: selection, around: active).isEmpty)
            }
            + [
                MoreEntry(title: "Split Right", action: .split(.vertical), isEnabled: canSplit),
                MoreEntry(title: "Split Down", action: .split(.horizontal), isEnabled: canSplit),
            ]
    }

    private static func help(_ title: String, _ shortcut: Shortcut?) -> String {
        shortcut.map { "\(title) (\($0))" } ?? title
    }

    private var tabs: some View {
        let tokens = theme.tokens
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(group.tabs) { tab in
                        TabButton(
                            tab: tab, tokens: tokens, font: theme.font(), measuringFont: theme.interfaceFont(),
                            closeFont: theme.font(.small),
                            // editor R63: a library tab's title ends in the jar; the icon is the file's.
                            icon: layout.tabKinds[tab.kind]?.showsFileIcon == true
                                ? FileIcon.image(named: FileIcon.name(for: tab.title.components(separatedBy: " — ")[0]))
                                : nil,
                            isActive: tab.id == group.activeTab,
                            isActiveGroup: isActiveGroup,
                            activate: { layout.activate(tab.id, in: group.id) },
                            close: { Task { await layout.closeTab(tab.id) } }
                        )
                        .id(tab.id)
                        // layout R35, R37: the native menu, each entry with its shortcut; an
                        // entry with nothing to close is disabled.
                        .contextMenu {
                            let close = layout.shortcuts.shortcut(for: "layout.tab.close")
                            Button("Close") { Task { await layout.closeTab(tab.id) } }
                                .modifier(MenuShortcut(close))
                            ForEach(TabCloseSelection.allCases, id: \.self) { selection in
                                Button(selection.title) { Task { await layout.closeTabs(selection, around: tab.id) } }
                                    .disabled(group.tabs(toClose: selection, around: tab.id).isEmpty)
                            }
                            // agents R5b: what the tab's owner adds.
                            let owned = layout.tabKinds[tab.kind]?.contextMenu(tab.id) ?? []
                            if !owned.isEmpty {
                                Divider()
                                ForEach(owned) { entry in
                                    Button(entry.title, action: entry.perform)
                                }
                            }
                        }
                    }
                    // layout R38: the empty part of the bar. It is a sibling of the tabs, not a
                    // layer under them, so a double click on a tab can never reach it.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { layout.newTab(in: group.id) }
                        .onTapGesture { layout.activateGroup(group.id) }
                }
                // Without a minimum the row is exactly as wide as its tabs and there is no empty
                // part to click; with it, `Color.clear` takes the slack the tabs leave.
                .frame(minWidth: width, alignment: .leading)
            }
            .onChange(of: group.activeTab, initial: true) { _, active in
                guard let active else { return }
                proxy.scrollTo(active)
            }
        }
    }
}

/// layout R37: writes a shortcut next to a menu entry.
///
/// Shown, never bound: the content of a `contextMenu` only exists while the menu is open, and the
/// registry's monitor takes the event first anyway.
private struct MenuShortcut: ViewModifier {
    let shortcut: Shortcut?

    init(_ shortcut: Shortcut?) {
        self.shortcut = shortcut
    }

    func body(content: Content) -> some View {
        if let shortcut, let key = shortcut.keyEquivalent.key.first {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: EventModifiers(shortcut.modifiers))
        } else {
            content
        }
    }
}

extension EventModifiers {
    /// layout R37: the SwiftUI side of `Shortcut.Modifiers`.
    init(_ modifiers: Shortcut.Modifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}

/// design R5, R16: a flat rectangle; active = the island's surface and a 2 pt accent rule on its
/// bottom edge — grey in a group that is not the active one (amended 2026-10-16); the close
/// button under the mouse, and always on the active tab of the active group (view 02).
struct TabButton: View {
    let tab: Tab
    let tokens: ThemeService.Tokens
    let font: Font
    /// The same font as `font`, to measure the title with (layout R16 amended 2026-10-17).
    let measuringFont: NSFont
    let closeFont: Font
    /// design R23: the file's type icon.
    let icon: NSImage?
    let isActive: Bool
    let isActiveGroup: Bool
    let activate: () -> Void
    let close: () -> Void

    /// layout R16 (amended 2026-10-17, M22 22.5): the widest a tab's title gets.
    ///
    /// A tab is as wide as its content, its title truncated in the middle past this — so one long
    /// name cannot take the whole bar (audit L7) and a short one leaves no empty band.
    static let maximumTitleWidth: CGFloat = 180

    /// The title's width: what the font needs, a point of slack for the italic of a preview, up
    /// to `maximum`.
    static func titleWidth(_ title: String, font: NSFont, maximum: CGFloat = maximumTitleWidth) -> CGFloat {
        min((title as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 2, maximum)
    }

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
            }
            // terminal R7: the owner's mark; a running process is dirty (terminal R10) but the
            // dot says it already.
            if case .dot(let color) = tab.badge {
                Circle()
                    .fill(tokens.status(color).color)
                    .frame(width: 7, height: 7)
            }
            let title = tab.title + (tab.isDirty && tab.badge == .none ? " •" : "")
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(font)
                .frame(width: Self.titleWidth(title, font: measuringFont), alignment: .leading)
                .italic(tab.isPreview)
                .foregroundStyle(isActive && isActiveGroup ? tokens.textPrimary.color : tokens.textSecondary.color)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(closeFont)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tokens.textSecondary.color)
            .opacity(isHovered || (isActive && isActiveGroup) ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .help(tab.title)
        .background(isActive ? tokens.surface.color : .clear)
        .overlay(alignment: .bottom) {
            (isActive ? (isActiveGroup ? tokens.accent : tokens.textDisabled).color : .clear).frame(height: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: activate)
    }
}
