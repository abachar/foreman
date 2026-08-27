import Testing

@testable import Wraith

/// The shared exclusion list (architecture): names anywhere, exact paths, `~/Library`.
struct ExcludedPathsTests {
    @Test func excludesKnownFoldersAtAnyDepth() {
        #expect(ExcludedPaths.isExcluded("node_modules"))
        #expect(ExcludedPaths.isExcluded("web/node_modules/react/index.js"))
        #expect(ExcludedPaths.isExcluded("target"))
        #expect(ExcludedPaths.isExcluded("lib/.build/debug"))
        #expect(ExcludedPaths.isExcluded("a/.DS_Store"))
        #expect(ExcludedPaths.isExcluded("DerivedData/Build/Products"))
        #expect(!ExcludedPaths.isExcluded("DerivedDataTests.swift"))
    }

    @Test func excludesExactPathsAndTheirContent() {
        #expect(ExcludedPaths.isExcluded(".git/objects"))
        #expect(ExcludedPaths.isExcluded(".git/objects/ab/cdef"))
        #expect(ExcludedPaths.isExcluded(".wraith/state.json"))
        #expect(!ExcludedPaths.isExcluded(".git/HEAD"))
        #expect(!ExcludedPaths.isExcluded(".wraith/config.json"))
        #expect(!ExcludedPaths.isExcluded("src/.git/objects.md"))
    }

    @Test func excludesLibraryOnlyUnderHome() {
        #expect(ExcludedPaths.isExcluded("Library", rootIsHome: true))
        #expect(ExcludedPaths.isExcluded("Library/Caches", rootIsHome: true))
        #expect(!ExcludedPaths.isExcluded("Library"))
        #expect(!ExcludedPaths.isExcluded("app/Library", rootIsHome: true))
        #expect(!ExcludedPaths.isExcluded("targets/x"))
        #expect(!ExcludedPaths.isExcluded(""))
    }
}
