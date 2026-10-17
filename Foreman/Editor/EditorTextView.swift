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
    /// editor R41: passed in rather than read off the tab, so the SwiftUI body observes it and
    /// `updateNSView` runs when a batch arrives.
    let diagnostics: [EditorDiagnostic]
    /// editor R53: the column of the print margin, `nil` for none.
    let printMargin: Int?

    /// editor R41, design R6: severity to token — the status colours the app already defines.
    static func color(for severity: EditorDiagnostic.Severity, tokens: ThemeService.Tokens) -> NSColor {
        switch severity {
        case .error: return tokens.statusRed.nsColor
        case .warning: return tokens.statusOrange.nsColor
        case .information: return tokens.statusBlue.nsColor
        case .hint: return tokens.textSecondary.nsColor
        }
    }

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
        // design R6 (M25 25.3): the line height goes in **before** the text, so TextKit's first
        // estimate of the document's height is at the right pitch — set after, the view kept the
        // frame of the bare height and drew nothing under it until the first scroll (2026-10-17).
        Self.applyLineHeight(theme.tokens.codeLineHeight, to: textView)
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
        textView.textWasReplaced()
        textView.delegate = context.coordinator
        // editor R26: folded paragraphs are laid out through the coordinator.
        textView.textContentStorage?.delegate = context.coordinator
        tab.textView = textView
        // editor R43: the view reports the click, the tab routes it to the feature.
        textView.onCommandClick = { [weak tab] location in tab?.onCommandClick?(location) }
        // editor R42: the same route for the pointer.
        textView.onPointerMoved = { [weak tab] location in tab?.onPointerMoved?(location) }
        textView.onPointerLeft = { [weak tab] in tab?.onPointerLeft?() }
        // editor R6: the gutter.
        let ruler = LineNumberRulerView(textView: textView, font: theme.editorFont)
        ruler.onToggleFold = { [weak tab] line in tab?.toggleFold(atLine: line) }
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        // editor R56: the sticky lines float over the top of the editor.
        let sticky = StickyLinesView()
        sticky.textView = textView
        sticky.lineStarts = { [weak textView] in textView?.lineStarts ?? [0] }
        sticky.autoresizingMask = [.width, .minYMargin]
        scroll.addSubview(sticky)
        context.coordinator.sticky = sticky
        scroll.drawsBackground = false
        Self.paint(textView, ruler: ruler, tokens: theme.tokens)
        if document.isHighlightable, let language = tab.language {
            // The grammar comes when it is ready (M6 6.5): plain text until then, no freeze.
            context.coordinator.attaching = Task {
                [
                    highlighter, weak textView, weak coordinator = context.coordinator,
                    semantics = context.coordinator.semantics
                ] in
                guard let textView,
                    let attached = await highlighter.attach(to: textView, language: language, semantics: semantics),
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
                coordinator?.sticky?.refresh()
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
            // editor R56: the restored position may equal the one asked for, with no bounds change.
            coordinator.sticky?.refresh()
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
        if textView.printMarginColumn != printMargin {
            textView.printMarginColumn = printMargin
        }
        if context.coordinator.reloadVersion != tab.reloadVersion, let document = tab.document {
            // editor R9: silent reload, cursor and scroll preserved.
            context.coordinator.reloadVersion = tab.reloadVersion
            let selection = textView.selectedRange()
            let origin = scroll.contentView.bounds.origin
            textView.string = document.text
            textView.isEditable = !document.isReadOnly
            // A programmatic `string` set posts no edit notification: the text view re-reads its
            // line starts, which the gutter draws from.
            textView.textWasReplaced()
            scroll.verticalRulerView?.needsDisplay = true
            textView.setSelectedRange(
                NSRange(location: min(selection.location, (document.text as NSString).length), length: 0))
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            context.coordinator.highlighter?.invalidate(.all)
        }
        // editor R26, R27: the folds reach the layout and the gutter.
        context.coordinator.applyFolds(regions: tab.foldRegions, folded: tab.foldedLines, to: textView, in: scroll)
        // editor R56: the sticky lines follow the regions of the same parse, on the editor's ground.
        if let sticky = context.coordinator.sticky {
            let tokens = theme.tokens
            sticky.background = tokens.surface.nsColor
            sticky.separator = tokens.separator.nsColor
            sticky.numberColor = tokens.textSecondary.nsColor
            sticky.numberFont = NSFont.monospacedDigitSystemFont(
                ofSize: theme.editorFont.pointSize - 1, weight: .regular)
            sticky.regions = tab.foldRegions
        }
        // editor R54, R55: the guides' block and the brackets come from the same parse.
        textView.setStructure(
            regions: tab.foldRegions, brackets: tab.bracketPairs,
            indentWidth: IndentGuides.width(of: tab.indentUnit))
        applyDiagnostics(to: textView, ruler: scroll.verticalRulerView as? LineNumberRulerView)
        guard let line = tab.requestedLine else { return }
        tab.requestedLine = nil
        // editor R3: the cursor goes to the line and the line is shown.
        let location = TextEditing.location(ofLine: line, in: textView.string as NSString)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// design R8, R22: the text, the caret, the selection, the current line and the gutter.
    /// editor R41: the ranges to underline and the lines to mark, both recomputed against the
    /// text as it is now — a diagnostic holds a line and a column, not an offset, precisely so a
    /// batch that arrives after an edit lands where the text is rather than where it was.
    private func applyDiagnostics(to textView: CurrentLineTextView, ruler: LineNumberRulerView?) {
        let text = textView.string as NSString
        let tokens = theme.tokens
        textView.underlines = diagnostics.compactMap { diagnostic in
            diagnostic.range(in: text).map {
                CurrentLineTextView.Underline(range: $0, color: Self.color(for: diagnostic.severity, tokens: tokens))
            }
        }
        ruler?.diagnosticDots = EditorDiagnostic.severityByLine(diagnostics).mapValues {
            Self.color(for: $0, tokens: tokens)
        }
    }

    static func paint(_ textView: CurrentLineTextView, ruler: LineNumberRulerView?, tokens: ThemeService.Tokens) {
        applyLineHeight(tokens.codeLineHeight, to: textView)
        let background = tokens.surface.nsColor
        let colorsChanged =
            textView.backgroundColor != background || textView.currentLineColor != tokens.surfaceSunken.nsColor
            || textView.textColor != tokens.codeText.nsColor
        guard colorsChanged else { return }
        textView.backgroundColor = background
        // design R9 (M25 25.3): the code's text is `codeText`, a step under the chrome's.
        textView.textColor = tokens.codeText.nsColor
        textView.insertionPointColor = tokens.codeText.nsColor
        textView.selectedTextAttributes = [.backgroundColor: tokens.accent.nsColor(alpha: 0.35)]
        textView.currentLineColor = tokens.surfaceSunken.nsColor
        // design R25 (2026-10-16): the print margin and the gutter's edge are separators.
        textView.printMarginColor = tokens.separator.nsColor
        textView.guideColor = tokens.separator.nsColor
        textView.activeGuideColor = tokens.textDisabled.nsColor
        textView.bracketColor = tokens.accent.nsColor(alpha: 0.3)
        // design R9 (M25 25.3): the numbers step back, the caret's line's number steps forward.
        ruler?.textColor = tokens.textDisabled.nsColor
        ruler?.currentLineTextColor = tokens.textSecondary.nsColor
        ruler?.backgroundColor = background
        ruler?.separatorColor = tokens.separator.nsColor
        ruler?.activeMarkerColor = tokens.textPrimary.nsColor
        ruler?.markerColor = tokens.textDisabled.nsColor
    }

    /// design R6 (M25 25.3): the code's line height, `multiple` times the font's, on a text view.
    ///
    /// Three places, each for a reason: the default style for text that has none, the typing
    /// attributes because Neon re-applies them under every token it colours (a style anywhere
    /// else is wiped at the first highlight), and the storage because `string =` and a font
    /// change do not revisit the paragraph style of the text already there. Idempotent and
    /// cheap: the storage is touched only when its first paragraph does not carry the multiple.
    static func applyLineHeight(_ multiple: Double, to textView: NSTextView) {
        let applied = (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple
        let first =
            textView.textStorage.flatMap { storage -> NSParagraphStyle? in
                guard storage.length > 0 else { return nil }
                return storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            }?.lineHeightMultiple
        let storageLacksIt = (textView.textStorage?.length ?? 0) > 0 && first != multiple
        guard applied != multiple || storageLacksIt else { return }
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = multiple
        textView.defaultParagraphStyle = style
        textView.typingAttributes[.paragraphStyle] = style
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
        // The text already laid out changes height under the viewport: TextKit 2 sizes the view
        // again on its next viewport pass, which nothing else asks for, and the gutter draws from
        // the fragments, so both are asked now (a live change of `codeLineHeight`).
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextContentStorageDelegate {
        /// The native view, owned here so it outlives the SwiftUI view that shows it.
        var scroll: NSScrollView?
        /// Kept alive for the life of the tab: Neon only holds the text view weakly.
        var highlighter: TextViewHighlighter?
        /// editor R59: the server's tokens for this text view, read by the highlighter's provider.
        let semantics = SemanticTokenStore()
        /// editor R56: the pinned lines over the top of the editor.
        var sticky: StickyLinesView?

        /// editor R59: a new batch in; the highlighter asks again about what changed.
        func applySemanticTokens(_ tokens: [SemanticToken]) {
            let changed = semantics.replace(with: tokens)
            guard !changed.isEmpty else { return }
            highlighter?.invalidate(.set(changed))
        }
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
