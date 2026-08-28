import Foundation
import Testing

@testable import Foreman

/// Badges, greying and the quick open index following git (explorer R4, R15; editor R18).
struct GitExplorerTests {
    @Test func propagatesTheStrongestStatusOntoTheAncestors() {
        let folders = ExplorerModel.propagate([
            "src/app/a.swift": .modified, "src/app/b.swift": .added, "src/lib/c.swift": .conflicted,
            "docs/new.md": .untracked, "build/out.o": .ignored,
        ])
        #expect(folders["src"] == .conflicted)
        #expect(folders["src/app"] == .modified)
        #expect(folders["src/lib"] == .conflicted)
        #expect(folders["docs"] == .untracked)
        #expect(folders["build"] == nil)
        #expect(ExplorerModel.propagate([:]).isEmpty)
    }

    @Test func anEntryUnderAnIgnoredFolderIsGreyed() {
        let ignored: Set<String> = ["DerivedData", "src/generated/x.swift"]
        #expect(ExplorerModel.isIgnored("DerivedData", in: ignored))
        #expect(ExplorerModel.isIgnored("DerivedData/Build/a", in: ignored))
        #expect(ExplorerModel.isIgnored("src/generated/x.swift", in: ignored))
        #expect(!ExplorerModel.isIgnored("src/generated/y.swift", in: ignored))
        #expect(!ExplorerModel.isIgnored("DerivedDataX", in: ignored))
        #expect(!ExplorerModel.isIgnored("a", in: []))
    }

    @MainActor
    @Test func aRepoStatusReplacesItsOwnEntriesAndKeepsTheOthers() {
        let root = URL(filePath: "/work")
        let model = ExplorerModel(root: root)
        let rootRepo = GitRepo(id: ".", url: root)
        let sub = GitRepo(id: "libs/core", url: root.appending(path: "libs/core"))
        model.applyGitStatus(GitStatusChange(repo: rootRepo, statuses: ["README.md": .modified, "build/": .ignored]))
        model.applyGitStatus(GitStatusChange(repo: sub, statuses: ["src/a.swift": .added]))
        #expect(model.gitStatuses == ["README.md": .modified, "libs/core/src/a.swift": .added])
        #expect(model.folderStatuses["libs/core/src"] == .added)
        #expect(model.folderStatuses["libs"] == .added)
        #expect(model.isGitIgnored("build/out.o"))
        #expect(
            model.gitStatus(
                of: FileNode(relativePath: "README.md", kind: .file, isExcluded: false, isUnreadable: false))
                == .modified)
        #expect(
            model.gitStatus(
                of: FileNode(relativePath: "libs", kind: .directory, isExcluded: false, isUnreadable: false)) == .added)

        model.applyGitStatus(GitStatusChange(repo: sub, statuses: [:]))
        #expect(model.gitStatuses == ["README.md": .modified])
        #expect(model.folderStatuses["libs"] == nil)
        model.applyGitStatus(GitStatusChange(repo: rootRepo, statuses: [:]))
        #expect(model.gitStatuses.isEmpty)
        #expect(!model.isGitIgnored("build/out.o"))
    }

    @Test func theQuickOpenIndexLeavesIgnoredPathsOutUntilTheyAreUnignored() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitExplorerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "gen"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "keep.swift"))
        try Data().write(to: root.appending(path: "gen/out.swift"))
        let index = QuickOpenIndex(root: root)
        await index.build()
        #expect(Set(await index.search("swift", limit: 10).paths) == ["keep.swift", "gen/out.swift"])
        await index.setIgnored(["gen"])
        #expect(await index.search("swift", limit: 10).paths == ["keep.swift"])
        await index.setIgnored([])
        #expect(Set(await index.search("swift", limit: 10).paths) == ["keep.swift", "gen/out.swift"])
    }
}
