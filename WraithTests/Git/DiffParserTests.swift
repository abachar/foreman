import Foundation
import Testing

@testable import Wraith

/// `diff --no-color --no-ext-diff -M` over real fixtures (git R13, R14, R16).
struct DiffParserTests {
    private let simple = """
        diff --git a/src/app.swift b/src/app.swift
        index e69de29..8b13789 100644
        --- a/src/app.swift
        +++ b/src/app.swift
        @@ -1,3 +1,4 @@ struct App {
         let a = 1
        -let b = 2
        +let b = 3
        +let c = 4
         let d = 5

        """

    @Test func readsOneHunkWithBothSidesNumbered() throws {
        let diff = DiffParser.parse(simple)
        let file = try #require(diff.files.first)
        #expect(file.oldPath == "src/app.swift")
        #expect(file.newPath == "src/app.swift")
        #expect(!file.isRename)
        #expect(!file.isBinary)
        let hunk = try #require(file.hunks.first)
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (1, 3, 1, 4))
        #expect(hunk.heading == "struct App {")
        #expect(hunk.header == "@@ -1,3 +1,4 @@ struct App {")
        #expect(
            hunk.lines == [
                DiffLine(kind: .context, text: "let a = 1", oldNumber: 1, newNumber: 1),
                DiffLine(kind: .removed, text: "let b = 2", oldNumber: 2, newNumber: nil),
                DiffLine(kind: .added, text: "let b = 3", oldNumber: nil, newNumber: 2),
                DiffLine(kind: .added, text: "let c = 4", oldNumber: nil, newNumber: 3),
                DiffLine(kind: .context, text: "let d = 5", oldNumber: 3, newNumber: 4),
            ])
    }

    @Test func readsSeveralHunksAndFiles() {
        let text = """
            diff --git a/a.txt b/a.txt
            --- a/a.txt
            +++ b/a.txt
            @@ -1 +1 @@
            -x
            +y
            @@ -10,2 +10,2 @@
             k
            -l
            +m
            diff --git a/b.txt b/b.txt
            --- a/b.txt
            +++ b/b.txt
            @@ -3,0 +4,1 @@
            +new
            """
        let diff = DiffParser.parse(text)
        #expect(diff.files.map(\.path) == ["a.txt", "b.txt"])
        #expect(diff.files[0].hunks.count == 2)
        #expect(diff.files[0].hunks[1].lines.map(\.oldNumber) == [10, 11, nil])
        #expect(diff.files[0].hunks[1].lines.map(\.newNumber) == [10, nil, 11])
        #expect(diff.files[1].hunks[0].lines == [DiffLine(kind: .added, text: "new", oldNumber: nil, newNumber: 4)])
        #expect(diff.lineCount == 6)
        #expect(!diff.isLarge)
    }

    @Test func readsAnAdditionADeletionARenameAndAModeChange() {
        let text = """
            diff --git a/new.txt b/new.txt
            new file mode 100644
            index 0000000..e69de29
            --- /dev/null
            +++ b/new.txt
            @@ -0,0 +1 @@
            +hello
            diff --git a/gone.txt b/gone.txt
            deleted file mode 100644
            index e69de29..0000000
            --- a/gone.txt
            +++ /dev/null
            @@ -1 +0,0 @@
            -bye
            diff --git a/old/name.txt b/new/name.txt
            similarity index 90%
            rename from old/name.txt
            rename to new/name.txt
            index 1111111..2222222 100644
            --- a/old/name.txt
            +++ b/new/name.txt
            @@ -1 +1 @@
            -a
            +b
            diff --git a/run.sh b/run.sh
            old mode 100644
            new mode 100755
            """
        let diff = DiffParser.parse(text)
        #expect(diff.files.count == 4)
        #expect(diff.files[0].oldPath == nil)
        #expect(diff.files[0].newPath == "new.txt")
        #expect(diff.files[1].oldPath == "gone.txt")
        #expect(diff.files[1].newPath == nil)
        #expect(diff.files[2].isRename)
        #expect(diff.files[2].oldPath == "old/name.txt")
        #expect(diff.files[2].newPath == "new/name.txt")
        #expect(diff.files[3].oldMode == "100644")
        #expect(diff.files[3].newMode == "100755")
        #expect(diff.files[3].hunks.isEmpty)
        #expect(GitDiffView.headerText(diff.files[0]) == "new.txt (new)")
        #expect(GitDiffView.headerText(diff.files[1]) == "gone.txt (deleted)")
        #expect(GitDiffView.headerText(diff.files[2]) == "old/name.txt \u{2192} new/name.txt")
        #expect(GitDiffView.headerText(diff.files[3]) == "run.sh")
    }

    @Test func readsABinaryFileAndAMissingFinalNewline() throws {
        let text = """
            diff --git a/logo.png b/logo.png
            index 1111111..2222222 100644
            Binary files a/logo.png and b/logo.png differ
            diff --git a/end.txt b/end.txt
            --- a/end.txt
            +++ b/end.txt
            @@ -1 +1 @@
            -last
            \\ No newline at end of file
            +last!
            \\ No newline at end of file
            """
        let diff = DiffParser.parse(text)
        #expect(diff.files[0].isBinary)
        let lines = try #require(diff.files[1].hunks.first?.lines)
        #expect(lines.map(\.hasNoNewline) == [true, true])
        #expect(lines.map(\.text) == ["last", "last!"])
        #expect(GitDiffModel.binaryText(old: 0, new: 2048).hasPrefix("binary, "))
    }

    @Test func skipsTheCommitHeaderOfShow() {
        let text = "feat: subject\n\n" + simple
        #expect(DiffParser.parse(text).files.map(\.path) == ["src/app.swift"])
        #expect(DiffParser.parse("").files.isEmpty)
    }

    @Test func anUntrackedFileBecomesOneHunkOfAddedLines() {
        let file = FileDiff.added(path: "x.txt", content: "a\nb\n")
        #expect(file.oldPath == nil)
        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].lines.map(\.text) == ["a", "b"])
        #expect(file.hunks[0].lines.map(\.newNumber) == [1, 2])
        #expect(FileDiff.added(path: "e", content: "").hunks.isEmpty)
    }

    @Test func aDiffOverFiveThousandLinesIsLarge() {
        let lines = (0..<5001).map { "+\($0)" }.joined(separator: "\n")
        let text = "diff --git a/big b/big\n--- a/big\n+++ b/big\n@@ -0,0 +1,5001 @@\n" + lines
        #expect(DiffParser.parse(text).isLarge)
    }

    // MARK: - Payload (git R14; layout R28)

    @Test func titlesAndArgumentsPerSource() {
        #expect(GitDiffPayload(repo: ".", source: .workingTree(path: "a/b.swift")).title == "a/b.swift (working tree)")
        #expect(GitDiffPayload(repo: ".", source: .staged(path: "a.swift")).title == "a.swift (staged)")
        #expect(
            GitDiffPayload(repo: ".", source: .commit(sha: "abc1234def", subject: "fix: x")).title == "abc1234 fix: x")
        #expect(
            GitDiffPayload(repo: ".", source: .workingTree(path: "-weird")).arguments
                == ["diff", "--no-color", "--no-ext-diff", "-M", "--", "-weird"])
        #expect(
            GitDiffPayload(repo: ".", source: .staged(path: "a")).arguments
                == ["diff", "--cached", "--no-color", "--no-ext-diff", "-M", "--", "a"])
        #expect(
            GitDiffPayload(repo: ".", source: .commit(sha: "abc", subject: "s")).arguments
                == ["show", "--format=%s", "--no-color", "--no-ext-diff", "-M", "abc", "--"])
        #expect(
            GitDiffPayload(repo: ".", source: .commitFile(sha: "abc", subject: "s", path: "p")).arguments
                == ["show", "--format=%s", "--no-color", "--no-ext-diff", "-M", "abc", "--", "p"])
    }

    @Test func roundtripsThePayloadAndRefusesAMalformedOne() {
        for payload in [
            GitDiffPayload(repo: "libs/core", source: .workingTree(path: "x.txt")),
            GitDiffPayload(repo: ".", source: .commitFile(sha: "abc", subject: "s", path: "p")),
        ] {
            #expect(GitDiffPayload.decode(payload.encoded()) == payload)
        }
        #expect(GitDiffPayload.decode("") == nil)
        #expect(GitDiffPayload.decode(#"{"repo":"."}"#) == nil)
        #expect(GitDiffPayload.decode(#"{"repo":".","source":{"unknown":{}}}"#) == nil)
    }

    @Test func objectsForBinarySizesPerSource() {
        let file = FileDiff(oldPath: "a.png", newPath: "a.png")
        #expect(GitDiffPayload(repo: ".", source: .workingTree(path: "a.png")).oldObject(for: file) == ":a.png")
        #expect(GitDiffPayload(repo: ".", source: .workingTree(path: "a.png")).newObjectIsWorktree)
        #expect(GitDiffPayload(repo: ".", source: .staged(path: "a.png")).oldObject(for: file) == "HEAD:a.png")
        #expect(GitDiffPayload(repo: ".", source: .staged(path: "a.png")).newObject(for: file) == ":a.png")
        #expect(
            GitDiffPayload(repo: ".", source: .commit(sha: "abc", subject: "")).oldObject(for: file) == "abc^:a.png")
        #expect(GitDiffPayload(repo: ".", source: .commit(sha: "abc", subject: "")).newObject(for: file) == "abc:a.png")
        #expect(
            GitDiffPayload(repo: ".", source: .commit(sha: "abc", subject: "")).oldObject(for: FileDiff(newPath: "n"))
                == nil)
    }
}

