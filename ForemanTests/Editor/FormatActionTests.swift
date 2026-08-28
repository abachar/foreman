import Foundation
import Testing

@testable import Foreman

/// The pure parts of `cmd+shift+l` (editor R25, R29, R30, R32).
///
/// The refusal guard, the cursor carried over, the per-tab lock, the banner wording. No view, no formatter.
struct FormatActionTests {
    @Test func refusesReadOnlyPreviewMissingCommandAndMissingBinaryInThatOrder() {
        #expect(
            EditorFeature.formatRefusal(
                isReadOnly: true, isPreview: true, key: "md", command: nil, isBinaryAvailable: false)
                == "Read-only or over 2 MB: not formatted")
        #expect(
            EditorFeature.formatRefusal(
                isReadOnly: false, isPreview: true, key: "md", command: "prettier", isBinaryAvailable: true)
                == "Markdown preview: switch to the source (⌘⇧V) to format")
        #expect(
            EditorFeature.formatRefusal(
                isReadOnly: false, isPreview: false, key: "xml", command: nil, isBinaryAvailable: false)
                == "No formatter for `.xml` in .foreman/config.json")
        #expect(
            EditorFeature.formatRefusal(
                isReadOnly: false, isPreview: false, key: "ts", command: "npx --no-install prettier",
                isBinaryAvailable: false) == "`npx` not found in PATH")
        #expect(
            EditorFeature.formatRefusal(
                isReadOnly: false, isPreview: false, key: "ts", command: "prettier", isBinaryAvailable: true) == nil)
    }

    @Test func carriesTheCursorOverByLineAndColumn() {
        let before = "a\n  bb\nccc" as NSString
        let position = TextEditing.position(at: 5, in: before)
        #expect(position == TextEditing.Position(line: 2, column: 3))
        #expect(TextEditing.location(of: position, in: "a\nbb\nccc") == 4)
        // A column beyond the line stops at its end, before the newline.
        #expect(TextEditing.location(of: position, in: "a\nb\nccc") == 3)
        // A line that disappeared goes to the last line.
        #expect(TextEditing.location(of: TextEditing.Position(line: 9, column: 1), in: "a\nb") == 3)
        #expect(TextEditing.location(of: TextEditing.Position(line: 9, column: 0), in: "a\nb\n") == 4)
        // The text emptied.
        #expect(TextEditing.location(of: position, in: "") == 0)
        #expect(TextEditing.position(at: 0, in: "") == TextEditing.Position(line: 1, column: 0))
        #expect(TextEditing.position(at: 10, in: "ab") == TextEditing.Position(line: 1, column: 2))
    }

    @Test @MainActor func aSecondTriggerDuringAnExecutionIsIgnored() {
        let tab = EditorTab(path: "a.ts", url: URL(filePath: "/a.ts"), isPinned: true)
        #expect(tab.beginFormatting())
        #expect(!tab.beginFormatting())
        tab.endFormatting()
        #expect(tab.beginFormatting())
    }

    @Test @MainActor func theMessageGoesAtTheNextKeystroke() {
        let tab = EditorTab(path: "a.ts", url: URL(filePath: "/a.ts"), isPinned: true)
        tab.message = "No formatter"
        tab.textDidChange()
        #expect(tab.message == nil)
    }

    @Test func wordsTheBanner() {
        #expect(EditorFeature.formatMessage(for: .formatted("x"), timeout: .seconds(5)) == nil)
        #expect(EditorFeature.formatMessage(for: .unchanged, timeout: .seconds(5)) == nil)
        #expect(
            EditorFeature.formatMessage(for: .failed(status: 2, stderr: "SyntaxError"), timeout: .seconds(5))
                == "Formatter (status 2): SyntaxError")
        #expect(
            EditorFeature.formatMessage(for: .failed(status: 1, stderr: ""), timeout: .seconds(5))
                == "Formatter exited with status 1")
        #expect(
            EditorFeature.formatMessage(for: .timedOut, timeout: .seconds(5))
                == "Formatter stopped after 5 s — raise formatter.timeout in .foreman/config.json")
    }
}
