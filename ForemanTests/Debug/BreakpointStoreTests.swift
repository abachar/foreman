import Foundation
import Testing

@testable import Foreman

/// The breakpoints of a workspace (debug R4): a plain value, no window, no session.
struct BreakpointStoreTests {
    private let root = URL(filePath: "/ws")

    private func store(_ lines: [String: [Int]]) -> BreakpointStore {
        BreakpointStore(state: BreakpointStore.State(breakpoints: lines))
    }

    @Test func toggleAddsThenRemovesAndKeepsTheLinesInOrder() {
        var store = BreakpointStore()
        store.toggle(30, in: "A.swift")
        store.toggle(10, in: "A.swift")
        #expect(store.lines == ["A.swift": [10, 30]])
        store.toggle(30, in: "A.swift")
        #expect(store.lines == ["A.swift": [10]])
        store.toggle(10, in: "A.swift")
        #expect(store.lines.isEmpty)
    }

    /// Lines inserted above move the breakpoint down; lines removed above move it up.
    @Test func aBreakpointMovesWithAnInsertionAndADeletionAbove() throws {
        // "a\nb\nc\nd\n": the breakpoint is on line 3 ("c").
        let starts = [0, 2, 4, 6, 8]
        var store = store(["A.swift": [3]])
        // Typing "x\ny\nz" at the end of line 1 puts two breaks in: "c" is on line 5.
        let insertion = try #require(
            BreakpointStore.Edit.make(
                oldStarts: starts, oldTextLength: 8, location: 1, oldLength: 0, replacement: "x\ny\nz"))
        let moved = store.apply(insertion, in: "A.swift")
        #expect(moved)
        #expect(store.lines == ["A.swift": [5]])
        // Deleting "\nb", the break after line 1 and the text of line 2: "c" is on line 2.
        let deletion = try #require(
            BreakpointStore.Edit.make(oldStarts: starts, oldTextLength: 8, location: 1, oldLength: 2, replacement: ""))
        var other = self.store(["A.swift": [3]])
        let shifted = other.apply(deletion, in: "A.swift")
        #expect(shifted)
        #expect(other.lines == ["A.swift": [2]])
    }

    @Test func aBreakpointOnADeletedLineGoesAndOneAboveStays() throws {
        let starts = [0, 2, 4, 6, 8]
        // Deleting "b\nc\n" from the start of line 2 removes lines 2 and 3.
        let edit = try #require(
            BreakpointStore.Edit.make(oldStarts: starts, oldTextLength: 8, location: 2, oldLength: 4, replacement: ""))
        var store = store(["A.swift": [1, 2, 3, 4]])
        _ = store.apply(edit, in: "A.swift")
        #expect(store.lines == ["A.swift": [1, 2]])
    }

    /// A line break typed at the start of a line pushes that line, breakpoint included, down.
    @Test func aBreakTypedAtTheStartOfALinePushesItsBreakpointDown() throws {
        let starts = [0, 2, 4]
        let edit = try #require(
            BreakpointStore.Edit.make(oldStarts: starts, oldTextLength: 6, location: 2, oldLength: 0, replacement: "\n")
        )
        var store = store(["A.swift": [1, 2]])
        _ = store.apply(edit, in: "A.swift")
        #expect(store.lines == ["A.swift": [1, 3]])
    }

    @Test func anEditWithoutALineBreakOrOverTheWholeTextMovesNothing() {
        let starts = [0, 2, 4]
        #expect(
            BreakpointStore.Edit.make(oldStarts: starts, oldTextLength: 6, location: 1, oldLength: 0, replacement: "x")
                == nil)
        // A reload or a formatter replaces everything: the lines keep their numbers.
        #expect(
            BreakpointStore.Edit.make(
                oldStarts: starts, oldTextLength: 6, location: 0, oldLength: 6, replacement: "a\n\n\nb\n") == nil)
    }

    @Test func aLinePastTheEndIsDroppedAtRestoration() {
        var store = store(["A.swift": [2, 9, 12], "B.swift": [1]])
        let dropped = store.drop(pastLine: BreakpointStore.lineCount(of: "a\nb\nc\n"), in: "A.swift")
        #expect(dropped)
        #expect(store.lines == ["A.swift": [2], "B.swift": [1]])
        let again = store.drop(pastLine: 3, in: "A.swift")
        #expect(!again)
        #expect(BreakpointStore.lineCount(of: "a\nb") == 2)
        #expect(BreakpointStore.lineCount(of: "a\nb\n") == 2)
        #expect(BreakpointStore.lineCount(of: "") == 1)
    }

    /// The `debug` section of `state.json`: relative to the root, never an absolute path.
    @Test func persistsAndRestoresRelativeToTheRoot() throws {
        let url = root.appending(path: "Foreman/Editor/EditorFeature.swift")
        let key = try #require(BreakpointStore.key(for: url, root: root))
        #expect(key == "Foreman/Editor/EditorFeature.swift")
        var store = BreakpointStore()
        store.toggle(42, in: key)
        store.toggle(7, in: key)

        let data = try JSONEncoder().encode(store.state)
        let restored = BreakpointStore(state: try JSONDecoder().decode(BreakpointStore.State.self, from: data))
        #expect(restored.lines == [key: [7, 42]])
        #expect(restored.file(key, root: root).path == "/ws/Foreman/Editor/EditorFeature.swift")
    }

    @Test func aFileOutsideTheRootOrTheRootItselfTakesNone() {
        #expect(BreakpointStore.key(for: URL(filePath: "/elsewhere/A.java"), root: root) == nil)
        #expect(BreakpointStore.key(for: URL(filePath: "/ws-other/A.java"), root: root) == nil)
        #expect(BreakpointStore.key(for: root, root: root) == nil)
    }

    @Test func aRestoredStateDropsNonsense() {
        let store = store(["A.swift": [3, 3, 0, -2, 1], "Empty.swift": []])
        #expect(store.lines == ["A.swift": [1, 3]])
    }

    /// debug R4, R9: one body per file, the path and the lines in order.
    @Test func setBreakpointsBodyPerFile() {
        let store = store(["b/B.swift": [4], "a/A.swift": [20, 3]])
        let files = store.files(root: root)
        #expect(files.map(\.path) == ["/ws/a/A.swift", "/ws/b/B.swift"])
        let body = files[0].arguments
        #expect(body.source.path == "/ws/a/A.swift")
        #expect(body.breakpoints.map(\.line) == [3, 20])
    }

    /// debug R4: filled when the adapter verified the line, hollow before a session and when it refused.
    @Test func verifiedAndHollowFollowTheAnswer() {
        var store = store(["A.swift": [3, 8]])
        #expect(store.marks(in: "A.swift") == [3: false, 8: false])
        let answer = DAPSetBreakpointsResponse(breakpoints: [
            DAPBreakpoint(verified: true, line: 3), DAPBreakpoint(verified: false, line: 8, message: "no code"),
        ])
        store.record(answer, requested: [3, 8], in: "A.swift")
        #expect(store.marks(in: "A.swift") == [3: true, 8: false])
        // The session ends: every dot is hollow again.
        store.forgetVerification()
        #expect(store.marks(in: "A.swift") == [3: false, 8: false])
    }

    /// An answer for lines that changed since is stale: a later request answers for them.
    @Test func aStaleAnswerIsIgnoredAndAShortOneLeavesTheRestHollow() {
        var store = store(["A.swift": [3, 8]])
        store.record(
            DAPSetBreakpointsResponse(breakpoints: [DAPBreakpoint(verified: true)]), requested: [3], in: "A.swift")
        #expect(store.marks(in: "A.swift") == [3: false, 8: false])
        store.record(
            DAPSetBreakpointsResponse(breakpoints: [DAPBreakpoint(verified: true)]), requested: [3, 8], in: "A.swift")
        #expect(store.marks(in: "A.swift") == [3: true, 8: false])
        // Toggling a line forgets what was verified for the file.
        store.toggle(8, in: "A.swift")
        #expect(store.marks(in: "A.swift") == [3: false])
    }
}
