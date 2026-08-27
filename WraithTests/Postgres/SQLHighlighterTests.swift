import AppKit
import Foundation
import Testing

@testable import Wraith

/// postgres R9 (plan B colorer): the tokens of a buffer.
struct SQLHighlighterTests {
    private func roles(_ text: String) -> [(String, HighlightRole)] {
        SQLHighlighter.tokens(in: text).map { ((text as NSString).substring(with: $0.range), $0.role) }
    }

    @Test func colorsKeywordsTypesStringsCommentsNumbersAndParameters() {
        let found = roles("SELECT id::int4, 'it''s' FROM t -- note\nWHERE a = $1 AND b > 2.5 /* c */")
        #expect(
            found.map(\.0) == ["SELECT", "int4", "'it''s'", "FROM", "-- note", "WHERE", "$1", "AND", "2.5", "/* c */"])
        #expect(
            found.map(\.1) == [
                .keyword, .type, .string, .keyword, .comment, .keyword, .variable, .keyword, .number, .comment,
            ])
    }

    @Test func wordsContainingKeywordsAndDigitsAreNotSplit() {
        #expect(roles("selected from2 t1").map(\.0) == [])
        #expect(roles("x1 select").map(\.0) == ["select"])
    }

    @Test func unterminatedStringAndCommentRunToTheEnd() {
        #expect(roles("select 'open").map(\.0) == ["select", "'open"])
        #expect(roles("/* never").map(\.1) == [.comment])
    }

    @MainActor
    @Test func scrollableTextViewBuildsTheSubclass() {
        #expect(SQLTextView.scrollableTextView().documentView is SQLTextView)
    }
}
