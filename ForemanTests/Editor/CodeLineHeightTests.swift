import AppKit
import Testing

@testable import Foreman

/// design R6 (M25 25.3): the code's line height is `codeLineHeight` times the font's, and the
/// text view lays its lines out at exactly that pitch — which is what the gutter, the sticky
/// lines and the guides read back from TextKit's fragments.
@MainActor
struct CodeLineHeightTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    @Test func thePitchIsTheFontsLineHeightTimesTheMultiple() {
        let bare = ThemeService.linePitch(of: font, multiple: 1)
        #expect(bare == (font.ascender - font.descender + font.leading).rounded(.up))
        #expect(ThemeService.linePitch(of: font, multiple: 1.2) == bare * 1.2)
        #expect(ThemeService.linePitch(of: font, multiple: 2) == 2 * bare)
    }

    /// The text view's fragments come out at the pitch, on a text set before and after `paint`.
    @Test func theTextViewLaysItsLinesOutAtThePitch() throws {
        let scroll = CurrentLineTextView.scrollableTextView()
        let textView = try #require(scroll.documentView as? CurrentLineTextView)
        textView.font = font
        textView.string = "one\ntwo\nthree\n"
        EditorTextView.paint(textView, ruler: nil, tokens: .dark)
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var heights: [CGFloat] = []
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: [.ensuresLayout]
        ) {
            heights.append($0.layoutFragmentFrame.height)
            return true
        }
        let pitch = ThemeService.linePitch(of: font, multiple: 1.2)
        #expect(heights.count >= 2)
        // The last fragment may carry the empty paragraph after the final newline; the first
        // two are one line each and must come out at the pitch exactly.
        for height in heights.prefix(2) {
            #expect(abs(height - pitch) < 0.01, "\(height) vs \(pitch)")
        }
        #expect(pitch > ThemeService.linePitch(of: font, multiple: 1))
        // Text typed later inherits the style through the typing attributes.
        #expect((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple == 1.2)
        // A second paint changes nothing and touches nothing.
        EditorTextView.paint(textView, ruler: nil, tokens: .dark)
        #expect(textView.textColor == ThemeService.Tokens.dark.codeText.nsColor)
    }

    /// Text replaced wholesale (a reload, editor R9) gets the style back at the next paint.
    @Test func aReplacedTextGetsTheStyleAgain() throws {
        let scroll = CurrentLineTextView.scrollableTextView()
        let textView = try #require(scroll.documentView as? CurrentLineTextView)
        textView.font = font
        EditorTextView.paint(textView, ruler: nil, tokens: .dark)
        textView.string = "fresh\n"
        EditorTextView.paint(textView, ruler: nil, tokens: .dark)
        let storage = try #require(textView.textStorage)
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineHeightMultiple == 1.2)
    }
}
