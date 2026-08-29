import Foundation
import Testing

@testable import Foreman

/// git R6b: one group's paths as a tree, folded, ordered, everything expanded.
struct PathTreeTests {
    private func entry(_ path: String, originalPath: String? = nil) -> GitStatusEntry {
        GitStatusEntry(path: path, originalPath: originalPath, index: .unmodified, worktree: .modified)
    }

    private func labels(_ rows: [PathTree.Row]) -> [String] {
        rows.map { row in
            switch row {
            case .folder(_, let label, let depth): return String(repeating: "  ", count: depth) + label + "/"
            case .file(let entry, let depth):
                return String(repeating: "  ", count: depth)
                    + (entry.path.split(separator: "/").last.map(String.init) ?? entry.path)
            }
        }
    }

    @Test func nestsFilesUnderTheirFolders() {
        let rows = PathTree.rows(of: [entry("src/a.swift"), entry("src/deep/b.swift"), entry("c.swift")])

        #expect(labels(rows) == ["src/", "  deep/", "    b.swift", "  a.swift", "c.swift"])
    }

    @Test func foldsAChainOfSingleChildFoldersIntoOneRow() {
        let rows = PathTree.rows(of: [entry("src/main/java/Foo.java")])

        #expect(labels(rows) == ["src/main/java/", "  Foo.java"])
        #expect(rows.first == .folder(path: "src/main/java", label: "src/main/java", depth: 0))
    }

    @Test func stopsFoldingAtASecondChild() {
        let rows = PathTree.rows(of: [entry("src/main/java/Foo.java"), entry("src/main/kotlin/Bar.kt")])

        #expect(labels(rows) == ["src/main/", "  java/", "    Foo.java", "  kotlin/", "    Bar.kt"])
    }

    @Test func stopsFoldingWhenTheFolderAlsoHoldsAFile() {
        let rows = PathTree.rows(of: [entry("src/main/java/Foo.java"), entry("src/README.md")])

        #expect(labels(rows) == ["src/", "  main/java/", "    Foo.java", "  README.md"])
    }

    @Test func ordersFoldersFirstThenNamesTheWayTheFinderDoes() {
        let rows = PathTree.rows(of: [
            entry("b.swift"), entry("File10.swift"), entry("File2.swift"), entry("zz/x.swift"), entry("aa/y.swift"),
        ])

        #expect(labels(rows) == ["aa/", "  y.swift", "zz/", "  x.swift", "b.swift", "File2.swift", "File10.swift"])
    }

    @Test func aSingleFileAtTheRootIsASingleRow() {
        let rows = PathTree.rows(of: [entry("README.md")])

        #expect(rows == [.file(entry("README.md"), depth: 0)])
    }

    @Test func aRenameIsOneEntryAtItsNewPath() {
        let rows = PathTree.rows(of: [entry("src/new/Name.swift", originalPath: "old/Other.swift")])

        #expect(labels(rows) == ["src/new/", "  Name.swift"])
        #expect(rows.count == 2)
    }

    @Test func noEntryIsNoRow() {
        #expect(PathTree.rows(of: []).isEmpty)
    }

    @Test func aCollapsedFolderKeepsItsRowAndHidesWhatIsUnderIt() {
        let entries = [entry("src/a.swift"), entry("src/deep/b.swift"), entry("c.swift")]

        let rows = PathTree.rows(of: entries, collapsed: ["src"])

        #expect(labels(rows) == ["src/", "c.swift"])
    }

    @Test func aCollapsedFolderInsideAnOpenOneOnlyHidesItsOwnSubtree() {
        let entries = [entry("src/a.swift"), entry("src/deep/b.swift")]

        let rows = PathTree.rows(of: entries, collapsed: ["src/deep"])

        #expect(labels(rows) == ["src/", "  deep/", "  a.swift"])
    }

    @Test func aFoldedChainIsCollapsedByItsWholePath() {
        let entries = [entry("src/main/java/Foo.java")]

        #expect(labels(PathTree.rows(of: entries, collapsed: ["src/main/java"])) == ["src/main/java/"])
        #expect(labels(PathTree.rows(of: entries, collapsed: ["src"])).count == 2)
    }
}
