import AppKit
import Foundation
import Testing

@testable import Foreman

/// design R23: the file name → icon mapping, and the catalog holding every icon it names.
struct FileIconTests {
    @Test(arguments: [
        ("UserController.java", "file-java"), ("Dockerfile", "file-docker"), ("Dockerfile.dev", "file-docker"),
        ("docker-compose.yml", "file-docker"), (".gitignore", "file-git"), ("README.md", "file-readme"),
        ("package.json", "file-npm"), ("tsconfig.build.json", "file-tsconfig"), ("App.TSX", "file-react"),
        ("main.kt", "file-kotlin"), ("x.unknown", "file-file"), ("Makefile", "file-makefile"), ("notes", "file-file"),
        ("config.yaml", "file-yaml"), ("schema.sql", "file-database"),
    ])
    func mapsNamesAndExtensionsCaseInsensitively(name: String, icon: String) {
        #expect(FileIcon.name(for: name) == icon)
    }

    @Test func foldersHaveOneIconEachWay() {
        #expect(FileIcon.folder(isExpanded: false) == "file-folder")
        #expect(FileIcon.folder(isExpanded: true) == "file-folder-open")
    }

    @Test @MainActor func everyIconOfTheMappingIsInTheCatalogAtTheRowSize() {
        for icon in FileIcon.allIcons {
            let image = FileIcon.image(named: FileIcon.assetPrefix + icon)
            #expect(image != nil, Comment(rawValue: icon))
            #expect(image?.isTemplate == false)
            #expect(image?.size == NSSize(width: FileIcon.pointSize, height: FileIcon.pointSize))
        }
        #expect(FileIcon.image(named: "sparkles") == nil)
    }
}
