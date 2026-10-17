import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterCSS
import TreeSitterDockerfile
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterKotlin
import TreeSitterMarkdown
import TreeSitterSql
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// The grammars Foreman ships (editor R11), one SPM package each, and the file names they cover.
///
/// `sql` came last (2026-08-28): tree-sitter-sql's `gh-pages` branch, the one carrying the
/// generated parser, resolves and builds next to SwiftTreeSitter under Xcode 27.
nonisolated enum Language: String, CaseIterable, Sendable {
    case java
    case kotlin
    case typescript
    case tsx
    case javascript
    case json
    case yaml
    case toml
    case markdown
    case bash
    case swift
    case html
    case css
    case dockerfile
    case sql

    /// layout (status bar, 2026-10-16): the language as the status bar names it.
    var displayName: String {
        switch self {
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .typescript: return "TypeScript"
        case .tsx: return "TypeScript JSX"
        case .javascript: return "JavaScript"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .markdown: return "Markdown"
        case .bash: return "Shell"
        case .swift: return "Swift"
        case .html: return "HTML"
        case .css: return "CSS"
        case .dockerfile: return "Dockerfile"
        case .sql: return "SQL"
        }
    }

    /// editor R11: by file name first (`Dockerfile.dev`, `.zshrc`), then by extension; `nil` is
    /// plain text.
    static func forFile(_ url: URL) -> Language? {
        let name = url.lastPathComponent
        if name.hasPrefix("Dockerfile") || name.hasSuffix(".dockerfile") {
            return .dockerfile
        }
        switch name {
        case ".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile", ".profile":
            return .bash
        default:
            break
        }
        switch url.pathExtension.lowercased() {
        case "java":
            return .java
        case "kt", "kts":
            return .kotlin
        case "ts", "mts", "cts":
            return .typescript
        case "tsx":
            return .tsx
        case "js", "mjs", "cjs", "jsx":
            return .javascript
        case "json", "jsonc":
            return .json
        case "yaml", "yml":
            return .yaml
        case "toml":
            return .toml
        case "md", "markdown":
            return .markdown
        case "sh", "bash", "zsh":
            return .bash
        case "swift":
            return .swift
        case "html", "htm":
            return .html
        case "css":
            return .css
        case "sql", "psql":
            return .sql
        default:
            return nil
        }
    }

    /// editor R6: what `cmd+/` inserts; `nil` when the language has no line comment.
    var lineCommentPrefix: String? {
        switch self {
        case .java, .kotlin, .typescript, .tsx, .javascript, .swift:
            return "//"
        case .yaml, .toml, .bash, .dockerfile:
            return "#"
        case .sql:
            return "--"
        case .json, .markdown, .html, .css:
            return nil
        }
    }

    /// The bare parser, for a parse without queries (editor R26 folding).
    var treeSitterLanguage: SwiftTreeSitter.Language {
        switch self {
        case .java: return SwiftTreeSitter.Language(tree_sitter_java())
        case .kotlin: return SwiftTreeSitter.Language(tree_sitter_kotlin())
        case .typescript: return SwiftTreeSitter.Language(tree_sitter_typescript())
        case .tsx: return SwiftTreeSitter.Language(tree_sitter_tsx())
        case .javascript: return SwiftTreeSitter.Language(tree_sitter_javascript())
        case .json: return SwiftTreeSitter.Language(tree_sitter_json())
        case .yaml: return SwiftTreeSitter.Language(tree_sitter_yaml())
        case .toml: return SwiftTreeSitter.Language(tree_sitter_toml())
        case .markdown: return SwiftTreeSitter.Language(tree_sitter_markdown())
        case .bash: return SwiftTreeSitter.Language(tree_sitter_bash())
        case .swift: return SwiftTreeSitter.Language(tree_sitter_swift())
        case .html: return SwiftTreeSitter.Language(tree_sitter_html())
        case .css: return SwiftTreeSitter.Language(tree_sitter_css())
        case .dockerfile: return SwiftTreeSitter.Language(tree_sitter_dockerfile())
        case .sql: return SwiftTreeSitter.Language(tree_sitter_sql())
        }
    }

    /// The parser and its `highlights.scm`, loaded from the package's resource bundle.
    ///
    /// Throws when the bundle or its queries are missing (editor R13: the caller falls back to
    /// plain text).
    func makeConfiguration() throws -> LanguageConfiguration {
        switch self {
        case .java:
            return try Self.ownConfiguration(tree_sitter_java(), name: "Java", highlights: "java.highlights")
        case .kotlin:
            return try LanguageConfiguration(tree_sitter_kotlin(), name: "Kotlin")
        case .typescript:
            return try Self.typeScriptConfiguration(
                tree_sitter_typescript(), name: "TypeScript", bundleName: "TreeSitterTypeScript_TreeSitterTypeScript")
        case .tsx:
            return try Self.typeScriptConfiguration(
                tree_sitter_tsx(), name: "TSX", bundleName: "TreeSitterTypeScript_TreeSitterTSX")
        case .javascript:
            return try LanguageConfiguration(tree_sitter_javascript(), name: "JavaScript")
        case .json:
            return try LanguageConfiguration(tree_sitter_json(), name: "JSON")
        case .yaml:
            return try LanguageConfiguration(tree_sitter_yaml(), name: "YAML")
        case .toml:
            return try LanguageConfiguration(tree_sitter_toml(), name: "TOML")
        case .markdown:
            return try LanguageConfiguration(
                tree_sitter_markdown(), name: "Markdown", bundleName: "TreeSitterMarkdown_TreeSitterMarkdown")
        case .bash:
            return try LanguageConfiguration(tree_sitter_bash(), name: "Bash")
        case .swift:
            return try LanguageConfiguration(tree_sitter_swift(), name: "Swift")
        case .html:
            return try LanguageConfiguration(tree_sitter_html(), name: "HTML")
        case .css:
            return try LanguageConfiguration(tree_sitter_css(), name: "CSS")
        case .dockerfile:
            return try LanguageConfiguration(tree_sitter_dockerfile(), name: "Dockerfile")
        case .sql:
            return try LanguageConfiguration(tree_sitter_sql(), name: "Sql")
        }
    }

    /// TypeScript and TSX highlighted with JavaScript's captures plus their own.
    ///
    /// tree-sitter-typescript ships `highlights.scm` files that only add the TypeScript-specific
    /// captures on top of tree-sitter-javascript's (its README: the queries "inherit" JavaScript's);
    /// SwiftTreeSitter loads one directory, so a `.ts`/`.tsx` file only got its types colored
    /// (bug 2026-08-28). The two files are concatenated, JavaScript first.
    private static func typeScriptConfiguration(
        _ tsLanguage: OpaquePointer, name: String, bundleName: String
    ) throws -> LanguageConfiguration {
        let language = SwiftTreeSitter.Language(tsLanguage)
        let directories = [
            try queriesDirectory("TreeSitterJavaScript_TreeSitterJavaScript"), try queriesDirectory(bundleName),
        ]
        let highlights =
            try directories
            .map { try Data(contentsOf: $0.appending(path: "highlights.scm")) }
            .reduce(into: Data()) { $0.append($1) }
        return LanguageConfiguration(
            language, name: name, queries: [.highlights: try Query(language: language, data: highlights)])
    }

    /// A grammar with **Foreman's own** `highlights.scm` instead of the package's (editor R12,
    /// amended 2026-10-17): the file `Highlight/Queries/<highlights>.scm`, shipped in the app's
    /// resources, written against what the author's eye expects (IntelliJ's Java page, M25 25.1).
    ///
    /// Only the highlights change; the grammar, its folding and everything else stay the package's.
    private static func ownConfiguration(
        _ tsLanguage: OpaquePointer, name: String, highlights: String
    ) throws -> LanguageConfiguration {
        let language = SwiftTreeSitter.Language(tsLanguage)
        let data = try Data(contentsOf: try ownQuery(highlights))
        return LanguageConfiguration(
            language, name: name, queries: [.highlights: try Query(language: language, data: data)])
    }

    /// `Highlight/Queries/<name>.scm`, looked up like the packages' bundles: the test host is not
    /// the app bundle.
    private static func ownQuery(_ name: String) throws -> URL {
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: name, withExtension: "scm") {
                return url
            }
        }
        throw HighlightError.bundleNotFound("\(name).scm")
    }

    private static func queriesDirectory(_ bundleName: String) throws -> URL {
        // Same lookup as SwiftTreeSitter's: the test host is not the app bundle.
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: bundleName, withExtension: "bundle") {
                return url.appending(path: "Contents/Resources/queries", directoryHint: .isDirectory)
            }
        }
        throw HighlightError.bundleNotFound(bundleName)
    }
}
