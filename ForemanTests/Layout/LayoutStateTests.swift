import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Foreman

/// Persistence of the layout (layout R27–R29): roundtrip, unknown kinds, restoration order.
@MainActor
struct LayoutStateTests {
    private final class Probe {
        var activations: [String] = []
    }

    private let probe = Probe()

    private func manager(kinds: [String]) -> LayoutManager {
        let layout = LayoutManager()
        for kind in kinds {
            layout.register(
                tabKind: CenterTabDescriptor(
                    kind: kind,
                    makeView: { _, payload in payload == "refuse" ? nil : AnyView(Text(payload)) },
                    serialize: { _ in "payload" }))
        }
        layout.register(
            panel: PanelDescriptor(
                id: "git.status", title: "Git", side: .left,
                makeView: { AnyView(EmptyView()) },
                activate: { [probe] in probe.activations.append("+git") }))
        return layout
    }

    @Test func roundtripsThroughJSON() throws {
        let layout = manager(kinds: ["demo.hello"])
        layout.openTab(kind: "demo.hello", title: "one", payload: "1")
        layout.openTab(kind: "demo.hello", title: "two", payload: "2")
        layout.split(.vertical)
        layout.openTab(kind: "demo.hello", title: "three", payload: "3")
        layout.panels.toggle("git.status")
        layout.setPanelSize(300, for: .left)
        layout.windowFrame = CGRect(x: 10, y: 20, width: 1200, height: 800)
        layout.isToolbarVisible = false
        let snapshot = layout.snapshot()

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        let restored = manager(kinds: ["demo.hello"])
        restored.restore(decoded)

        #expect(decoded == snapshot)
        #expect(restored.snapshot() == snapshot)
        #expect(restored.model.tree.groups.count == 2)
        #expect(restored.model.active.active?.title == "three")
        #expect(restored.panels.visible == [.left: "git.status"])
        #expect(restored.panelSizes["git.status"] == 300)
        #expect(restored.requestedSizes[.left] == 300)
        #expect(!restored.isToolbarVisible)
    }

    @Test func ignoresUnknownKindsAndFoldsTheEmptiedGroup() throws {
        let source = manager(kinds: ["demo.hello", "editor.file"])
        source.openTab(kind: "demo.hello", title: "kept", payload: "1")
        source.split(.vertical)
        source.openTab(kind: "editor.file", title: "gone", payload: "x")
        let snapshot = source.snapshot()

        let restored = manager(kinds: ["demo.hello"])
        restored.restore(snapshot)

        #expect(restored.model.tree.groups.count == 1)
        #expect(restored.model.active.tabs.map(\.title) == ["kept"])
    }

    @Test func eachPanelOfASlotKeepsItsOwnSize() throws {
        let layout = manager(kinds: [])
        layout.register(
            panel: PanelDescriptor(
                id: "postgres.schema", title: "Schema", side: .left, makeView: { AnyView(EmptyView()) }))
        layout.panels.toggle("git.status")
        layout.setPanelSize(300, for: .left)
        layout.panels.toggle("postgres.schema")
        // layout R18 (2026-08-28): the replacing panel starts at the slot's default, not at 300.
        #expect(layout.requestedSizes[.left] == ZoneSizing.defaults[.left])
        layout.setPanelSize(420, for: .left)
        layout.panels.toggle("git.status")
        #expect(layout.requestedSizes[.left] == 300)

        let data = try JSONEncoder().encode(layout.snapshot())
        // layout R18: an object keyed by panel id, readable by hand in state.json.
        #expect(String(decoding: data, as: UTF8.self).contains(#""git.status":300"#))
        let restored = manager(kinds: [])
        restored.restore(try JSONDecoder().decode(LayoutState.self, from: data))
        // The schema panel is unknown to this window: its size is dropped, git's stays.
        #expect(restored.panelSizes == ["git.status": 300])
    }

    @Test func keepsTheLastGroupEvenWhenEveryTabIsIgnored() {
        let source = manager(kinds: ["editor.file"])
        source.openTab(kind: "editor.file", title: "gone", payload: "x")

        let restored = manager(kinds: ["demo.hello"])
        restored.restore(source.snapshot())

        #expect(restored.model.tree.groups.count == 1)
        #expect(restored.model.active.isEmpty)
    }

    @Test func aTabItsFeatureRefusesIsIgnored() {
        let source = manager(kinds: ["demo.hello"])
        source.openTab(kind: "demo.hello", title: "ok", payload: "1")
        var snapshot = source.snapshot()
        snapshot.groups = [
            LayoutState.GroupState(
                id: snapshot.groups[0].id,
                tabs: snapshot.groups[0].tabs + [
                    LayoutState.TabState(id: TabID(), kind: "demo.hello", title: "no", payload: "refuse")
                ],
                activeTab: snapshot.groups[0].activeTab)
        ]

        let restored = manager(kinds: ["demo.hello"])
        restored.restore(snapshot)

        #expect(restored.model.active.tabs.map(\.title) == ["ok"])
    }

    @Test func activatesRestoredPanelsOnlyAfterTheFirstFrame() {
        let source = manager(kinds: [])
        source.panels.toggle("git.status")
        let restored = manager(kinds: [])

        restored.restore(source.snapshot())
        #expect(restored.panels.visible == [.left: "git.status"])
        #expect(probe.activations == ["+git"])
        #expect(restored.panels.focus == .center)

        restored.panels.activateVisible()
        #expect(probe.activations == ["+git", "+git"])
    }

    @Test func recentersAFrameOffEveryScreen() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let onScreen = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let offScreen = CGRect(x: 5000, y: 100, width: 3000, height: 700)

        #expect(LayoutManager.frameToRestore(onScreen, screens: [main], main: main) == onScreen)
        #expect(
            LayoutManager.frameToRestore(offScreen, screens: [main], main: main)
                == CGRect(x: 0, y: 190, width: 1920, height: 700))
    }
}
