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

    /// editor R34: `cmd+s` on an untitled tab names the file, moves the scratch there and leaves an
    /// ordinary file tab behind — title (R5) and path included.
    @Test func savingAnUntitledTabTurnsItIntoAnOrdinaryFileTab() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (layout, editor) = Self.feature(root: root)

        await editor.newFile()
        let id = try #require(layout.model.active.active?.id)
        #expect(editor.path(of: id) == ".foreman/scratches/Untitled")
        #expect(layout.model.active.active?.title == "Untitled")
        // editor R19: a draft is not a file the user opened.
        #expect(editor.recentPaths.isEmpty)

        let scratch = Scratch.folder(root: root).appending(path: "Untitled")
        let destination = root.appending(path: "notes.md")
        #expect(await editor.saveScratch(id, to: destination))
        #expect(editor.path(of: id) == "notes.md")
        #expect(layout.model.active.active?.title == "notes.md")
        #expect(editor.recentPaths == ["notes.md"])
        #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))
    }

    /// editor R34: the scratch goes with the tab it belonged to.
    @Test func closingAnUntitledTabRemovesItsScratch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (layout, editor) = Self.feature(root: root)

        await editor.newFile()
        let id = try #require(layout.model.active.active?.id)
        let scratch = Scratch.folder(root: root).appending(path: "Untitled")
        #expect(FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))

        await layout.closeTab(id)
        #expect(editor.openTabCount == 0)
        // The removal is off the main actor; it is a file deletion, not a second of work.
        for _ in 0..<50 where FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))
        // The folder and its `.gitignore` stay: the next draft reuses them.
        let ignore = Scratch.folder(root: root).appending(path: ".gitignore")
        #expect(FileManager.default.fileExists(atPath: ignore.path(percentEncoded: false)))
    }

    /// layout R38, editor R34: the action exists under its shortcut, and the group the double
    /// click names is the one the untitled tab lands in.
    @Test func newFileIsRegisteredAndOpensInTheGroupAskedFor() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a".utf8).write(to: root.appending(path: "a.txt"))
        try Data("b".utf8).write(to: root.appending(path: "b.txt"))
        let (layout, editor) = Self.feature(root: root)
        #expect(layout.shortcuts.shortcut(for: "editor.newFile")?.description == "cmd+n")

        editor.open(root.appending(path: "a.txt"), preview: false)
        let first = layout.model.activeGroup
        editor.open(root.appending(path: "b.txt"), preview: false, newGroup: true)
        let second = layout.model.activeGroup
        #expect(first != second)

        layout.newTab(in: first)

        // The scratch is created off the main actor before the tab exists.
        for _ in 0..<50 where layout.model[group: first]?.tabs.count == 1 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(layout.model.activeGroup == first)
        #expect(layout.model[group: first]?.tabs.map(\.title) == ["a.txt", "Untitled"])
        #expect(layout.model[group: second]?.tabs.map(\.title) == ["b.txt"])
    }

    private static func feature(root: URL) -> (layout: LayoutManager, editor: EditorFeature) {
        let layout = LayoutManager()
        let workspace = Workspace(root: root, globalConfigFile: root.appending(path: "no-global.json"))
        let theme = ThemeService()
        return (
            layout,
            EditorFeature(
                layout: layout, workspace: workspace, theme: theme, palette: Palette(theme: theme),
                highlighter: Highlighter(theme: theme))
        )
    }
}
