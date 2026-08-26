import AppKit
import Neon
import SwiftUI

/// The text itself: `NSTextView` on TextKit 2 with Neon attached (editor, technical options).
///
/// Read-only until 1.9 brings editing and `isDirty`.
struct EditorTextView: NSViewRepresentable {
    let tab: EditorTab
    let document: FileDocument
    let theme: ThemeService
    let highlighter: Highlighter

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.font = theme.editorFont
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = document.text
        if document.isHighlightable, let language = tab.language {
            context.coordinator.highlighter = highlighter.attach(to: textView, language: language)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let line = tab.requestedLine, let textView = scroll.documentView as? NSTextView else { return }
        tab.requestedLine = nil
        let text = textView.string as NSString
        var location = 0
        var current = 1
        while current < line, location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            current += 1
        }
        // editor R3: the cursor goes to the line and the line is shown.
        textView.setSelectedRange(NSRange(location: min(location, text.length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    @MainActor
    final class Coordinator {
        /// Kept alive for the life of the view: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
    }
}
