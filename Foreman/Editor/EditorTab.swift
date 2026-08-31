import AppKit
import Foundation
import Observation

/// One `editor.file` tab (editor R1): the file, how it was opened, what it shows.
@Observable
@MainActor
final class EditorTab {
    enum Content: Equatable {
        case loading
        case text(FileDocument)
        case failed(EditorError)
    }

    /// The `payload` persisted by the layout (editor R4; `layout` R28).
    /// editor R14: what a markdown tab shows.
    nonisolated enum Mode: String, Codable, Sendable {
        case source
        case preview
    }

    nonisolated struct Payload: Codable, Equatable, Sendable {
        var path: String
        var pinned: Bool
        var cursor = 0
        var scroll = 0.0
        var mode = Mode.source
        /// editor R4, R14: the first visible block of the markdown preview.
        var previewBlock = 0

        init(
            path: String, pinned: Bool, cursor: Int = 0, scroll: Double = 0, mode: Mode = .source, previewBlock: Int = 0
        ) {
            self.path = path
            self.pinned = pinned
            self.cursor = cursor
            self.scroll = scroll
            self.mode = mode
            self.previewBlock = previewBlock
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            pinned = try container.decode(Bool.self, forKey: .pinned)
            cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
            scroll = try container.decodeIfPresent(Double.self, forKey: .scroll) ?? 0
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .source
            previewBlock = try container.decodeIfPresent(Int.self, forKey: .previewBlock) ?? 0
        }
    }

    /// editor R9: what happened to the file on disk since it was read.
    enum DiskState: Equatable {
        case current
        /// The file changed while the tab was dirty: the user chooses.
        case modified
        case deleted
    }

    /// Relative to the root when inside it, absolute otherwise (config R10); follows a rename.
    private(set) var path: String
    private(set) var url: URL
    /// editor R2: an unpinned tab is the group's preview, replaced by the next one.
    var isPinned: Bool
    /// editor R1: unsaved changes; never persisted (R4).
    private(set) var isDirty = false
    /// editor R3: the 1-based line to reveal once the text is shown.
    var requestedLine: Int?
    /// editor R4: persisted with the tab, restored into the view.
    var cursor = 0
    var scroll = 0.0
    /// editor R14: persisted; only meaningful for markdown.
    var mode = Mode.source
    /// editor R4, R14: the preview's first visible block, restored with the tab.
    var previewBlock = 0
    private(set) var diskState: DiskState = .current
    /// Bumped when the text must be replaced in the view (editor R9, silent reload).
    private(set) var reloadVersion = 0
    private(set) var content: Content = .loading
    /// editor R6: the unit `tab` inserts, detected at load.
    private(set) var indentUnit = "    "
    /// The view showing the text, set by `EditorTextView`; the commands act on it.
    weak var textView: NSTextView?
    /// The native text view and its Neon highlighter, kept for the life of the tab: a tab switch
    /// re-inserts them instead of rebuilding and re-parsing the file (editor R4: undo, cursor and
    /// scroll come back with the tab).
    var textCoordinator: EditorTextView.Coordinator?
    /// editor R26–R28: the regions of the current text and the first lines of the folded ones.
    private(set) var foldRegions: [FoldRegion] = []
    private(set) var foldedLines: Set<Int> = []
    private var folding: Task<Void, Never>?
    /// editor R28, R30, R32: why the last formatting did nothing, shown in a banner until the
    /// next keystroke.
    var message: String?
    /// editor R30: one execution at a time per tab.
    private(set) var isFormatting = false

    var language: Language? {
        Language.forFile(url)
    }

    /// editor R34: an untitled tab, read off its path — nothing is persisted for it, so a restored
    /// tab is a scratch again for the same reason it was one before (editor R4).
    var isScratch: Bool {
        Scratch.isScratch(path: path)
    }

    private var scratchWrite: Task<Void, Never>?

