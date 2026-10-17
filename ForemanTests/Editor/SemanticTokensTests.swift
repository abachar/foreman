import Foundation
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R58–R60: the server's relative array into ranges and roles, a delta into the next
/// array, and the store the highlighter's provider reads.
struct SemanticTokensTests {
    private let legend = SemanticTokensLegend(
        tokenTypes: ["class", "property", "method", "variable", "parameter", "annotation", "event"],
        tokenModifiers: ["declaration", "static", "deprecated", "readonly"])

    /// `[deltaLine, deltaStart, length, type, modifiers]` per token.
    private func data(_ rows: [[UInt32]]) -> [UInt32] {
        rows.flatMap { $0 }
    }

    /// The protocol's edit, decoded as the server sends it (the type has no other initializer).
    private func edit(_ start: Int, _ deleteCount: Int, _ data: [UInt32]?) throws -> SemanticTokensEdit {
        let json = data.map { "\"data\": \($0)," } ?? ""
        return try JSONDecoder().decode(
            SemanticTokensEdit.self,
            from: Data(#"{ \#(json) "start": \#(start), "deleteCount": \#(deleteCount) }"#.utf8))
    }

    /// R58: one line, then another; the second token of a line is relative to the first.
    @Test func decodesRelativePositionsIntoRanges() {
        let text = "class Foo {\n  int count = size();\n}\n" as NSString
        // `Foo` declared (class, declaration); `count` (property, declaration); `size` (method).
        let tokens = SemanticTokenDecoder.tokens(
            data: data([[0, 6, 3, 0, 0b1], [1, 6, 5, 1, 0b1], [0, 8, 4, 2, 0]]), legend: legend, text: text)
        #expect(
            tokens.map(\.range) == [
                NSRange(location: 6, length: 3), NSRange(location: 18, length: 5), NSRange(location: 26, length: 4),
            ])
        #expect(tokens.map(\.role) == [.type, .property, nil])
        #expect(text.substring(with: tokens[2].range) == "size")
    }

    /// R38, R58: positions are UTF-16 units, which an astral character counts as two of.
    @Test func countsAstralCharactersAsTwoUnits() {
        let text = "😀 a.b" as NSString
        let tokens = SemanticTokenDecoder.tokens(data: data([[0, 5, 1, 1, 0]]), legend: legend, text: text)
        #expect(tokens.count == 1)
        #expect(text.substring(with: tokens[0].range) == "b")
    }

    /// R58: a token past the text, on a missing line, empty, or of an unknown type is left out.
    @Test func clampsAndDropsWhatTheTextCannotHold() {
        let text = "ab\ncd" as NSString
        let tokens = SemanticTokenDecoder.tokens(
            data: data([[0, 1, 10, 1, 0], [0, 1, 0, 1, 0], [1, 0, 2, 9, 0], [0, 0, 2, 1, 0], [5, 0, 2, 1, 0]]),
            legend: legend, text: text)
        // Clamped to the line's end, the empty and the unknown dropped, the missing line dropped.
        #expect(tokens.map(\.range) == [NSRange(location: 1, length: 2), NSRange(location: 3, length: 2)])
        #expect(SemanticTokenDecoder.tokens(data: [], legend: legend, text: text).isEmpty)
        #expect(SemanticTokenDecoder.tokens(data: [0, 0, 1], legend: legend, text: text).isEmpty)
    }

    /// R60: a type R60 has no opinion about keeps the capture's colour — it yields no token.
    @Test func typesWithoutAnOpinionYieldNoToken() {
        let text = "x" as NSString
        #expect(SemanticTokenDecoder.tokens(data: data([[0, 0, 1, 6, 0]]), legend: legend, text: text).isEmpty)
    }

    /// R60: the roles and the traits, by type and modifier.
    @Test func mapsTypesAndModifiersToRoles() throws {
        func role(_ type: String, _ modifiers: Set<String> = []) -> HighlightRole?? {
            SemanticTokenDecoder.role(ofType: type, modifiers: modifiers)?.role
        }
        #expect(role("property") == .some(.property))
        #expect(role("recordComponent") == .some(.property))
        #expect(role("enumMember") == .some(.constant))
        #expect(role("variable") == .some(nil))
        #expect(role("variable", ["static", "readonly"]) == .some(.constant))
        #expect(role("parameter") == .some(nil))
        #expect(role("method") == .some(nil))
        #expect(role("method", ["declaration"]) == .some(.function))
        #expect(role("function", ["definition"]) == .some(.function))
        #expect(role("class") == .some(nil))
        #expect(role("class", ["declaration"]) == .some(.type))
        #expect(role("record", ["declaration"]) == .some(.type))
        #expect(role("annotation") == .some(.attribute))
        #expect(role("keyword") == .some(.keyword))
        #expect(role("modifier") == .some(.keyword))
        #expect(role("string") == .some(.string))
        #expect(SemanticTokenDecoder.role(ofType: "event", modifiers: []) == nil)
        let deprecated = try #require(SemanticTokenDecoder.role(ofType: "method", modifiers: ["deprecated"]))
        #expect(deprecated.traits == [.strikethrough])
        #expect(deprecated.role == nil)
    }

    /// R58: a delta's edits replace slices of the previous array, from the highest start down.
    @Test func appliesADeltaToThePreviousArray() throws {
        let previous: [UInt32] = [0, 0, 1, 1, 0, 1, 0, 2, 2, 0, 1, 0, 3, 3, 0]
        let inserted = SemanticTokenDecoder.apply(
            [try edit(5, 0, [9, 9, 9, 9, 9])], to: previous)
        #expect(inserted == [0, 0, 1, 1, 0, 9, 9, 9, 9, 9, 1, 0, 2, 2, 0, 1, 0, 3, 3, 0])
        let deleted = SemanticTokenDecoder.apply(
            [try edit(0, 5, nil)], to: previous)
        #expect(deleted == [1, 0, 2, 2, 0, 1, 0, 3, 3, 0])
        let replacedEnd = SemanticTokenDecoder.apply(
            [try edit(10, 5, [7, 7, 7, 7, 7])], to: previous)
        #expect(replacedEnd == [0, 0, 1, 1, 0, 1, 0, 2, 2, 0, 7, 7, 7, 7, 7])
        // Two edits in one delta: applied in descending order whatever the order sent.
        let both = SemanticTokenDecoder.apply(
            [
                try edit(0, 5, nil),
                try edit(10, 5, nil),
            ], to: previous)
        #expect(both == [1, 0, 2, 2, 0])
        // An edit past the end is clamped, never a crash.
        let past = SemanticTokenDecoder.apply(
            [try edit(99, 5, [1])], to: previous)
        #expect(past == previous + [1])
    }

    /// R58: an empty last line counts, an unterminated one starts none.
    @Test func lineStartsFollowTheTerminators() {
        #expect(SemanticTokenDecoder.lineStarts(of: "") == [0])
        #expect(SemanticTokenDecoder.lineStarts(of: "a") == [0])
        #expect(SemanticTokenDecoder.lineStarts(of: "a\nb") == [0, 2])
        #expect(SemanticTokenDecoder.lineStarts(of: "a\nb\n") == [0, 2, 4])
        #expect(SemanticTokenDecoder.lineStarts(of: "a\r\nb") == [0, 3])
    }

    /// R59: the store answers the token covering a Neon token's start, and names what changed.
    @MainActor
    @Test func theStoreCoversAndDiffs() {
        let store = SemanticTokenStore()
        let field = SemanticToken(range: NSRange(location: 10, length: 5), role: .property, traits: [])
        let call = SemanticToken(range: NSRange(location: 20, length: 4), role: nil, traits: [])
        let first = store.replace(with: [field, call])
        #expect(first == IndexSet(integersIn: 10..<15).union(IndexSet(integersIn: 20..<24)))
        #expect(store.token(covering: NSRange(location: 10, length: 5)) == field)
        #expect(store.token(covering: NSRange(location: 12, length: 1)) == field)
        #expect(store.token(covering: NSRange(location: 15, length: 1)) == nil)
        #expect(store.token(covering: NSRange(location: 0, length: 3)) == nil)
        #expect(store.token(covering: NSRange(location: 20, length: 4)) == call)
        // The same batch again changes nothing; a repainted token changes its range only.
        #expect(store.replace(with: [field, call]).isEmpty)
        let repainted = SemanticToken(range: NSRange(location: 20, length: 4), role: .function, traits: [])
        #expect(store.replace(with: [field, repainted]) == IndexSet(integersIn: 20..<24))
        #expect(store.replace(with: []) == IndexSet(integersIn: 10..<15).union(IndexSet(integersIn: 20..<24)))
    }
}
