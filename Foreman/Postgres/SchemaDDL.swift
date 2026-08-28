import Foundation

/// *View the DDL* (postgres R8): reconstructed on the client, best effort, from the rows the
/// tree already loaded (decision 2026-08-27: tables, views, functions and indexes only).
///
/// The server has no `pg_get_tabledef`; this is what a `pg_dump` header would look like, from
/// `format_type`, `pg_get_expr`, `pg_get_constraintdef` and `pg_get_indexdef`.
nonisolated enum SchemaDDL {
    /// R8: the banner over every reconstructed definition.
    static let disclaimer = "Reconstructed by Foreman from pg_catalog, not the server's definition."

    /// One constraint or index as the tree loaded it.
    struct Definition: Hashable, Sendable {
        let name: String
        let text: String
    }

    static func table(
        schema: String, name: String, columns: [SchemaNode.Column], constraints: [Definition], indexes: [Definition]
    ) -> String {
        var lines = columns.map { column in
            var line = "    \(SQLIdentifier.quote(column.name)) \(column.type)"
            if column.isNotNull {
                line += " NOT NULL"
            }
            if let defaultValue = column.defaultValue {
                line += " DEFAULT \(defaultValue)"
            }
            return line
        }
        lines += constraints.map { "    CONSTRAINT \(SQLIdentifier.quote($0.name)) \($0.text)" }
        var ddl = "CREATE TABLE \(SQLIdentifier.qualified(schema, name)) (\n\(lines.joined(separator: ",\n"))\n);"
        // An index backing a constraint carries the constraint's name: already in the table.
        let constraintNames = Set(constraints.map(\.name))
        for index in indexes where !constraintNames.contains(index.name) {
            ddl += "\n\(index.text);"
        }
        return ddl
    }

    static func view(schema: String, name: String, isMaterialized: Bool, definition: String) -> String {
        let keyword = isMaterialized ? "CREATE MATERIALIZED VIEW" : "CREATE OR REPLACE VIEW"
        let body = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(keyword) \(SQLIdentifier.qualified(schema, name)) AS\n\(body.hasSuffix(";") ? body : body + ";")"
    }
}
