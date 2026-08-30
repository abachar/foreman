import Foundation

/// The editing commands of editor R6 as pure transformations on a text and a selection.
///
/// Each returns the replacement for a range so the view applies it through `insertText`, which
/// keeps `NSTextView`'s own undo. Ranges are UTF-16 (`NSString`).
nonisolated enum TextEditing {
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        /// Where the selection goes after the edit.
        let selection: NSRange
    }

    /// editor R6: spaces or tabs, detected on the first 100 lines; default four spaces.
    static func detectIndent(_ text: String) -> String {
        var spaceWidths: [Int: Int] = [:]
        var tabs = 0
        for line in text.split(separator: "\n", maxSplits: 100, omittingEmptySubsequences: false).prefix(100) {
            if line.hasPrefix("\t") {
                tabs += 1
            } else {
                let width = line.prefix { $0 == " " }.count
                if width > 0 {
                    spaceWidths[width, default: 0] += 1
                }
            }
        }
        let spaces = spaceWidths.values.reduce(0, +)
        if tabs > spaces {
            return "\t"
        }
        let smallest = spaceWidths.keys.filter { $0 == 2 || $0 == 4 || $0 == 8 }.min()
        return String(repeating: " ", count: smallest ?? 4)
    }

    /// The whole lines touched by `selection` (a caret counts as its line).
    static func lineRange(of selection: NSRange, in text: NSString) -> NSRange {
        text.lineRange(for: selection)
    }

    /// agents R10b: the 1-based lines a non-empty selection covers; an end at column 0 does not
    /// count that line; `nil` for a caret.
    static func selectedLines(_ selection: NSRange, in text: NSString) -> ClosedRange<Int>? {
        guard selection.length > 0 else { return nil }
        let first = position(at: selection.location, in: text).line
        let end = position(at: NSMaxRange(selection), in: text)
        let last = end.column == 0 ? max(first, end.line - 1) : end.line
        return first...last
    }

    /// editor R6: `enter` keeps the indentation of the current line.
    static func newline(at selection: NSRange, in text: NSString) -> Edit {
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let content = text.substring(with: line)
        let indent = content.prefix { $0 == " " || $0 == "\t" }
        let replacement = "\n" + indent
        return Edit(
            range: selection, replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    /// editor R6: `cmd+]` / `cmd+[` on every selected line; unindent removes at most one unit.
    static func indent(_ selection: NSRange, in text: NSString, unit: String, outdent: Bool) -> Edit {
        let range = lineRange(of: selection, in: text)
        let lines = splitLines(text.substring(with: range))
        let changed = lines.map { line -> String in
            guard line != "\n", !line.isEmpty else { return line }
            if outdent {
                let leading = line.prefix { $0 == " " || $0 == "\t" }.count
                return String(line.dropFirst(min(leading, unit.count)))
            }
            return unit + line
        }
        let replacement = changed.joined()
        return Edit(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location, length: (replacement as NSString).length))
    }

    /// editor R6: `cmd+/` comments the lines, or uncomments them when all already are.
    static func toggleComment(_ selection: NSRange, in text: NSString, prefix: String) -> Edit {
        let range = lineRange(of: selection, in: text)
        let lines = splitLines(text.substring(with: range))
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let allCommented =
            !nonBlank.isEmpty && nonBlank.allSatisfy { $0.drop { $0 == " " || $0 == "\t" }.hasPrefix(prefix) }
        let minimumIndent = nonBlank.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let changed = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return line }
            if allCommented {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                var rest = line.dropFirst(indent.count).dropFirst(prefix.count)
                if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                return String(indent) + String(rest)
            }
            return String(line.prefix(minimumIndent)) + prefix + " " + String(line.dropFirst(minimumIndent))
        }
        let replacement = changed.joined()
        return Edit(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location, length: (replacement as NSString).length))
    }

    /// editor R6: `opt+↑` / `opt+↓` swap the selected lines with the neighbor line.
    static func moveLines(_ selection: NSRange, in text: NSString, up: Bool) -> Edit? {
        let range = lineRange(of: selection, in: text)
        if up {
            guard range.location > 0 else { return nil }
            let previous = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            let block = NSRange(location: previous.location, length: previous.length + range.length)
            let moved = withNewline(text.substring(with: range)) + text.substring(with: previous)
            return Edit(
                range: block, replacement: trimTrailingNewlineIfNeeded(moved, original: text.substring(with: block)),
                selection: NSRange(location: previous.location, length: range.length))
        }
        guard NSMaxRange(range) < text.length else { return nil }
        let next = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
        let block = NSRange(location: range.location, length: range.length + next.length)
        let moved = withNewline(text.substring(with: next)) + text.substring(with: range)
        let replacement = trimTrailingNewlineIfNeeded(moved, original: text.substring(with: block))
        return Edit(
            range: block, replacement: replacement,
            selection: NSRange(
                location: range.location + (withNewline(text.substring(with: next)) as NSString).length,
                length: range.length))
    }

    /// editor R8: a final newline when absent.
    static func withFinalNewline(_ text: String) -> String {
        text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
    }

    /// The UTF-16 offset of the start of a 1-based line, clamped to the end of the text.
    static func location(ofLine line: Int, in text: NSString) -> Int {
        var location = 0
        var current = 1
        while current < line, location < text.length {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
            current += 1
        }
        return min(location, text.length)
    }

    /// A 1-based line and a UTF-16 column (editor R29).
    struct Position: Equatable {
        let line: Int
        let column: Int
    }

    /// editor R29: where `location` sits, by line and column.
    static func position(at location: Int, in text: NSString) -> Position {
        let clamped = min(max(location, 0), text.length)
        let line = text.lineRange(for: NSRange(location: clamped, length: 0))
        var count = 1
        var cursor = 0
        while cursor < line.location {
            cursor = NSMaxRange(text.lineRange(for: NSRange(location: cursor, length: 0)))
            count += 1
        }
        return Position(line: count, column: clamped - line.location)
    }

    /// editor R29: `position` carried over to another text, clamped: a line past the end goes to
    /// the last line, a column past the line to its end, an empty text to 0.
    static func location(of position: Position, in text: NSString) -> Int {
        let start = location(ofLine: position.line, in: text)
        let line = text.lineRange(for: NSRange(location: start, length: 0))
        var end = NSMaxRange(line)
        if end > line.location, text.character(at: end - 1) == 0x0A {
            end -= 1
        }
        return min(start + position.column, end)
    }

    /// Each line with its `\n` attached, the last one bare when the text does not end in one, and
    /// never an empty trailing element.
    ///
    /// Splits on the `\n` grapheme only, like the text views.
    private static func splitLines(_ text: String) -> [String] {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        var lines = parts.dropLast().map { String($0) + "\n" }
        if let last = parts.last, !last.isEmpty {
            lines.append(String(last))
        }
        return lines
    }

    private static func withNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func trimTrailingNewlineIfNeeded(_ text: String, original: String) -> String {
        original.hasSuffix("\n") || !text.hasSuffix("\n") ? text : String(text.dropLast())
    }
}
