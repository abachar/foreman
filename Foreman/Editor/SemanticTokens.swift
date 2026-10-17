import Foundation
import LanguageServerProtocol

/// What a language server says about one span of text (editor R58–R60): where it is, the role it
/// paints with — `nil` is the code's own text — and the traits that are not a colour.
nonisolated struct SemanticToken: Equatable, Sendable {
    struct Traits: OptionSet, Sendable, Hashable {
        let rawValue: UInt8
        /// R60: `deprecated`.
        static let strikethrough = Traits(rawValue: 1)
    }

    let range: NSRange
    let role: HighlightRole?
    let traits: Traits
}

/// editor R58, R60: the protocol's arrays and legend into Foreman's tokens.
///
/// The relative array into tokens, a delta into the next array, and a type and its modifiers
/// into a role. Pure, so it runs off the main actor (R45) and is tested on fixtures.
nonisolated enum SemanticTokenDecoder {
    /// R58: the edits of a delta applied to the previous array, highest `start` first so each
    /// edit's offsets still mean what the server meant.
    static func apply(_ edits: [SemanticTokensEdit], to data: [UInt32]) -> [UInt32] {
        var data = data
        for edit in edits.sorted(by: { $0.start > $1.start }) {
            let start = min(Int(edit.start), data.count)
            let end = min(start + Int(edit.deleteCount), data.count)
            data.replaceSubrange(start..<end, with: edit.data ?? [])
        }
        return data
    }

    /// R58, R60: the relative five-tuples into absolute UTF-16 ranges and roles, sorted by location.
    ///
    /// A token on a line the text does not have, or past its end, is clamped; an empty
    /// one is dropped; a type the legend does not name (a server ahead of its legend) too; a type
    /// R60 has no opinion about is dropped as well, so the capture's colour stands.
    static func tokens(data: [UInt32], legend: SemanticTokensLegend, text: NSString) -> [SemanticToken] {
        let lineStarts = lineStarts(of: text)
        var tokens: [SemanticToken] = []
        tokens.reserveCapacity(data.count / 5)
        var line = 0
        var character = 0
        var index = 0
        while index + 4 < data.count {
            let deltaLine = Int(data[index])
            let deltaStart = Int(data[index + 1])
            let length = Int(data[index + 2])
            let typeIndex = Int(data[index + 3])
            let modifierBits = data[index + 4]
            index += 5
            line += deltaLine
            character = deltaLine == 0 ? character + deltaStart : deltaStart
            guard line < lineStarts.count, typeIndex < legend.tokenTypes.count, length > 0 else { continue }
            let lineStart = lineStarts[line]
            let lineEnd = line + 1 < lineStarts.count ? lineStarts[line + 1] : text.length
            let location = min(lineStart + character, lineEnd)
            // R58: no multiline tokens were announced; one that crosses the line is cut at its end.
            let end = min(location + length, lineEnd)
            guard end > location else { continue }
            var modifiers: Set<String> = []
            for (bit, name) in legend.tokenModifiers.enumerated() where modifierBits & (1 << UInt32(bit)) != 0 {
                modifiers.insert(name)
            }
            guard let (role, traits) = role(ofType: legend.tokenTypes[typeIndex], modifiers: modifiers) else {
                continue
            }
            tokens.append(
                SemanticToken(range: NSRange(location: location, length: end - location), role: role, traits: traits))
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    /// R60: what a type and its modifiers become; `nil` when the rule has no opinion.
    ///
    /// The role is R12's; `nil` inside the pair is the code's own text (design R9 `codeText`),
    /// which is how a use of a class or a call of a method is painted — IntelliJ colours the
    /// declaration, never the use.
    static func role(
        ofType type: String, modifiers: Set<String>
    ) -> (role: HighlightRole?, traits: SemanticToken.Traits)? {
        let declared = modifiers.contains("declaration") || modifiers.contains("definition")
        var traits: SemanticToken.Traits = []
        if modifiers.contains("deprecated") {
            traits.insert(.strikethrough)
        }
        let role: HighlightRole?
        switch type {
        case "property", "recordComponent", "annotationMember":
            role = .property
        case "enumMember":
            role = .constant
        case "variable":
            role = modifiers.contains("static") && modifiers.contains("readonly") ? .constant : nil
        case "parameter", "namespace":
            role = nil
        case "method", "function", "macro":
            role = declared ? .function : nil
        case "class", "interface", "enum", "struct", "type", "typeParameter", "record":
            role = declared ? .type : nil
        case "annotation":
            role = .attribute
        case "keyword", "modifier":
            role = .keyword
        case "string", "regexp":
            role = .string
        case "number":
            role = .number
        case "comment":
            role = .comment
        case "operator":
            role = .operator
        default:
            return nil
        }
        return (role, traits)
    }

    /// The UTF-16 offset where each line starts, line `i` at `[i]`.
    static func lineStarts(of text: NSString) -> [Int] {
        var starts = [0]
        var location = 0
        while location < text.length {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            // `lineRange` includes the terminator: a terminated line starts another, even an empty
            // last one (LSP counts it); an unterminated last line starts none.
            if location > range.location, isLineBreak(text, before: location) {
                starts.append(location)
            }
        }
        return starts
    }

    private static func isLineBreak(_ text: NSString, before location: Int) -> Bool {
        guard location > 0 else { return false }
        let unit = text.character(at: location - 1)
        return unit == 0x0A || unit == 0x0D
    }
}

/// editor R59: the server's tokens for one text view, read by Neon's attribute provider.
///
/// One per `EditorTextView.Coordinator`, not per file: two groups showing one file have two
/// text views, each with its own highlighter, and both are fed by the same answer.
@MainActor
final class SemanticTokenStore {
    private(set) var tokens: [SemanticToken] = []

    /// R59: the token covering the start of `range`, if any — a binary search on the sorted list.
    func token(covering range: NSRange) -> SemanticToken? {
        var low = 0
        var high = tokens.count - 1
        var candidate: SemanticToken?
        while low <= high {
            let middle = (low + high) / 2
            let token = tokens[middle]
            if token.range.location <= range.location {
                candidate = token
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard let candidate, NSLocationInRange(range.location, candidate.range) else { return nil }
        return candidate
    }

    /// R59: the new batch in, and the ranges whose token changed — added, removed or repainted —
    /// which is what the highlighter must ask about again.
    @discardableResult
    func replace(with new: [SemanticToken]) -> IndexSet {
        let before = Set(tokens)
        let after = Set(new)
        var changed = IndexSet()
        for token in before.symmetricDifference(after) where token.range.length > 0 {
            changed.insert(integersIn: token.range.location..<NSMaxRange(token.range))
        }
        tokens = new
        return changed
    }
}

extension SemanticToken: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(range.location)
        hasher.combine(range.length)
        hasher.combine(role)
        hasher.combine(traits)
    }
}
