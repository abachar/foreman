import Foundation
import Testing

@testable import Foreman

/// editor R4 (payload), R9 (disk state machine), R19 (recent list).
@MainActor
struct EditorTabTests {
    @Test func payloadRoundtripsAndToleratesOldOnes() throws {
        let payload = EditorTab.Payload(
            path: "src/a.swift", pinned: true, cursor: 12, scroll: 340.5, mode: .preview, previewBlock: 7)
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(EditorTab.Payload.self, from: data) == payload)
        let old = try JSONDecoder().decode(EditorTab.Payload.self, from: Data(#"{"path":"a","pinned":false}"#.utf8))
        #expect(old == EditorTab.Payload(path: "a", pinned: false))
    }

    @Test(arguments: [
        (false, true, true, EditorTab.DiskState?.some(.current)),
        (true, true, true, .some(.modified)),
        (false, false, false, .some(.deleted)),
        (true, false, true, .some(.deleted)),
        (false, true, false, nil),
        (true, true, false, nil),
    ])
    func decidesWhatADiskChangeMeans(isDirty: Bool, exists: Bool, isStale: Bool, expected: EditorTab.DiskState?) {
        #expect(EditorTab.diskAction(isDirty: isDirty, exists: exists, isStale: isStale) == expected)
    }

    @Test func recentListMovesToFrontDedupesAndCaps() {
        var recent: [String] = []
        for index in 0..<60 {
            recent = EditorFeature.pushRecent("f\(index)", into: recent)
        }
        #expect(recent.count == 50)
        #expect(recent.first == "f59")
        recent = EditorFeature.pushRecent("f30", into: recent)
        #expect(recent.first == "f30")
        #expect(recent.count == 50)
        #expect(recent.filter { $0 == "f30" }.count == 1)
    }

    @Test func reloadReplacesTheTextAndClearsDirty() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorTabTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "a.txt")
        try Data("one\n".utf8).write(to: url)
        let tab = EditorTab(path: "a.txt", url: url, isPinned: true)
        await tab.load()
        tab.textDidChange()
        #expect(tab.isDirty)

        try Data("two\n".utf8).write(to: url)
        await tab.reload()

        #expect(!tab.isDirty)
        #expect(tab.document?.text == "two\n")
        #expect(tab.reloadVersion == 1)
        #expect(tab.diskState == .current)
    }

    /// editor R34: a tab is untitled because of where its file is, so the save that moves the file
    /// out of the scratches is all it takes to become an ordinary one — highlighting (R11) included.
    @Test func aSavedScratchTabBecomesAnOrdinaryFileTab() {
        let root = URL(filePath: "/tmp/EditorTabTests")
        let tab = EditorTab(
            path: ".foreman/scratches/Untitled", url: Scratch.folder(root: root).appending(path: "Untitled"),
            isPinned: true)
        #expect(tab.isScratch)
        #expect(tab.language == nil)

        tab.fileRenamed(to: root.appending(path: "docs/notes.md"), path: "docs/notes.md")

        #expect(!tab.isScratch)
        #expect(tab.language == .markdown)
        #expect(tab.url.lastPathComponent == "notes.md")
        #expect(tab.payload.path == "docs/notes.md")
    }

    /// editor R34: the draft reaches disk without the tab losing its unsaved marker — closing it
    /// still asks (layout R15) and `cmd+s` still names it (R8).
    @Test func writingAScratchKeepsTheTabDirty() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EditorTabTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try await Scratch.create(root: root)
        let tab = EditorTab(path: ".foreman/scratches/Untitled", url: url, isPinned: true)
        await tab.load()
        tab.textDidChange()

        await tab.writeScratch()

        #expect(tab.isDirty)
        // editor R9: the write is Foreman's own, so the tab must not see the file as changed.
        #expect(tab.document?.isStale(at: url) == false)
    }
}
