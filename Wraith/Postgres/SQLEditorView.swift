import AppKit
import SwiftUI

/// The SQL editor of a query tab (postgres R9, R10): a monospaced `NSTextView` with the
/// editor's gutter and `TextEditing`, `cmd+enter` and `cmd+.` as keys of the view.
///
/// The file editor's `EditorTextView` is tied to `EditorTab` and `FileDocument`; this is the
/// feature's own text area (decision 2026-08-26), ~120 lines, nothing else reused was possible.
struct SQLEditorView: NSViewRepresentable {
    let tab: PostgresQueryTab
    let theme: ThemeService
    let onRun: () -> Void
    let onStop: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = SQLTextView(frame: .zero)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.font = theme.editorFont
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = tab.text
        textView.delegate = context.coordinator
        textView.onRun = onRun
        textView.onStop = onStop
        tab.textView = textView
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.verticalRulerView = LineNumberRulerView(textView: textView, font: theme.editorFont)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? SQLTextView else { return }
        tab.textView = textView
        textView.onRun = onRun
        textView.onStop = onStop
        if textView.font != theme.editorFont {
            textView.font = theme.editorFont
        }
        if let insertion = tab.pendingInsertion {
            tab.pendingInsertion = nil
            textView.insertText(insertion, replacementRange: textView.selectedRange())
        }
        if let cursor = tab.requestedCursor {
            // R19: the cursor goes to the error.
            tab.requestedCursor = nil
            let location = min(cursor, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.window?.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let tab: PostgresQueryTab

        init(tab: PostgresQueryTab) {
            self.tab = tab
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            tab.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            tab.selection = textView.selectedRange()
        }

        /// R9: `tab` inserts four spaces, `enter` keeps the line's indent (`TextEditing`, M1).
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let selection = textView.selectedRange()
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText("    ", replacementRange: selection)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let edit = TextEditing.newline(at: selection, in: textView.string as NSString)
                textView.insertText(edit.replacement, replacementRange: edit.range)
                return true
            default:
                return false
            }
        }
    }
}

/// `NSTextView` that hands `cmd+enter` and `cmd+.` to the tab (postgres R10, R13: keys of the
/// panel, not `ShortcutAction`s — see the M5 backlog).
final class SQLTextView: NSTextView {
    var onRun: () -> Void = {}
    var onStop: () -> Void = {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.keyCode == 36 || event.keyCode == 76 {
            onRun()
            return true
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "." {
            onStop()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
