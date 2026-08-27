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
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// The grammars Wraith ships (editor R11), one SPM package each, and the file names they cover.
///
/// `sql` (editor R11) is not here: its package manifest does not resolve under Xcode 27 (M1, then
/// again in M5 task 5.4), see `editor/decisions.md` 2026-08-27 and `editor/questions.md`.
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
        case .json, .markdown, .html, .css:
            return nil
        }
    }

    /// The parser and its `highlights.scm`, loaded from the package's resource bundle.
    ///
    /// Throws when the bundle or its queries are missing (editor R13: the caller falls back to
    /// plain text).
    func makeConfiguration() throws -> LanguageConfiguration {
        switch self {
        case .java:
            return try LanguageConfiguration(tree_sitter_java(), name: "Java")
        case .kotlin:
            return try LanguageConfiguration(tree_sitter_kotlin(), name: "Kotlin")
        case .typescript:
            return try LanguageConfiguration(
                tree_sitter_typescript(), name: "TypeScript", bundleName: "TreeSitterTypeScript_TreeSitterTypeScript")
        case .tsx:
            return try LanguageConfiguration(
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
        }
    }
}
