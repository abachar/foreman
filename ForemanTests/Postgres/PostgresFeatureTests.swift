import Foundation
import Testing

@testable import Foreman

/// postgres R4: the feature owns the window's connection, so what it keeps alive matters.
@MainActor
struct PostgresFeatureTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PostgresFeatureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFeature(root: URL) -> PostgresFeature {
        let theme = ThemeService()
        return PostgresFeature(
            layout: LayoutManager(),
            workspace: Workspace(root: root, globalConfigFile: root.appending(path: "no-global.json")),
            secrets: .inMemory(), theme: theme, highlighter: Highlighter(theme: theme))
    }

    /// R4: closing the connection happens in the feature's `deinit`, which only runs if nothing
    /// keeps the feature alive — the schema model holds it weakly.
    @Test func aReleasedFeatureAndItsSchemaModelDeallocate() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        weak var weakFeature: PostgresFeature?
        weak var weakSchema: PostgresSchemaModel?
        var feature: PostgresFeature? = makeFeature(root: root)
        weakFeature = feature
        weakSchema = feature?.schema
        #expect(weakSchema != nil)
        feature = nil
        #expect(weakFeature == nil)
        #expect(weakSchema == nil)
    }
}
