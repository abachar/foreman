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
        .overlay {
            // layout R17, design R3: the active group is the only thing carrying the accent; a lone
            // group has nothing to be told apart from, and the stroke follows the island's corners
            // (decision 2026-08-27).
            let isMarked = isActive && layout.model.groups.count > 1
            RoundedRectangle(cornerRadius: tokens.islandRadius)
                .strokeBorder(isMarked ? tokens.accent.color : .clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(group.tabs) { tab in
                        TabButton(
                            tab: tab, tokens: tokens, font: theme.font(), closeFont: theme.font(.small),
                            icon: layout.tabKinds[tab.kind]?.showsFileIcon == true
                                ? FileIcon.image(named: FileIcon.name(for: tab.title)) : nil,
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
        .frame(height: tokens.barHeight)
        .background(tokens.surfaceRaised.color)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
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
/// bottom edge; the close button only under the mouse.
private struct TabButton: View {
    let tab: Tab
    let tokens: ThemeService.Tokens
    let font: Font
    let closeFont: Font
    /// design R23: the file's type icon.
    let icon: NSImage?
    let isActive: Bool
    let isActiveGroup: Bool
    let activate: () -> Void
    let close: () -> Void

    private static let minimumWidth: CGFloat = 120
    /// layout R16: past this a title is truncated, so one long name cannot take the whole bar
    /// and hide every other tab (audit L7).
    private static let maximumWidth: CGFloat = 240

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
            Text(tab.title + (tab.isDirty && tab.badge == .none ? " •" : ""))
                .lineLimit(1)
                .font(font)
                .italic(tab.isPreview)
                .foregroundStyle(isActive && isActiveGroup ? tokens.textPrimary.color : tokens.textSecondary.color)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(closeFont)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tokens.textSecondary.color)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: Self.minimumWidth, maxWidth: Self.maximumWidth, maxHeight: .infinity)
        .background(isActive ? tokens.surface.color : .clear)
        .overlay(alignment: .bottom) {
            (isActive ? tokens.accent.color : .clear).frame(height: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: activate)
    }
}
