import AppKit
import Neon
import RangeState
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
        let scroll = CurrentLineTextView.scrollableTextView()
        guard let textView = scroll.documentView as? CurrentLineTextView else { return scroll }
        textView.font = theme.editorFont
        textView.isEditable = !document.isReadOnly
        textView.isRichText = false
        textView.allowsUndo = true
        // editor R7: the find and replace bar is NSTextFinder's (1.11).
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = document.text
        textView.delegate = context.coordinator
        tab.textView = textView
        // editor R6: the gutter.
        let ruler = LineNumberRulerView(textView: textView, font: theme.editorFont)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = false
        Self.paint(textView, ruler: ruler, tokens: theme.tokens)
        if document.isHighlightable, let language = tab.language {
            // The grammar comes when it is ready (M6 6.5): plain text until then, no freeze.
            context.coordinator.attaching = Task { [highlighter, weak textView, coordinator = context.coordinator] in
                guard let textView, let attached = await highlighter.attach(to: textView, language: language),
                    !Task.isCancelled
                else { return }
                coordinator.highlighter = attached
                attached.invalidate(.all)
            }
        }
        // editor R4: cursor and scroll come back with the tab. The position is captured before
        // the observer exists: the first layout of a rebuilt view reports `y = 0`, which must
        // not overwrite it (bug: switching tabs lost the scroll, 2026-08-27).
        textView.setSelectedRange(NSRange(location: min(tab.cursor, (document.text as NSString).length), length: 0))
        let savedScroll = tab.scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [tab, weak scroll, coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let scroll, coordinator.isScrollRestored else { return }
                tab.scroll = scroll.contentView.bounds.origin.y
            }
        }
        context.coordinator.reloadVersion = tab.reloadVersion
        DispatchQueue.main.async { [weak scroll, coordinator = context.coordinator] in
            defer { coordinator.isScrollRestored = true }
            guard let scroll, let textView = scroll.documentView as? NSTextView else { return }
            // TextKit 2 lays out lazily: without this the clip view clamps the target to 0.
            if let layoutManager = textView.textLayoutManager {
                layoutManager.ensureLayout(for: layoutManager.documentRange)
            }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: savedScroll))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CurrentLineTextView else { return }
        // SwiftUI may rebuild the native view when the tab is shown again: the commands must
        // reach the live instance.
        tab.textView = textView
        // terminal R14: the font follows the config.
        if textView.font != theme.editorFont {
            textView.font = theme.editorFont
        }
        Self.paint(textView, ruler: scroll.verticalRulerView as? LineNumberRulerView, tokens: theme.tokens)
        if context.coordinator.reloadVersion != tab.reloadVersion, let document = tab.document {
            // editor R9: silent reload, cursor and scroll preserved.
            context.coordinator.reloadVersion = tab.reloadVersion
            let selection = textView.selectedRange()
            let origin = scroll.contentView.bounds.origin
            textView.string = document.text
            textView.isEditable = !document.isReadOnly
            textView.setSelectedRange(
                NSRange(location: min(selection.location, (document.text as NSString).length), length: 0))
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            context.coordinator.highlighter?.invalidate(.all)
        }
        guard let line = tab.requestedLine else { return }
        tab.requestedLine = nil
        // editor R3: the cursor goes to the line and the line is shown.
        let location = TextEditing.location(ofLine: line, in: textView.string as NSString)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// design R8, R22: the text, the caret, the selection, the current line and the gutter.
    static func paint(_ textView: CurrentLineTextView, ruler: LineNumberRulerView?, tokens: ThemeService.Tokens) {
        let background = tokens.surface.nsColor
        guard textView.backgroundColor != background || textView.currentLineColor != tokens.surfaceSunken.nsColor
        else { return }
        textView.backgroundColor = background
        textView.textColor = tokens.textPrimary.nsColor
        textView.insertionPointColor = tokens.textPrimary.nsColor
        textView.selectedTextAttributes = [.backgroundColor: tokens.accent.nsColor(alpha: 0.35)]
        textView.currentLineColor = tokens.surfaceSunken.nsColor
        ruler?.textColor = tokens.textSecondary.nsColor
        ruler?.backgroundColor = background
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Kept alive for the life of the view: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
        var attaching: Task<Void, Never>?
        var scrollObserver: (any NSObjectProtocol)?
        /// editor R4: bounds changes count only once the saved position was restored.
        var isScrollRestored = false
        var reloadVersion = 0
        private let tab: EditorTab

        init(tab: EditorTab) {
            self.tab = tab
        }

        isolated deinit {
            attaching?.cancel()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func textDidChange(_ notification: Notification) {
            tab.textDidChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            tab.cursor = textView.selectedRange().location
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
