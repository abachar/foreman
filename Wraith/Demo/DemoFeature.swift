import SwiftUI

/// M0 only: a text tab, three panels and a toolbar item to exercise the layout end to end.
///
/// Removed at the start of M1, with everything under `Demo/`.
@MainActor
enum DemoFeature {
    static let tabKind = "demo.hello"

    static func register(in layout: LayoutManager) {
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: tabKind,
                makeView: { _, payload in AnyView(HelloTabView(title: payload)) },
                serialize: { id in
                    layout.model.owner(of: id).flatMap { layout.model[group: $0]?.tabs.first { $0.id == id }?.title }
                }
            ))
        layout.shortcuts.register(
            ShortcutAction(id: "demo.hello.open", title: "New Hello Tab", defaultShortcut: "cmd+n") {
                openHello(in: layout)
            })
        layout.register(
            homeEntry: HomeEntry(id: "demo.hello.open", title: "New Hello Tab", icon: "hand.wave", section: .actions) {
                openHello(in: layout)
            })
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: "demo.hello", title: "Hello", icon: "hand.wave", placement: .leading,
                kind: .action(
                    perform: { openHello(in: layout) },
                    secondaryMenu: {
                        [
                            ToolbarMenuEntry(id: "demo.badge.on", title: "Badge on", badge: .dot(.green)) {
                                layout.setBadge(.dot(.green), on: "demo.hello")
                            },
                            ToolbarMenuEntry(id: "demo.badge.off", title: "Badge off") {
                                layout.setBadge(.none, on: "demo.hello")
                            },
                        ]
                    })))
        for (side, number) in [(PanelSide.left, 1), (.right, 2), (.bottom, 3)] {
            layout.register(
                panel: PanelDescriptor(
                    id: PanelID("demo.\(side.rawValue)"), title: "Demo \(side.rawValue)", side: side,
                    defaultShortcut: "cmd+shift+\(number)",
                    makeView: { AnyView(DemoPanelView(side: side)) }))
        }
    }

    private static var count = 0

    private static func openHello(in layout: LayoutManager) {
        count += 1
        layout.openTab(kind: tabKind, title: "Hello \(count)", payload: "Hello \(count)")
    }
}

private struct HelloTabView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DemoPanelView: View {
    let side: PanelSide
    @State private var counter = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Panel \(side.rawValue)")
                .font(.headline)
            // Local state survives hide and show: the view is kept (layout R4, R5).
            Button("Clicked \(counter)") { counter += 1 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
