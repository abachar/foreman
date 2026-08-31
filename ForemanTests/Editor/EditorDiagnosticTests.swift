import Foundation
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R40, R41: what a batch becomes, and where it lands in the text.
struct EditorDiagnosticTests {
    private let text = "let a = 1\nlet b = 2\n\nlet c = 3\n" as NSString

    private func diagnostic(
        line: Int, from: Int, toLine: Int? = nil, to: Int, severity: EditorDiagnostic.Severity = .error,
        message: String = "boom"
    ) -> EditorDiagnostic {
        EditorDiagnostic(
            startLine: line, startCharacter: from, endLine: toLine ?? line, endCharacter: to, message: message,
            severity: severity)
    }

    // MARK: - Ranges (R41)

    @Test func mapsARangeOntoTheText() {
        #expect(diagnostic(line: 1, from: 4, to: 5).range(in: text) == NSRange(location: 14, length: 1))
    }

    @Test func spansSeveralLines() {
        #expect(diagnostic(line: 0, from: 0, toLine: 1, to: 3).range(in: text) == NSRange(location: 0, length: 13))
    }

    /// A server may report an error *at* a point; an underline of no width is invisible.
    @Test func widensAZeroWidthRangeForward() {
        #expect(diagnostic(line: 0, from: 4, to: 4).range(in: text) == NSRange(location: 4, length: 1))
    }

    /// At the end of a line there is nothing forward but the newline: it takes the character before.
    @Test func widensBackwardAtTheEndOfALine() {
        #expect(diagnostic(line: 0, from: 9, to: 9).range(in: text) == NSRange(location: 8, length: 1))
    }

    /// An empty line has neither, and nothing is drawn.
    @Test func hasNoRangeOnAnEmptyLine() {
        #expect(diagnostic(line: 2, from: 0, to: 0).range(in: text) == nil)
    }

    /// A batch that arrives after an edit shortened the file is clamped into it.
    ///
    /// The clamp lands on the empty last line here, so there is nothing to underline and nothing
    /// is drawn: the stale batch disappears instead of misplacing itself.
    @Test func clampsARangePastTheEnd() {
        #expect(diagnostic(line: 99, from: 0, to: 4).range(in: text) == nil)
        // On a text whose last line has characters, the same clamp underlines that line.
        let unterminated = "let a = 1" as NSString
        #expect(diagnostic(line: 99, from: 0, to: 4).range(in: unterminated) == NSRange(location: 8, length: 1))
    }

    /// A server that inverts its range still gets an underline the right way round.
    @Test func ordersAnInvertedRange() {
        #expect(diagnostic(line: 0, from: 7, to: 2).range(in: text) == NSRange(location: 2, length: 5))
    }

    // MARK: - The gutter (R41)

    @Test func marksTheFirstLineOfEachDiagnostic() {
        let lines = EditorDiagnostic.severityByLine([
            diagnostic(line: 0, from: 0, to: 3, severity: .warning),
            diagnostic(line: 3, from: 0, to: 3, severity: .hint),
        ])
        #expect(lines == [1: .warning, 4: .hint])
    }

    /// The dot is one pixel of attention: it points at the thing that breaks the build.
    @Test func keepsTheWorstSeverityOnALine() {
        let lines = EditorDiagnostic.severityByLine([
            diagnostic(line: 1, from: 0, to: 3, severity: .hint),
            diagnostic(line: 1, from: 4, to: 5, severity: .error),
            diagnostic(line: 1, from: 6, to: 7, severity: .warning),
        ])
        #expect(lines == [2: .error])
    }

    // MARK: - Picking one under the pointer (R42)

    @Test func findsTheDiagnosticUnderALocation() throws {
        let diagnostics = [
            diagnostic(line: 0, from: 0, to: 3, message: "first"),
            diagnostic(line: 1, from: 0, to: 3, message: "second"),
        ]
        let found = try #require(EditorDiagnostic.first(at: 11, among: diagnostics, in: text))
        #expect(found.message == "second")
        #expect(EditorDiagnostic.first(at: 8, among: diagnostics, in: text) == nil)
    }

    @Test func prefersTheWorstOfTwoOverlapping() throws {
        let diagnostics = [
            diagnostic(line: 0, from: 0, to: 9, severity: .hint, message: "hint"),
            diagnostic(line: 0, from: 0, to: 9, severity: .error, message: "error"),
        ]
        #expect(try #require(EditorDiagnostic.first(at: 2, among: diagnostics, in: text)).message == "error")
    }

    // MARK: - The version filter (R40)

    /// A batch describing a text the user has already changed is dropped.
    @Test func dropsAStaleBatch() {
        #expect(LSPServers.isCurrent(3, of: 3))
        #expect(!LSPServers.isCurrent(2, of: 3))
    }

    /// The version is optional in the protocol; a server that sends none is trusted, there being
    /// nothing to compare it with.
    @Test func trustsABatchWithNoVersion() {
        #expect(LSPServers.isCurrent(nil, of: 7))
    }

    // MARK: - Conversion (R40)

    @Test func convertsTheProtocolsDiagnostic() {
        let converted = LSPServers.convert(
            Diagnostic(
                range: LSPRange(start: Position(line: 2, character: 4), end: Position(line: 2, character: 9)),
                severity: .warning, message: "unused"))
        #expect(converted == diagnostic(line: 2, from: 4, to: 9, severity: .warning, message: "unused"))
    }

    /// The severity is optional: the protocol leaves it to the client, and information is the
    /// least alarming thing to guess.
    @Test func fallsBackToInformationWithNoSeverity() {
        let converted = LSPServers.convert(
            Diagnostic(
                range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
                message: "?"))
        #expect(converted.severity == .information)
    }
}
