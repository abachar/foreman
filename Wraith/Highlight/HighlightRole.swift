import Foundation

/// The roles a `highlights.scm` capture maps to (editor R12); `ThemeService` gives each a color.
///
/// Capture names are dotted (`keyword.return`, `function.method`, `comment.documentation`): the
/// first component decides, a few grammar-specific names are folded into the nearest role.
nonisolated enum HighlightRole: String, CaseIterable, Sendable {
    case keyword
    case string
    case comment
    case type
    case function
    case number
    case variable
    case punctuation
    case `operator`
    case constant
    case property
    case attribute
    case tag
    case label
    case markup

    /// `nil` for captures that carry no color (`spell`, `none`, `conceal`…).
    init?(capture: String) {
        let head = capture.split(separator: ".", maxSplits: 1).first.map(String.init) ?? capture
        if let role = HighlightRole(rawValue: head) {
            self = role
            return
        }
        switch head {
        case "constructor", "module", "namespace", "class", "interface", "enum", "struct":
            self = .type
        case "method", "macro":
            self = .function
        case "boolean", "float", "character", "escape":
            self = .constant
        case "parameter", "field", "local", "definition":
            self = .variable
        case "text", "title", "heading", "emphasis", "strong", "link", "uri", "list", "quote", "code":
            self = .markup
        case "include", "repeat", "conditional", "exception", "storageclass", "storage", "exception_handling":
            self = .keyword
        case "delimiter", "bracket", "special":
            self = .punctuation
        default:
            return nil
        }
    }
}
