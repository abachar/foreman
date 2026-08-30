import Foundation
import Testing

@testable import Foreman

/// editor R1 (one tab per file per group) and the tab bookkeeping of the feature.
@MainActor
struct EditorFeatureTests {
    @Test func opensOneTabPerFileAndForgetsClosedOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a".utf8).write(to: root.appending(path: "a.txt"))
        try Data("b".utf8).write(to: root.appending(path: "b.txt"))
        let layout = LayoutManager()
        let workspace = Workspace(root: root, globalConfigFile: root.appending(path: "no-global.json"))
        let theme = ThemeService()
        let editor = EditorFeature(
            layout: layout, workspace: workspace, theme: theme, palette: Palette(theme: theme),
            highlighter: Highlighter(theme: theme))

        editor.open(root.appending(path: "a.txt"), preview: false)
        editor.open(root.appending(path: "a.txt"), preview: false)
        #expect(layout.model.active.tabs.count == 1)
        #expect(editor.openTabCount == 1)
        let first = try #require(layout.model.active.active?.id)
        #expect(editor.path(of: first) == "a.txt")

        editor.open(root.appending(path: "b.txt"), preview: true)
        #expect(layout.model.active.tabs.count == 2)
        #expect(layout.model.active.active?.isPreview == true)

        await layout.closeTab(first)
        editor.open(root.appending(path: "b.txt"), preview: false)
        #expect(editor.openTabCount == 1)
        #expect(layout.model.active.active?.isPreview == false)
    }
}
