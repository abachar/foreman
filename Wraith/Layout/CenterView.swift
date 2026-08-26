import SwiftUI

/// The center zone: the split tree rendered with equal shares (layout R8), one `TabGroupView`
/// per leaf (product R3).
struct CenterView: View {
    let layout: LayoutManager

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
            return AnyView(TabGroupView(layout: layout, groupID: id))
        case .split(.vertical, let first, let second):
            return AnyView(
                HStack(spacing: 0) {
                    self.node(first)
                    Divider()
                    self.node(second)
                })
        case .split(.horizontal, let first, let second):
            return AnyView(
                VStack(spacing: 0) {
                    self.node(first)
                    Divider()
                    self.node(second)
                })
        }
    }
}

/// One tab group: its tab bar and the active tab, or the home screen when empty (layout R33).
struct TabGroupView: View {
    let layout: LayoutManager
    let groupID: GroupID

    var body: some View {
        let group = layout.model[group: groupID] ?? TabGroup(id: groupID)
        let isActive = layout.model.activeGroup == groupID
        VStack(spacing: 0) {
            if !group.isEmpty {
                TabBarView(layout: layout, group: group, isActiveGroup: isActive)
                Divider()
            }
            content(of: group)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // layout R17: the active group is the one commands apply to; it is marked.
            Rectangle()
                .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
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
            view
        } else {
            HomeView(layout: layout)
        }
    }
}

/// layout R16: one component, scrollable, active tab kept visible, tabs never under a minimum width.
struct TabBarView: View {
    let layout: LayoutManager
    let group: TabGroup
    let isActiveGroup: Bool

    private let minimumTabWidth: CGFloat = 120

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(group.tabs) { tab in
                        tabButton(tab)
                            .id(tab.id)
                    }
                }
            }
            .onChange(of: group.activeTab, initial: true) { _, active in
                guard let active else { return }
                proxy.scrollTo(active)
            }
        }
        .frame(height: 30)
        .background(.bar)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isActive = tab.id == group.activeTab
        return HStack(spacing: 6) {
            Text(tab.title + (tab.isDirty ? " •" : ""))
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(isActive && isActiveGroup ? .primary : .secondary)
            Button {
                Task { await layout.closeTab(tab.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: minimumTabWidth, maxHeight: .infinity)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            layout.activate(tab.id, in: group.id)
        }
    }
}
