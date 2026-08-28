import AppKit
import Neon
import RangeState
import Testing

@testable import Foreman

/// The TextKit 2 prototype (editor, open question, 2026-08-26): Neon on an `NSTextView` built
/// with `NSTextLayoutManager` colors a keyword and the view stays on TextKit 2.
@MainActor
struct HighlighterTests {
    @Test func colorsSwiftKeywordsOnTextKit2() async throws {
        let theme = ThemeService()
        let highlighter = Highlighter(theme: theme)
        let scroll = NSTextView.scrollableTextView()
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(textView.textLayoutManager != nil)

        let attached = try #require(await highlighter.attach(to: textView, language: .swift))
        textView.string = "let answer = 42 // why\n"
        attached.invalidate(.all)
        try await Task.sleep(for: .milliseconds(500))

        #expect(textView.textLayoutManager != nil)
        let storage = try #require(textView.textStorage)
        let manager = try #require(textView.textLayoutManager)
        var first: [NSAttributedString.Key: Any] = [:]
        manager.enumerateRenderingAttributes(from: manager.documentRange.location, reverse: false) { _, attributes, _ in
            first = attributes
            return false
        }
        #expect(first[.foregroundColor] as? NSColor == theme.color(for: .keyword))
        #expect(storage.length == 23)
    }

    @Test func unknownGrammarFallsBackToPlainText() async throws {
        let scroll = NSTextView.scrollableTextView()
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(await Highlighter(theme: ThemeService()).attach(to: textView, language: .json) != nil)
    }
}
