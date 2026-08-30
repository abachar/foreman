import Foundation
import Testing

@testable import Foreman

/// `state.json`: roundtrip, versioning and `.bak` (config R9), paths (R10), debounce (R8).
struct WorkspaceStateTests {
    private struct Layout: Codable, Equatable {
        var activeTab: String
        var panels: [String]
    }

    private let root: URL
    private let file: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        file = WorkspaceState.file(under: root)
    }

    @Test func isEmptyWithoutAFile() async throws {
        defer { remove() }

        let state = await WorkspaceState.load(root: root)

        #expect(state == .empty)
        #expect(try state.section("layout", as: Layout.self) == nil)
    }

    @Test func roundtripsSectionsThroughTheFile() async throws {
        defer { remove() }
        let layout = Layout(activeTab: "demo.hello", panels: ["git.status"])
        var state = WorkspaceState.empty
        try state.setSection("layout", to: layout)

        try await WorkspaceState.write(state, root: root)
        let loaded = await WorkspaceState.load(root: root)

        #expect(try loaded.section("layout", as: Layout.self) == layout)
        #expect(loaded == state)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"version\" : 1"))
        #expect(text.contains("\"activeTab\" : \"demo.hello\""))
    }

    @Test(arguments: [#"{ "version": 99, "layout": {} }"#, "{ not json", "[1]"])
    func setsAsideAnUnreadableOrUnknownVersionFile(content: String) async throws {
        defer { remove() }
        try write(content)

        let state = await WorkspaceState.load(root: root)

        #expect(state == .empty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        let backup = try String(contentsOf: file.appendingPathExtension("bak"), encoding: .utf8)
        #expect(backup == content)
    }

    @Test func persistsPathsRelativeToTheRootWhenInside() {
        let root = URL(filePath: "/Users/tester/code", directoryHint: .isDirectory)

        #expect(
            Workspace.persistedPath(for: URL(filePath: "/Users/tester/code/src/main.swift"), root: root)
                == "src/main.swift")
        #expect(Workspace.persistedPath(for: URL(filePath: "/Users/tester/code/"), root: root) == "")
        #expect(
            Workspace.persistedPath(for: URL(filePath: "/Users/tester/codex/a"), root: root) == "/Users/tester/codex/a")
        #expect(Workspace.persistedPath(for: URL(filePath: "/etc/hosts"), root: root) == "/etc/hosts")

        #expect(Workspace.url(forPersistedPath: "src/main.swift", root: root) == root.appending(path: "src/main.swift"))
        #expect(Workspace.url(forPersistedPath: "/etc/hosts", root: root) == URL(filePath: "/etc/hosts"))
    }

    @Test @MainActor func writesOnceAfterABurstOfChanges() async throws {
        defer { remove() }
        let workspace = Workspace(
            root: root, stateWriteDelay: .milliseconds(200), globalConfigFile: root.appending(path: "no-global.json"))

        workspace.setState("layout", to: Layout(activeTab: "first", panels: []))
        workspace.setState("layout", to: Layout(activeTab: "second", panels: []))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        try await Task.sleep(for: .milliseconds(400))

        let loaded = await WorkspaceState.load(root: root)
        #expect(try loaded.section("layout", as: Layout.self)?.activeTab == "second")
        #expect(workspace.isStatePersisted)
    }

    @Test @MainActor func flushWritesImmediately() async throws {
        defer { remove() }
        let workspace = Workspace(
            root: root, stateWriteDelay: .seconds(10), globalConfigFile: root.appending(path: "no-global.json"))

        workspace.setState("layout", to: Layout(activeTab: "now", panels: []))
        await workspace.flushState()

        let loaded = await WorkspaceState.load(root: root)
        #expect(try loaded.section("layout", as: Layout.self)?.activeTab == "now")
    }

    @Test @MainActor func reportsAnUnwritableRootOnce() async throws {
        defer { remove() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: root.appending(path: ".foreman"))
        let workspace = Workspace(
            root: root, stateWriteDelay: .zero, globalConfigFile: root.appending(path: "no-global.json"))

        workspace.setState("layout", to: Layout(activeTab: "x", panels: []))
        await workspace.flushState()

        #expect(!workspace.isStatePersisted)
    }

    private func write(_ content: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
    }

    private func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
