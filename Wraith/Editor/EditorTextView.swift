import AppKit
import Neon
import SwiftUI

/// The text itself: `NSTextView` on TextKit 2 with Neon attached (editor, technical options).
///
/// Editing, undo, selection and IME are the view's; `tab` and `enter` follow editor R6 through
/// the delegate; every other command comes from `EditorFeature` through `EditorTab.textView`.
struct EditorTextView: NSViewRepresentable {
    let tab: EditorTab
    let document: FileDocument
    let theme: ThemeService
    let highlighter: Highlighter

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.font = theme.editorFont
        textView.isEditable = !document.isReadOnly
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = document.text
        textView.delegate = context.coordinator
        tab.textView = textView
        if document.isHighlightable, let language = tab.language {
            context.coordinator.highlighter = highlighter.attach(to: textView, language: language)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let line = tab.requestedLine, let textView = scroll.documentView as? NSTextView else { return }
        tab.requestedLine = nil
        // editor R3: the cursor goes to the line and the line is shown.
        let location = TextEditing.location(ofLine: line, in: textView.string as NSString)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Kept alive for the life of the view: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
        private let tab: EditorTab

        init(tab: EditorTab) {
            self.tab = tab
        }

        func textDidChange(_ notification: Notification) {
            tab.textDidChange()
        }

        /// editor R6: `tab` inserts the file's indent unit, `enter` keeps the line's indent.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let text = textView.string as NSString
            let selection = textView.selectedRange()
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText(tab.indentUnit, replacementRange: selection)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let edit = TextEditing.newline(at: selection, in: text)
                textView.insertText(edit.replacement, replacementRange: edit.range)
                return true
            default:
                return false
            }
        }
    }
}
