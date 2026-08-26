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
    /// editor R3: the 1-based line to reveal once the text is shown.
    var requestedLine: Int?
    private(set) var content: Content = .loading

    var language: Language? {
        Language.forFile(url)
    }

    var payload: Payload {
        Payload(path: path, pinned: isPinned)
    }

    init(path: String, url: URL, isPinned: Bool, line: Int? = nil) {
        self.path = path
        self.url = url
        self.isPinned = isPinned
        requestedLine = line
    }

    func load() async {
        do {
            content = .text(try await FileDocument.read(url))
        } catch {
            content = .failed(error)
        }
    }
}
