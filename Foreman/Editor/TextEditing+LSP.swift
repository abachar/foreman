import Foundation
import LanguageServerProtocol

/// editor R38: LSP positions and `NSRange` locations, both ways.
///
/// The conversion is short because the two agree on the unit: LSP counts UTF-16 code units in
/// `character` (its default, and Foreman announces nothing else — R38), which is exactly what
/// `NSString` and `NSRange` count. The only real difference is the line base — LSP counts from 0,
/// `TextEditing.Position` from 1 — so this reuses the editor's own pure helpers rather than
/// walking the text a second way.
///
/// Both types are called `Position`, so both are spelled out here: inside this extension the bare
/// name would mean `TextEditing.Position`.
nonisolated extension TextEditing {
    /// The LSP position of `location` in `text`.
    static func lspPosition(at location: Int, in text: NSString) -> LanguageServerProtocol.Position {
        let position = position(at: location, in: text)
        return LanguageServerProtocol.Position(line: position.line - 1, character: position.column)
    }

    /// Where an LSP position sits in `text`, clamped like `location(of:in:)`.
    ///
    /// A negative line or character cannot come from a well-formed server, but it costs one `max`
    /// to land on the first line instead of before the text.
    static func location(ofLSP position: LanguageServerProtocol.Position, in text: NSString) -> Int {
        location(
            of: TextEditing.Position(line: max(position.line, 0) + 1, column: max(position.character, 0)),
            in: text)
    }
}
