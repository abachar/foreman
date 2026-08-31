import Foundation

/// One diagnostic on an open file (editor R40, R41).
///
/// Foreman's own type, not the protocol's: `architecture.md` keeps third-party types near their
/// use, and everything below `LSPServers` — the tab, the gutter, the drawing — works on this.
/// Positions stay as LSP gave them (0-based line, UTF-16 character) and become an `NSRange` only
/// against a text, because the text moves and the diagnostic does not.
nonisolated struct EditorDiagnostic: Equatable, Sendable {
    /// The four the protocol defines, in its own order.
    enum Severity: Int, Sendable, CaseIterable {
        case error = 1
        case warning = 2
        case information = 3
        case hint = 4
    }

    let startLine: Int
    let startCharacter: Int
    let endLine: Int
    let endCharacter: Int
    let message: String
    let severity: Severity

    /// editor R41: the 1-based line the gutter marks.
    var line: Int {
        startLine + 1
    }

    /// The range to underline in `text`, or `nil` when there is nothing to draw on.
    ///
    /// A server may report a zero-width range — an error *at* a point rather than *over* one — and
    /// an underline of no width is invisible, so it is widened by one character, forward when the
    /// line has one to spare and backward otherwise. A diagnostic on an empty line gets none.
    func range(in text: NSString) -> NSRange? {
        let start = TextEditing.location(of: .init(line: startLine + 1, column: startCharacter), in: text)
        let end = TextEditing.location(of: .init(line: endLine + 1, column: endCharacter), in: text)
        var lower = min(start, end)
        var upper = max(start, end)
        if lower == upper {
            if upper < text.length, text.character(at: upper) != 0x0A {
                upper += 1
            } else if lower > 0, text.character(at: lower - 1) != 0x0A {
                lower -= 1
            } else {
                return nil
            }
        }
        return NSRange(location: lower, length: upper - lower)
    }

    /// editor R41: the first line of each diagnostic, keyed by the worst severity on it.
    ///
    /// Worst wins: a line carrying an error and a hint shows the error's colour, because the dot
    /// is one pixel of attention and it should point at the thing that breaks the build.
    static func severityByLine(_ diagnostics: [EditorDiagnostic]) -> [Int: Severity] {
        diagnostics.reduce(into: [:]) { result, diagnostic in
            let current = result[diagnostic.line]
            if current == nil || diagnostic.severity.rawValue < (current?.rawValue ?? .max) {
                result[diagnostic.line] = diagnostic.severity
            }
        }
    }

    /// editor R42: the diagnostic to show for a click or a pointer at `location`, the worst first.
    static func first(at location: Int, among diagnostics: [EditorDiagnostic], in text: NSString) -> EditorDiagnostic? {
        diagnostics
            .filter { NSLocationInRange(location, $0.range(in: text) ?? NSRange(location: -1, length: 0)) }
            .min { $0.severity.rawValue < $1.severity.rawValue }
    }
}
