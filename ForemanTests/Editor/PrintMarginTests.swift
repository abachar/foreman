import AppKit
import Foundation
import Testing

@testable import Foreman

/// The print margin (editor R53, M21 21.8): its key and where its line goes.
struct PrintMarginTests {
    private func margin(_ json: String) async throws -> Int? {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "foreman-margin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = WorkspaceConfig.file(under: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: file, atomically: true, encoding: .utf8)
        return EditorFeature.Settings.printMargin(in: try await WorkspaceConfig.load(root: root))
    }

    @Test func theKeyDefaultsTo120AndZeroTurnsItOff() async throws {
        #expect(try await margin("{}") == 120)
        #expect(try await margin(#"{ "editor": { "printMargin": 80 } }"#) == 80)
        #expect(try await margin(#"{ "editor": { "printMargin": 0 } }"#) == nil)
        #expect(try await margin(#"{ "editor": { "printMargin": -4 } }"#) == nil)
        #expect(try await margin(#"{ "editor": { "insertFinalNewline": false } }"#) == 120)
    }

    @Test func theLineGoesAfterTheColumnsCharacters() {
        #expect(abs(CurrentLineTextView.printMarginX(column: 120, advance: 7.8, inset: 4, padding: 5) - 945) < 0.001)
        #expect(CurrentLineTextView.printMarginX(column: 0, advance: 7.8, inset: 4, padding: 5) == 9)
    }

    @Test @MainActor func theAdvanceIsOneCharacterOfTheFont() throws {
        let font = try #require(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) as NSFont?)
        let ten = ("0000000000" as NSString).size(withAttributes: [.font: font]).width
        #expect(abs(CurrentLineTextView.advance(of: font) * 10 - ten) < 0.5)
    }
}
