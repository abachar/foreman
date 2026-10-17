import Foundation
import Testing

@testable import Foreman

/// Which files a diff renders when it loads (git R16, audit 2026-10-17 M2).
struct GitDiffModelTests {
    private func file(_ path: String, lines: Int) -> FileDiff {
        FileDiff.added(path: path, content: (0..<lines).map { "line \($0)" }.joined(separator: "\n"))
    }

    private func binary(_ path: String) -> FileDiff {
        FileDiff(oldPath: path, newPath: path, isBinary: true)
    }

    /// Three files over the threshold between them, so every file starts folded.
    private var large: GitDiff {
        let third = GitDiff.collapseThreshold / 2
        return GitDiff(files: [
            file("a.swift", lines: third), binary("b.png"), file("c.swift", lines: third),
            file("d.swift", lines: third),
        ])
    }

    @Test func aSmallDiffRendersEveryTextFileInOrder() {
        let diff = GitDiff(files: [file("a.swift", lines: 3), binary("b.png"), file("c.swift", lines: 2)])
        #expect(!diff.isLarge)
        #expect(GitDiffModel.filesToRender(diff, expanded: []).map(\.id) == ["a.swift", "c.swift"])
    }

    @Test func aLargeDiffRendersNothingWhileEveryFileIsFolded() {
        #expect(large.isLarge)
        #expect(GitDiffModel.filesToRender(large, expanded: []).isEmpty)
    }

    @Test func aLargeDiffRendersOnlyTheOpenedFilesInDiffOrder() {
        let files = GitDiffModel.filesToRender(large, expanded: ["d.swift", "a.swift", "b.png"])
        #expect(files.map(\.id) == ["a.swift", "d.swift"])
    }

    // MARK: - git R17

    @Test func aRefreshRendersOnlyWhatChangedOrWasNeverRendered() {
        let before = GitDiff(files: [file("a.swift", lines: 3), file("b.swift", lines: 2)])
        let unchanged = file("a.swift", lines: 3)
        let changed = file("b.swift", lines: 4)
        let new = file("c.swift", lines: 1)
        #expect(!GitDiffModel.needsRender(unchanged, previous: before, isRendered: true))
        #expect(GitDiffModel.needsRender(changed, previous: before, isRendered: true))
        #expect(GitDiffModel.needsRender(new, previous: before, isRendered: true))
        #expect(GitDiffModel.needsRender(unchanged, previous: before, isRendered: false))
        #expect(GitDiffModel.needsRender(unchanged, previous: nil, isRendered: true))
    }

    // MARK: - git R13b, R16 (M23 23.11)

    private func hunk(_ id: String, rows: Int) -> RenderedHunk {
        RenderedHunk(id: id, header: "@@ \(id) @@", rows: (0..<rows).map { RenderedRow(id: $0, left: nil, right: nil) })
    }

    @Test func rowsAreFlatAndInOrder() {
        let diff = GitDiff(files: [file("a.swift", lines: 3), file("b.swift", lines: 2)])
        let rendered = ["a.swift": [hunk("1-1", rows: 2), hunk("9-9", rows: 1)], "b.swift": [hunk("1-1", rows: 2)]]
        let rows = GitDiffModel.rows(of: diff, expanded: { $0.id == "a.swift" }, rendered: rendered)
        #expect(
            rows.map(\.id) == [
                "file:a.swift",
                "hunk:a.swift:1-1", "row:a.swift:1-1:0", "row:a.swift:1-1:1",
                "hunk:a.swift:9-9", "row:a.swift:9-9:0",
                "file:b.swift",
            ])
    }

    @Test func aFoldedFileContributesItsHeaderOnly() {
        let diff = GitDiff(files: [file("a.swift", lines: 3)])
        let rows = GitDiffModel.rows(of: diff, expanded: { _ in false }, rendered: ["a.swift": [hunk("1-1", rows: 3)]])
        #expect(rows.map(\.id) == ["file:a.swift"])
    }

    @Test func aBinaryFileContributesOneLine() {
        let diff = GitDiff(files: [binary("b.png")])
        let rows = GitDiffModel.rows(of: diff, expanded: { _ in true }, rendered: [:])
        #expect(rows.map(\.id) == ["file:b.png", "binary:b.png"])
    }

    @Test func rowIdsAreUniqueAcrossHunksAndFiles() {
        // Two new files: both hunks are `0-1`, both first rows are 0.
        let diff = GitDiff(files: [file("a.swift", lines: 2), file("b.swift", lines: 2)])
        let rendered = ["a.swift": [hunk("0-1", rows: 2)], "b.swift": [hunk("0-1", rows: 2)]]
        let ids = GitDiffModel.rows(of: diff, expanded: { _ in true }, rendered: rendered).map(\.id)
        #expect(ids.count == 8)
        #expect(Set(ids).count == ids.count)
    }
}
