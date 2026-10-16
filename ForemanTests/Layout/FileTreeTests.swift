import Foundation
import Testing

@testable import Foreman

/// design R23, git R6b: the paths of a file tree, folded and ordered as the explorer orders them.
struct FileTreeTests {
    private func entry(_ path: String, detail: String? = nil) -> FileTreeEntry {
        FileTreeEntry(path: path, status: .modified, mark: "M", detail: detail)
    }

    /// Each row indented by its depth, a folder ending with `/`.
    private func labels(_ nodes: [FileTreeNode], depth: Int = 0) -> [String] {
        nodes.flatMap { node in
            [String(repeating: "  ", count: depth) + node.label + (node.isFolder ? "/" : "")]
                + labels(node.children, depth: depth + 1)
        }
    }

    @Test func nestsFilesUnderTheirFolders() {
        let tree = FileTreeNode.build([entry("src/a.swift"), entry("src/deep/b.swift"), entry("c.swift")])
        #expect(labels(tree) == ["src/", "  deep/", "    b.swift", "  a.swift", "c.swift"])
    }

    @Test func foldsAChainOfSingleChildFoldersIntoOneRow() {
        let tree = FileTreeNode.build([entry("src/main/java/Foo.java")])
        #expect(labels(tree) == ["src/main/java/", "  Foo.java"])
        #expect(tree.first?.path == "src/main/java")
        #expect(tree.first?.children.first?.entry?.path == "src/main/java/Foo.java")
    }

    @Test func stopsFoldingAtASecondChild() {
        let tree = FileTreeNode.build([entry("src/main/java/Foo.java"), entry("src/main/kotlin/Bar.kt")])
        #expect(labels(tree) == ["src/main/", "  java/", "    Foo.java", "  kotlin/", "    Bar.kt"])
        #expect(tree.first?.children.map(\.path) == ["src/main/java", "src/main/kotlin"])
    }

    @Test func stopsFoldingWhenTheFolderAlsoHoldsAFile() {
        let tree = FileTreeNode.build([entry("src/main/java/Foo.java"), entry("src/README.md")])
        #expect(labels(tree) == ["src/", "  main/java/", "    Foo.java", "  README.md"])
    }

    @Test func ordersFoldersFirstThenNamesTheWayTheFinderDoes() {
        let tree = FileTreeNode.build([
            entry("b.swift"), entry("File10.swift"), entry("File2.swift"), entry("zz/x.swift"), entry("aa/y.swift"),
        ])
        #expect(labels(tree) == ["aa/", "  y.swift", "zz/", "  x.swift", "b.swift", "File2.swift", "File10.swift"])
    }

    @Test func aRenameIsOneEntryAtItsNewPathCarryingItsDetail() {
        let tree = FileTreeNode.build([entry("src/new/Name.swift", detail: "← old/Other.swift")])
        #expect(labels(tree) == ["src/new/", "  Name.swift"])
        #expect(tree.first?.children.first?.entry?.detail == "← old/Other.swift")
    }

    @Test func noEntryIsNoRow() {
        #expect(FileTreeNode.build([]).isEmpty)
    }
}
