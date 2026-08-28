import Foundation
import Testing

@testable import Foreman

/// `status --porcelain=v2 -z --branch` over real records (git R27; edge cases: unborn, bytes).
struct StatusParserTests {
    private func parse(_ records: [String]) -> GitStatus {
        StatusParser.parse(Data(records.joined(separator: "\0").utf8 + [0]))
    }

    @Test func readsTheBranchLinesWithUpstreamAndCounts() {
        let status = parse([
            "# branch.oid 4f2a9c1e0b7d6a5f3c2b1a0e9d8c7b6a5f4e3d2c", "# branch.head main",
            "# branch.upstream origin/main", "# branch.ab +3 -1",
        ])
        #expect(status.head == .branch("main"))
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 3)
        #expect(status.behind == 1)
        #expect(status.entries.isEmpty)
    }

    @Test func readsADetachedHeadAsItsShortSha() {
        let status = parse(["# branch.oid 4f2a9c1e0b7d6a5f3c2b1a0e9d8c7b6a5f4e3d2c", "# branch.head (detached)"])
        #expect(status.head == .detached("4f2a9c1"))
        #expect(status.upstream == nil)
        #expect(status.ahead == 0)
    }

    @Test func readsAnUnbornHead() {
        let status = parse(["# branch.oid (initial)", "# branch.head main", "? new.txt"])
        #expect(status.head == .unborn("main"))
        #expect(status.entries == [GitStatusEntry(path: "new.txt", index: .untracked, worktree: .untracked)])
    }

    @Test func readsOrdinaryRenamedUnmergedUntrackedAndIgnoredEntries() {
        let status = parse([
            "# branch.oid 4f2a9c1e0b7d6a5f3c2b1a0e9d8c7b6a5f4e3d2c", "# branch.head main",
            "1 .M N... 100644 100644 100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 src/app.swift",
            "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 docs/new.md",
            "2 R. N... 100644 100644 100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 R100 new/name.txt",
            "old/name.txt",
            "u UU N... 100644 100644 100644 100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 conflict.txt",
            "? untracked.txt", "! build/out.o",
        ])
        #expect(
            status.entries == [
                GitStatusEntry(path: "src/app.swift", index: .unmodified, worktree: .modified),
                GitStatusEntry(path: "docs/new.md", index: .added, worktree: .unmodified),
                GitStatusEntry(
                    path: "new/name.txt", originalPath: "old/name.txt", index: .renamed, worktree: .unmodified),
                GitStatusEntry(path: "conflict.txt", index: .unmerged, worktree: .unmerged, isConflict: true),
                GitStatusEntry(path: "untracked.txt", index: .untracked, worktree: .untracked),
                GitStatusEntry(path: "build/out.o", index: .ignored, worktree: .ignored),
            ])
        #expect(
            status.fileStatuses == [
                "src/app.swift": .modified, "docs/new.md": .added, "new/name.txt": .renamed,
                "conflict.txt": .conflicted,
                "untracked.txt": .untracked, "build/out.o": .ignored,
            ])
    }

    @Test func keepsANewlineInAPathAndSurvivesBytesThatAreNotUTF8() {
        var data = Data("# branch.oid (initial)\0# branch.head main\0? a\nb.txt\0? caf".utf8)
        data.append(contentsOf: [0xE9, 0x2E, 0x74, 0x78, 0x74, 0])
        let status = StatusParser.parse(data)
        #expect(status.entries.map(\.path) == ["a\nb.txt", "caf\u{FFFD}.txt"])
    }

    @Test func emptyOutputIsAnEmptyUnbornStatus() {
        #expect(StatusParser.parse(Data()) == .empty)
        #expect(parse(["garbage line"]).entries.isEmpty)
    }

    @Test func fileStatusFollowsTheWorktreeSideThenTheIndex() {
        #expect(GitStatusEntry(path: "a", index: .modified, worktree: .modified).fileStatus == .modified)
        #expect(GitStatusEntry(path: "a", index: .added, worktree: .modified).fileStatus == .added)
        #expect(GitStatusEntry(path: "a", index: .unmodified, worktree: .deleted).fileStatus == .deleted)
        #expect(GitStatusEntry(path: "a", index: .deleted, worktree: .unmodified).fileStatus == .deleted)
        #expect(GitStatusEntry(path: "a", index: .copied, worktree: .modified).fileStatus == .renamed)
        #expect(GitStatusEntry(path: "a", index: .unmodified, worktree: .typeChanged).fileStatus == .modified)
    }
}
