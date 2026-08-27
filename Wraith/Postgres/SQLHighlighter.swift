import Foundation

/// A stop-gap SQL colorer for the query editor (postgres R9).
///
/// While `tree-sitter-sql` does not resolve (editor decision 2026-08-27, plan B): keywords,
/// types, strings, comments, numbers and `$n` parameters, ~80 lines of scanning, no dependency;
/// the roles are the editor's (`HighlightRole`), so the colors are `ThemeService`'s.
nonisolated enum SQLHighlighter {
    struct Token: Equatable, Sendable {
        let range: NSRange
        let role: HighlightRole
    }

    static let keywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "join", "inner", "left",
        "right", "full", "outer", "cross", "on", "using", "group", "by", "order", "having", "limit", "offset", "as",
        "and", "or", "not", "null", "is", "in", "like", "ilike", "between", "exists", "case", "when", "then", "else",
        "end", "create", "alter", "drop", "table", "index", "view", "materialized", "function", "returns", "returning",
        "begin", "commit", "rollback", "with", "recursive", "union", "all", "distinct", "asc", "desc", "primary",
        "key", "foreign", "references", "default", "true", "false", "unique", "constraint", "check", "cascade",
        "explain", "analyze", "vacuum", "grant", "revoke", "schema", "sequence", "type", "enum", "if", "replace",
        "temp", "temporary", "trigger", "procedure", "language", "declare", "return", "loop", "for", "over",
        "partition", "window", "fetch", "first", "next", "only", "rows", "row", "lateral", "natural", "any", "some",
        "except", "intersect", "cast", "coalesce", "nullif", "extract", "interval", "current_timestamp",
        "current_date", "now", "count", "sum", "avg", "min", "max", "array", "array_agg", "string_agg",
        "conflict", "do", "nothing", "add", "column", "rename", "to", "owner", "truncate", "restart", "identity",
    ]

    static let types: Set<String> = [
        "int", "integer", "int2", "int4", "int8", "smallint", "bigint", "serial", "bigserial", "numeric", "decimal",
        "real", "float", "float4", "float8", "double", "precision", "boolean", "bool", "text", "varchar", "char",
        "character", "varying", "uuid", "date", "time", "timestamp", "timestamptz", "timetz", "json", "jsonb",
        "bytea", "inet", "cidr", "macaddr", "money", "oid", "name", "regclass", "void", "record", "setof",
    ]

    static func tokens(in text: String) -> [Token] {
        let scalars = Array(text.utf16)
        var tokens: [Token] = []
        var index = 0
        func scalar(_ at: Int) -> UInt16? {
            at < scalars.count ? scalars[at] : nil
        }
        func isWord(_ value: UInt16) -> Bool {
            (0x30...0x39).contains(value) || (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
                || value == 0x5F
        }
        while index < scalars.count {
            let current = scalars[index]
            if current == 0x2D, scalar(index + 1) == 0x2D {
                let start = index
                while index < scalars.count, scalars[index] != 0x0A {
                    index += 1
                }
                tokens.append(Token(range: NSRange(location: start, length: index - start), role: .comment))
            } else if current == 0x2F, scalar(index + 1) == 0x2A {
                let start = index
                index += 2
                while index < scalars.count, !(scalars[index] == 0x2A && scalar(index + 1) == 0x2F) {
                    index += 1
                }
                index = min(index + 2, scalars.count)
                tokens.append(Token(range: NSRange(location: start, length: index - start), role: .comment))
            } else if current == 0x27 {
                let start = index
                index += 1
                while index < scalars.count {
                    if scalars[index] == 0x27 {
                        if scalar(index + 1) == 0x27 {
                            index += 2
                            continue
                        }
                        index += 1
                        break
                    }
                    index += 1
                }
                tokens.append(Token(range: NSRange(location: start, length: index - start), role: .string))
            } else if current == 0x24, let next = scalar(index + 1), (0x30...0x39).contains(next) {
                let start = index
                index += 1
                while let digit = scalar(index), (0x30...0x39).contains(digit) {
                    index += 1
                }
                tokens.append(Token(range: NSRange(location: start, length: index - start), role: .variable))
            } else if (0x30...0x39).contains(current), index == 0 || !isWord(scalars[index - 1]) {
                let start = index
                while let value = scalar(index), (0x30...0x39).contains(value) || value == 0x2E {
                    index += 1
                }
                tokens.append(Token(range: NSRange(location: start, length: index - start), role: .number))
            } else if isWord(current), index == 0 || !isWord(scalars[index - 1]) {
                let start = index
                while let value = scalar(index), isWord(value) {
                    index += 1
                }
                let word = String(utf16CodeUnits: Array(scalars[start..<index]), count: index - start).lowercased()
                if keywords.contains(word) {
                    tokens.append(Token(range: NSRange(location: start, length: index - start), role: .keyword))
                } else if types.contains(word) {
                    tokens.append(Token(range: NSRange(location: start, length: index - start), role: .type))
                }
            } else {
                index += 1
            }
        }
        return tokens
    }
}