    /// editor R37: what the text did, for whoever keeps a copy of it — the language server.
    ///
    /// A closure rather than a reference: the tab knows nothing of LSP, and `EditorFeature` owns
    /// the servers (architecture: a notification between features is a closure).
    enum TextEvent {
        case opened
        case changed
        case saved
    }

    var onTextEvent: ((TextEvent) -> Void)?
    /// editor R40, R41: what the server says about this file right now; replaced whole, never
    /// merged — a batch is the server's complete opinion of the file (`publishDiagnostics`).
    var diagnostics: [EditorDiagnostic] = []
    /// editor R43: `cmd+click` at that character offset; set by `EditorFeature`.
    var onCommandClick: ((Int) -> Void)?
    /// editor R42: the pointer moved to that character offset, or left the text.
    var onPointerMoved: ((Int) -> Void)?
    var onPointerLeft: (() -> Void)?

    var payload: Payload {
        Payload(path: path, pinned: isPinned, cursor: cursor, scroll: scroll, mode: mode, previewBlock: previewBlock)
    }

    var document: FileDocument? {
        if case .text(let document) = content {
            return document
        }
        return nil
    }

    init(
        path: String, url: URL, isPinned: Bool, line: Int? = nil, cursor: Int = 0, scroll: Double = 0,
        mode: Mode? = nil, previewBlock: Int = 0
    ) {
        self.path = path
        self.url = url
        self.isPinned = isPinned
        requestedLine = line
        self.cursor = cursor
        self.scroll = scroll
        // editor R14 (amended 2026-08-29): a markdown file opens in preview unless the tab says otherwise.
        self.mode = language == .markdown ? (mode ?? .preview) : .source
        self.previewBlock = previewBlock
    }

    /// The text as it is now: the view's when it exists, the file's otherwise.
    var currentText: String {
        textView?.string ?? document?.text ?? ""
    }

    /// editor R14: `cmd+shift+v`, markdown only.
    func togglePreview() {
        guard language == .markdown else { return }
        mode = mode == .source ? .preview : .source
    }

    /// editor R9: what to do when the file changed on disk.
    nonisolated static func diskAction(isDirty: Bool, exists: Bool, isStale: Bool) -> DiskState? {
        guard exists else { return .deleted }
        guard isStale else { return nil }
        return isDirty ? .modified : .current
    }

    /// editor R9: called by the feature on every FSEvents batch touching the file.
    func fileChangedOnDisk() async {
        let status = await Self.diskStatus(of: url, document: document)
        guard let action = Self.diskAction(isDirty: isDirty, exists: status.exists, isStale: status.isStale) else {
            return
        }
        switch action {
        case .current:
            await reload()
        case .modified, .deleted:
            diskState = action
        }
    }

    /// The exists/stat pair off the main actor (coding rules: no blocking IO on it).
    @concurrent
    private static func diskStatus(of url: URL, document: FileDocument?) async -> (exists: Bool, isStale: Bool) {
        (
            exists: FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            isStale: document?.isStale(at: url) ?? false
        )
    }

    /// editor R9: *Reload* on the banner, or the silent reload; cursor and scroll are kept.
    func reload() async {
        guard let document = try? await FileDocument.read(url) else { return }
        content = .text(document)
        isDirty = false
        diskState = .current
        reloadVersion += 1
    }

    /// editor R9: *Keep my changes* on the banner.
    func keepChanges() {
        diskState = .current
    }

    /// explorer R17: the tab follows a rename.
    func fileRenamed(to newURL: URL, path newPath: String) {
        url = newURL
        path = newPath
        diskState = .current
    }

    /// explorer R18 and editor R9: the tab stays, `cmd+s` recreates the file.
    func fileDeleted() {
        diskState = .deleted
    }

    func load() async {
        // Shown again is not read again: a re-read would refresh the modification date and
        // defuse the stale-overwrite prompt (editor R10); `reload()` is the explicit path (R9).
        guard case .loading = content else { return }
        do {
            let document = try await FileDocument.read(url)
            indentUnit = TextEditing.detectIndent(document.text)
            content = .text(document)
            onTextEvent?(.opened)
        } catch {
            content = .failed(error)
        }
    }