/// git R13b: the side-by-side pairing.
struct SideBySideTests {
    private func line(_ kind: DiffLine.Kind, _ text: String) -> DiffLine {
        DiffLine(kind: kind, text: text, oldNumber: kind == .added ? nil : 1, newNumber: kind == .removed ? nil : 1)
    }

    @Test func pairsRemovedRunsWithTheAddedRunThatFollows() {
        let hunk = Hunk(
            oldStart: 1, oldCount: 3, newStart: 1, newCount: 4, heading: "",
            lines: [
                line(.context, "a"), line(.removed, "b"), line(.removed, "c"), line(.added, "B"), line(.context, "d"),
                line(.added, "e"), line(.added, "f"),
            ])
        let rows = SideBySideRow.rows(of: hunk)
        #expect(rows.map { $0.left?.text } == ["a", "b", "c", "d", nil, nil])
        #expect(rows.map { $0.right?.text } == ["a", "B", nil, "d", "e", "f"])
    }

    @Test func anAddedRunBeforeARemovedOneStartsANewPair() {
        let hunk = Hunk(
            oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, heading: "",
            lines: [line(.added, "x"), line(.removed, "y")])
        let rows = SideBySideRow.rows(of: hunk)
        #expect(rows.map { $0.left?.text } == [nil, "y"])
        #expect(rows.map { $0.right?.text } == ["x", nil])
    }
}
