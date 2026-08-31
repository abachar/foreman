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
        if let existing = tab.textCoordinator {
            return existing
        }
        let coordinator = Coordinator(tab: tab)
        tab.textCoordinator = coordinator
        return coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        // SwiftUI rebuilds this view on every tab switch; the native one is built once per tab.
        if let scroll = context.coordinator.scroll {
            return scroll
        }
        let scroll = CurrentLineTextView.scrollableTextView()
        context.coordinator.scroll = scroll
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
        // editor R26: folded paragraphs are laid out through the coordinator.
        textView.textContentStorage?.delegate = context.coordinator
        tab.textView = textView
        // editor R43: the view reports the click, the tab routes it to the feature.
        textView.onCommandClick = { [weak tab] location in tab?.onCommandClick?(location) }
        // editor R6: the gutter.
        let ruler = LineNumberRulerView(textView: textView, font: theme.editorFont)
        ruler.onToggleFold = { [weak tab] line in tab?.toggleFold(atLine: line) }
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = false
        Self.paint(textView, ruler: ruler, tokens: theme.tokens)
        if document.isHighlightable, let language = tab.language {
            // The grammar comes when it is ready (M6 6.5): plain text until then, no freeze.
            context.coordinator.attaching = Task {
                [highlighter, weak textView, weak coordinator = context.coordinator] in
                guard let textView, let attached = await highlighter.attach(to: textView, language: language),
                    !Task.isCancelled, let coordinator
                else { return }
                coordinator.highlighter = attached
                attached.invalidate(.all)
            }
            tab.refreshFolds(after: .zero)
        }
        // editor R4: cursor and scroll come back with the tab. The position is captured before
        // the observer exists: the first layout of a rebuilt view reports `y = 0`, which must
        // not overwrite it (bug: switching tabs lost the scroll, 2026-08-27).
        textView.setSelectedRange(NSRange(location: min(tab.cursor, (document.text as NSString).length), length: 0))
        let savedScroll = tab.scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak tab, weak scroll, weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                // Weak: NotificationCenter keeps this block until `removeObserver`, which runs
                // in the coordinator's deinit — a strong capture would make that unreachable.
                guard let tab, let scroll, let coordinator, coordinator.isScrollRestored else { return }
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
            // The clip view keeps its own x: with a vertical ruler AppKit lays it out under the
            // ruler and offsets its bounds, and an x of 0 hid the first 44 pt of text (2026-08-28).
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: savedScroll))
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
            // A programmatic `string` set posts no edit notification: the gutter is told.
            (scroll.verticalRulerView as? LineNumberRulerView)?.rebuildLineStarts()
            textView.setSelectedRange(
                NSRange(location: min(selection.location, (document.text as NSString).length), length: 0))
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            context.coordinator.highlighter?.invalidate(.all)
        }
        // editor R26, R27: the folds reach the layout and the gutter.
        context.coordinator.applyFolds(regions: tab.foldRegions, folded: tab.foldedLines, to: textView, in: scroll)
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
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextContentStorageDelegate {
        /// The native view, owned here so it outlives the SwiftUI view that shows it.
        var scroll: NSScrollView?
        /// Kept alive for the life of the tab: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
        var attaching: Task<Void, Never>?
        var scrollObserver: (any NSObjectProtocol)?
        /// editor R4: bounds changes count only once the saved position was restored.
        var isScrollRestored = false
        var reloadVersion = 0
        /// Weak: the tab owns the coordinator (`textCoordinator`); a strong back reference would
        /// keep both — and the whole text stack — alive after the tab closes.
        private weak var tab: EditorTab?
        /// editor R26: the characters of the hidden lines, as laid out.
        private var hiddenCharacters = IndexSet()
        private var appliedFolds: (regions: [FoldRegion], folded: Set<Int>) = ([], [])

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
            tab?.textDidChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let tab else { return }
            tab.cursor = textView.selectedRange().location
            // editor R28: the cursor inside a fold (an edit, a search hit) opens it.
            if !hiddenCharacters.isEmpty, hiddenCharacters.contains(textView.selectedRange().location) {
                tab.unfoldHidden(
                    line: TextEditing.position(at: textView.selectedRange().location, in: textView.string as NSString)
                        .line)
            }
        }

        // MARK: - Folding (editor R26, R27)

        /// The hidden lines recomputed, the layout asked again for every paragraph, the gutter redrawn.
        func applyFolds(regions: [FoldRegion], folded: Set<Int>, to textView: NSTextView, in scroll: NSScrollView) {
            guard appliedFolds.regions != regions || appliedFolds.folded != folded else { return }
            appliedFolds = (regions, folded)
            let ruler = scroll.verticalRulerView as? LineNumberRulerView
            ruler?.foldRegions = regions
            ruler?.foldedLines = folded
            let hidden = Folding.hiddenLines(regions, folded: folded)
            let characters = Self.characters(ofLines: hidden, in: textView.string as NSString)
            guard characters != hiddenCharacters else { return }
            hiddenCharacters = characters
            guard let storage = textView.textStorage else { return }
            // An attribute-only edit over the whole text: the content storage rebuilds its
            // paragraphs through the delegate and the layout follows; nothing changes on disk.
            storage.beginEditing()
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
            storage.endEditing()
            ruler?.needsDisplay = true
        }

        /// The character ranges of `lines` (1-based), as one index set.
        nonisolated static func characters(ofLines lines: IndexSet, in text: NSString) -> IndexSet {
            var result = IndexSet()
            guard !lines.isEmpty else { return result }
            var line = 1
            var location = 0
            while location < text.length, line <= (lines.last ?? 0) {
                let range = text.lineRange(for: NSRange(location: location, length: 0))
                if lines.contains(line) {
                    result.insert(integersIn: range.location..<NSMaxRange(range))
                }
                line += 1
                location = NSMaxRange(range)
            }
            return result
        }

        /// editor R26: a hidden paragraph keeps its characters (the storage is untouched) and
        /// loses its height; the platform's way to fold on TextKit 2 (decision 2026-08-28).
        func textContentStorage(
            _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
        )
            -> NSTextParagraph?
        {
            guard hiddenCharacters.contains(range.location),
                let original = textContentStorage.textStorage?.attributedSubstring(from: range)
            else { return nil }
            let hidden = NSMutableAttributedString(attributedString: original)
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = 0.01
            style.maximumLineHeight = 0.01
            style.lineSpacing = 0
            hidden.addAttributes(
                [.font: NSFont.systemFont(ofSize: 0.01), .paragraphStyle: style, .foregroundColor: NSColor.clear],
                range: NSRange(location: 0, length: hidden.length))
            return NSTextParagraph(attributedString: hidden)
        }

        /// editor R6: `tab` inserts the file's indent unit, `enter` keeps the line's indent.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let tab else { return false }
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
