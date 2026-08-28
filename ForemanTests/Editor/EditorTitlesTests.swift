import Testing

@testable import Foreman

/// editor R5: duplicated names get their parent folder.
struct EditorTitlesTests {
    @Test func addsTheParentFolderOnlyToDuplicates() {
        let titles = EditorTitles.titles(for: ["a/index.ts", "b/index.ts", "README.md", "/etc/hosts"])
        #expect(titles == ["a/index.ts", "b/index.ts", "README.md", "hosts"])
    }

    @Test func keepsANameAtTheRootAsIs() {
        #expect(EditorTitles.titles(for: ["index.ts", "src/index.ts"]) == ["index.ts", "src/index.ts"])
    }
}
