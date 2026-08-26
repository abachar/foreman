import Foundation
import Testing

@testable import Wraith

/// editor R11: file name and extension to grammar.
struct LanguageTests {
    @Test(arguments: [
        ("Main.java", Language.java), ("App.kt", .kotlin), ("build.gradle.kts", .kotlin),
        ("index.ts", .typescript), ("App.tsx", .tsx), ("lib.mjs", .javascript), ("x.jsx", .javascript),
        ("package.json", .json), ("ci.yml", .yaml), ("stack.yaml", .yaml), ("Cargo.toml", .toml),
        ("README.md", .markdown), ("deploy.sh", .bash), (".zshrc", .bash), (".bash_profile", .bash),
        ("Editor.swift", .swift), ("index.html", .html), ("site.css", .css),
        ("Dockerfile", .dockerfile), ("Dockerfile.dev", .dockerfile), ("api.dockerfile", .dockerfile),
        ("FILE.JSON", .json),
    ])
    func mapsKnownFiles(name: String, language: Language) {
        #expect(Language.forFile(URL(filePath: "/ws/src/\(name)")) == language)
    }

    @Test(arguments: ["notes.txt", "Makefile", "query.sql", "image.png", "noext", ".env"])
    func unknownFilesArePlainText(name: String) {
        #expect(Language.forFile(URL(filePath: "/ws/\(name)")) == nil)
    }

    @Test func everyLanguageLoadsItsQueries() throws {
        for language in Language.allCases {
            #expect(throws: Never.self, "\(language)") { try language.makeConfiguration() }
        }
    }
}
