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

        init(path: String, pinned: Bool, cursor: Int = 0, scroll: Double = 0, mode: Mode = .source) {
            self.path = path
            self.pinned = pinned
            self.cursor = cursor
            self.scroll = scroll
            self.mode = mode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            pinned = try container.decode(Bool.self, forKey: .pinned)
            cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
            scroll = try container.decodeIfPresent(Double.self, forKey: .scroll) ?? 0
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .source
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
    private(set) var diskState: DiskState = .current
    /// Bumped when the text must be replaced in the view (editor R9, silent reload).
    private(set) var reloadVersion = 0
    private(set) var content: Content = .loading
    /// editor R6: the unit `tab` inserts, detected at load.
    private(set) var indentUnit = "    "
    /// The view showing the text, set by `EditorTextView`; the commands act on it.
    weak var textView: NSTextView?

    var language: Language? {
        Language.forFile(url)
    }

    var payload: Payload {
        Payload(path: path, pinned: isPinned, cursor: cursor, scroll: scroll, mode: mode)
    }

    var document: FileDocument? {
        if case .text(let document) = content {
            return document
        }
        return nil
    }

    init(
        path: String, url: URL, isPinned: Bool, line: Int? = nil, cursor: Int = 0, scroll: Double = 0,
        mode: Mode = .source
    ) {
        self.path = path
        self.url = url
        self.isPinned = isPinned
        requestedLine = line
        self.cursor = cursor
        self.scroll = scroll
        self.mode = language == .markdown ? mode : .source
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
        let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        let stale = document?.isStale(at: url) ?? false
        guard let action = Self.diskAction(isDirty: isDirty, exists: exists, isStale: stale) else { return }
        switch action {
        case .current:
            await reload()
        case .modified, .deleted:
            diskState = action
        }
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
        do {
            let document = try await FileDocument.read(url)
            indentUnit = TextEditing.detectIndent(document.text)
            content = .text(document)
        } catch {
            content = .failed(error)
        }
    }

    /// The view reports every change (editor R1, R2).
    func textDidChange() {
        isDirty = true
    }

    /// editor R8, R10: writes the view's text; `false` when refused (read-only, stale file, IO).
    /// `force` writes over a file changed on disk (R10, *Overwrite*).
    func save(insertFinalNewline: Bool, force: Bool = false) async throws(EditorError) -> Bool {
        guard let document, let textView else { return false }
        guard !document.isReadOnly else { throw .unreadable("\(url.lastPathComponent) is read-only") }
        if !force, document.isStale(at: url) {
            return false
        }
        var text = textView.string
        if insertFinalNewline, !text.hasSuffix("\n") {
            text = TextEditing.withFinalNewline(text)
            textView.insertText(
                "\n", replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
        }
        content = .text(try await FileDocument.write(text, to: url, as: document))
        isDirty = false
        diskState = .current
        return true
    }
}