    /// The view reports every change (editor R1, R2); a formatter message does not outlive it.
    // MARK: - Folding (editor R26–R28)

    /// editor R27: the innermost region around `line` folded or unfolded.
    func setFold(atLine line: Int, folded: Bool) {
        guard let region = Folding.innermost(foldRegions, containing: line) else { return }
        if folded {
            foldedLines.insert(region.first)
        } else {
            foldedLines.remove(region.first)
        }
    }

    func toggleFold(atLine line: Int) {
        guard let region = Folding.innermost(foldRegions, containing: line) else { return }
        setFold(atLine: line, folded: !foldedLines.contains(region.first))
    }

    /// editor R28: a line inside a fold reached by the cursor (an edit, a search) unfolds it.
    func unfoldHidden(line: Int) {
        for region in foldRegions where foldedLines.contains(region.first) && region.first < line && line <= region.last
        {
            foldedLines.remove(region.first)
        }
    }

    /// editor R26: the regions follow the text, a little after the last keystroke; a fold whose
    /// region vanished is dropped.
    func refreshFolds(after delay: Duration = .milliseconds(300)) {
        folding?.cancel()
        guard let language else { return }
        folding = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil, let text = self?.currentText else { return }
            let regions = await Self.regions(in: text, language: language)
            guard !Task.isCancelled, let self else { return }
            foldRegions = regions
            foldedLines = foldedLines.filter { first in regions.contains { $0.first == first } }
        }
    }

    @concurrent
    private static func regions(in text: String, language: Language) async -> [FoldRegion] {
        Folding.regions(in: text, language: language)
    }

    func textDidChange() {
        isDirty = true
        message = nil
        refreshFolds()
        onTextEvent?(.changed)
        if isScratch {
            scheduleScratchWrite()
        }
    }

    // MARK: - Scratch (editor R34)

    /// editor R34: the draft reaches its scratch a little after the last keystroke, so quitting
    /// the app (`cmd+q`, which chains no confirmation) brings it back at the next launch.
    ///
    /// `isDirty` is deliberately left set: the file on disk is Foreman's, not a name the user
    /// chose, so closing the tab must still ask (layout R15) and `cmd+s` must still name it (R8).
    private func scheduleScratchWrite(after delay: Duration = .seconds(1)) {
        scratchWrite?.cancel()
        scratchWrite = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.writeScratch()
        }
    }

    /// editor R34: writes the draft now, and takes the new modification date with it — Foreman's
    /// own write must not come back through FSEvents as a "modified on disk" banner (editor R9).
    func writeScratch() async {
        scratchWrite?.cancel()
        scratchWrite = nil
        guard isScratch, let document else { return }
        guard let written = try? await FileDocument.write(currentText, to: url, as: document) else { return }
        content = .text(written)
    }

    /// editor R30: `false` when a formatting is already running; `endFormatting` releases.
    func beginFormatting() -> Bool {
        guard !isFormatting else { return false }
        isFormatting = true
        return true
    }

    func endFormatting() {
        isFormatting = false
    }

    /// editor R8, R10: writes the view's text; `false` when refused (read-only, stale file, IO).
    /// `force` writes over a file changed on disk (R10, *Overwrite*).
    func save(insertFinalNewline: Bool, force: Bool = false) async throws(EditorError) -> Bool {
        guard let document, let textView else { return false }
        guard !document.isReadOnly else { throw .unreadable("\(url.lastPathComponent) is read-only") }
        if !force, document.isStale(at: url) {
            return false
        }
        var saved = textView.string
        if insertFinalNewline, !saved.hasSuffix("\n") {
            saved = TextEditing.withFinalNewline(saved)
            textView.insertText(
                "\n", replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
        }
        content = .text(try await FileDocument.write(saved, to: url, as: document))
        // A keystroke during the write is not on disk: the tab is clean only while the buffer
        // still matches what was written.
        isDirty = textView.string != saved
        diskState = .current
        onTextEvent?(.saved)
        return true
    }
}
