import AppKit
import Neon
import RangeState
import SwiftUI

/// The SQL editor of a query tab (postgres R9, R10): a monospaced `NSTextView` with the
/// editor's gutter and `TextEditing`, `cmd+enter` and `cmd+.` as keys of the view.
///
/// The file editor's `EditorTextView` is tied to `EditorTab` and `FileDocument`; this is the
/// feature's own text area (decision 2026-08-26), ~120 lines, nothing else reused was possible.
struct SQLEditorView: NSViewRepresentable {
    let tab: PostgresQueryTab
    /// R8, R19, R20: read by the enclosing body so a new request updates this view; the
    /// coordinator is what applies it.
    let pending: PostgresQueryTab.PendingEdit
    let theme: ThemeService
    let highlighter: Highlighter
    let onRun: () -> Void
    let onStop: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // `scrollableTextView()` wires the container, the clip view and the sizing that a bare
        // `NSTextView(frame:)` lacks (bug: the editor stayed narrow, 2026-08-27).
        let scroll = SQLTextView.scrollableTextView()
        guard let textView = scroll.documentView as? SQLTextView else { return scroll }
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
        // postgres R9: the same Neon highlighter as the file editor, on the `sql` grammar (2026-08-28).
        context.coordinator.attaching = Task { [highlighter, weak textView, coordinator = context.coordinator] in
            guard let textView, let attached = await highlighter.attach(to: textView, language: .sql),
                !Task.isCancelled
            else { return }
            coordinator.highlighter = attached
            attached.invalidate(.all)
        }
        let ruler = LineNumberRulerView(textView: textView, font: theme.editorFont)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = false
        EditorTextView.paint(textView, ruler: ruler, tokens: theme.tokens)
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
        EditorTextView.paint(textView, ruler: scroll.verticalRulerView as? LineNumberRulerView, tokens: theme.tokens)
        context.coordinator.apply(pending, to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Kept alive for the life of the tab: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
        var attaching: Task<Void, Never>?
        /// R8, R19, R20: the version of the last request applied, held here so nothing on the
        /// tab is written from a view update.
        private var appliedEdit = 0
        private let tab: PostgresQueryTab

        init(tab: PostgresQueryTab) {
            self.tab = tab
        }

        isolated deinit {
            attaching?.cancel()
        }

        /// R8, R19, R20: the buffer replaced, a name inserted, the cursor moved — each request
        /// applied exactly once.
        ///
        /// The edit itself runs after the update pass: `insertText` comes back through
        /// `textDidChange`, and writing observed state while SwiftUI is updating the view is
        /// undefined.
        func apply(_ pending: PostgresQueryTab.PendingEdit, to textView: SQLTextView) {
            guard pending.version != appliedEdit else { return }
            appliedEdit = pending.version
            Task { [weak self, weak textView] in
                guard let self, let textView else { return }
                perform(pending, on: textView)
            }
        }

        private func perform(_ pending: PostgresQueryTab.PendingEdit, on textView: SQLTextView) {
            if let replacement = pending.replacement {
                let whole = NSRange(location: 0, length: (textView.string as NSString).length)
                textView.insertText(replacement, replacementRange: whole)
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                highlighter?.invalidate(.all)
            }
            if let insertion = pending.insertion {
                textView.insertText(insertion, replacementRange: textView.selectedRange())
            }
            if let cursor = pending.cursor {
                // R19: the cursor goes to the error.
                let location = min(cursor, (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.scrollRangeToVisible(textView.selectedRange())
                textView.window?.makeFirstResponder(textView)
            }
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
final class SQLTextView: CurrentLineTextView {
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
