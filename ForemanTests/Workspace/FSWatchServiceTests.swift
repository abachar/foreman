import Foundation
import Testing

@testable import Foreman

/// FSEvents debounce and hot reload of `config.json` (config R6), on a temporary folder.
struct FSWatchServiceTests {
    private let root: URL

    init() {
        root = WorkspaceFolder.canonical(
            FileManager.default.temporaryDirectory
                .appending(path: "FSWatchServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func coalescesABurstOfWritesIntoOneBatch() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FSWatchService(roots: [root], debounce: .milliseconds(200))
        let changes = await service.changes(under: root)
        // The folder's own creation may still be reported: let it flush before the burst.
        try await Task.sleep(for: .milliseconds(600))

        for name in ["a", "b", "c"] {
            try Data(name.utf8).write(to: root.appending(path: name))
        }

        let batch = try #require(await firstBatch(of: changes) { $0.contains { $0.lastPathComponent == "c" } })
        #expect(Set(batch.map(\.lastPathComponent)) == ["a", "b", "c"])
    }

    @Test func emitsWithinTheMaxDelayUnderASustainedStream() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FSWatchService(roots: [root], debounce: .milliseconds(200), maxDelay: .milliseconds(500))
        let changes = await service.changes(under: root)
        try await Task.sleep(for: .milliseconds(600))

        // Writes closer together than the debounce, for longer than `firstBatch` waits: only the
        // max-delay emit can deliver a batch before the timeout.
        let writer = Task { [root] in
            for index in 0..<80 {
                guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
                try? Data("\(index)".utf8).write(to: root.appending(path: "file"))
            }
        }
        defer { writer.cancel() }

        let batch = await firstBatch(of: changes) { $0.contains { $0.lastPathComponent == "file" } }
        #expect(batch != nil)
    }

    @Test func onlyDeliversChangesUnderTheSubscribedLocation() async throws {
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FSWatchService(roots: [root], debounce: .milliseconds(200))
        let changes = await service.changes(under: root.appending(path: "sub"))
        try await Task.sleep(for: .milliseconds(600))

        try Data("x".utf8).write(to: root.appending(path: "outside"))
        try Data("y".utf8).write(to: root.appending(components: "sub", "inside"))

        let batch = try #require(await firstBatch(of: changes) { $0.contains { $0.lastPathComponent == "inside" } })
        #expect(batch.map(\.lastPathComponent) == ["inside"])
    }

    @Test @MainActor func reloadsTheConfigWhenTheFileChanges() async throws {
        let file = WorkspaceConfig.file(under: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(root: root, globalConfigFile: root.appending(path: "no-global.json"))
        workspace.watchConfig()
        try await Task.sleep(for: .milliseconds(300))

        try Data(#"{ "theme": "dark" }"#.utf8).write(to: file)
        let accepted = try #require(await firstBatch(of: workspace.configChanges()))
        #expect(try accepted.section("theme", as: String.self) == "dark")

        try Data("{ broken".utf8).write(to: file)
        try await Task.sleep(for: .seconds(1))
        #expect(!workspace.configErrors.isEmpty)
        #expect(try workspace.config.section("theme", as: String.self) == "dark")
    }

    /// The first element of `stream` accepted by `where`, or `nil` after five seconds.
    private func firstBatch<T: Sendable>(
        of stream: AsyncStream<T>,
        where accepts: @Sendable @escaping (T) -> Bool = { _ in true }
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                for await batch in stream where accepts(batch) {
                    return batch
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
