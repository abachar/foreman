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
    nonisolated struct Payload: Codable, Equatable, Sendable {
        var path: String
        var pinned: Bool
    }

    /// Relative to the root when inside it, absolute otherwise (config R10).
    let path: String
    let url: URL
    /// editor R2: an unpinned tab is the group's preview, replaced by the next one.
    var isPinned: Bool
    /// editor R1: unsaved changes; never persisted (R4).
    private(set) var isDirty = false
    /// editor R3: the 1-based line to reveal once the text is shown.
    var requestedLine: Int?
    private(set) var content: Content = .loading
    /// editor R6: the unit `tab` inserts, detected at load.
    private(set) var indentUnit = "    "
    /// The view showing the text, set by `EditorTextView`; the commands act on it.
    weak var textView: NSTextView?

    var language: Language? {
        Language.forFile(url)
    }

    var payload: Payload {
        Payload(path: path, pinned: isPinned)
    }

    var document: FileDocument? {
        if case .text(let document) = content {
            return document
        }
        return nil
    }

    init(path: String, url: URL, isPinned: Bool, line: Int? = nil) {
        self.path = path
        self.url = url
        self.isPinned = isPinned
        requestedLine = line
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
        return true
    }
}
