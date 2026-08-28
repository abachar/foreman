import Foundation

/// `quote_ident` on the client side (postgres R15): every identifier Foreman puts into SQL text
/// goes through here; values never do, they are bound.
///
/// Nothing in PostgresNIO quotes identifiers (it binds values only), so this is ~40 lines
/// following the server's rule: quoted unless it is lowercase `[a-z_][a-z0-9_$]*` and not a
/// keyword; a `"` inside is doubled.
nonisolated enum SQLIdentifier {
    static func quote(_ name: String) -> String {
        guard needsQuotes(name) else { return name }
        return "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func qualified(_ schema: String, _ name: String) -> String {
        quote(schema) + "." + quote(name)
    }

    static func needsQuotes(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || ("a"..."z").contains(first) else { return true }
        for scalar in name.unicodeScalars.dropFirst()
        where !(scalar == "_" || scalar == "$" || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)) {
            return true
        }
        return keywords.contains(name)
    }

    /// The server's reserved keywords (`pg_get_keywords()` categories other than unreserved),
    /// which `quote_ident` quotes; PostgreSQL 17.
    static let keywords: Set<String> = [
        "all", "analyse", "analyze", "and", "any", "array", "as", "asc", "asymmetric", "authorization", "between",
        "bigint", "binary", "bit", "boolean", "both", "case", "cast", "char", "character", "check", "coalesce",
        "collate", "collation", "column", "concurrently", "constraint", "create", "cross", "current_catalog",
        "current_date", "current_role", "current_schema", "current_time", "current_timestamp", "current_user",
        "dec", "decimal", "default", "deferrable", "desc", "distinct", "do", "else", "end", "except", "exists",
        "extract", "false", "fetch", "float", "for", "foreign", "freeze", "from", "full", "grant", "greatest",
        "group", "grouping", "having", "ilike", "in", "initially", "inner", "inout", "int", "integer", "intersect",
        "interval", "into", "is", "isnull", "join", "json", "json_array", "json_arrayagg", "json_exists",
        "json_object", "json_objectagg", "json_query", "json_scalar", "json_serialize", "json_table",
        "json_value", "lateral", "leading", "least", "left", "like", "limit", "localtime", "localtimestamp",
        "merge_action", "national", "natural", "nchar", "none", "normalize", "not", "notnull", "null", "nullif",
        "numeric", "offset", "on", "only", "or", "order", "out", "outer", "overlaps", "overlay", "placing",
        "position", "precision", "primary", "real", "references", "returning", "right", "row", "select",
        "session_user", "setof", "similar", "smallint", "some", "substring", "symmetric", "system_user", "table",
        "tablesample", "then", "time", "timestamp", "to", "trailing", "treat", "trim", "true", "union", "unique",
        "user", "using", "values", "varchar", "variadic", "verbose", "when", "where", "window", "with", "xmlattributes",
        "xmlconcat", "xmlelement", "xmlexists", "xmlforest", "xmlnamespaces", "xmlparse", "xmlpi", "xmlroot",
        "xmlserialize", "xmltable",
    ]
}
