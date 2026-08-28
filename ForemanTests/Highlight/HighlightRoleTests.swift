import Testing

@testable import Foreman

/// editor R12: capture names of `highlights.scm` to roles.
struct HighlightRoleTests {
    @Test(arguments: [
        ("keyword", HighlightRole.keyword), ("keyword.return", .keyword), ("function.method", .function),
        ("comment.documentation", .comment), ("string.escape", .string), ("variable.parameter", .variable),
        ("punctuation.bracket", .punctuation), ("constant.builtin", .constant), ("number.float", .number),
        ("constructor", .type), ("boolean", .constant), ("text.title", .markup), ("markup.heading", .markup),
        ("tag", .tag), ("attribute", .attribute), ("property", .property), ("label", .label), ("operator", .operator),
    ])
    func mapsCapturesToRoles(capture: String, role: HighlightRole) {
        #expect(HighlightRole(capture: capture) == role)
    }

    @Test(arguments: ["spell", "nospell", "none", "conceal", ""])
    func uncoloredCapturesHaveNoRole(capture: String) {
        #expect(HighlightRole(capture: capture) == nil)
    }
}
