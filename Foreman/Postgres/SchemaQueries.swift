import Foundation
import PostgresNIO

/// The `pg_catalog` queries behind the schema tree (postgres R6, R7, R15), one per level.
///
/// Every value is bound (`$n`), never written into the SQL text; identifiers only appear in the
/// text through `SQLIdentifier`. The server's `format_type`, `pg_get_expr`, `pg_get_indexdef`,
/// `pg_get_constraintdef`, `pg_get_viewdef` and `pg_get_functiondef` do the formatting
/// (decision 2026-08-27): nothing here re-does them.
nonisolated enum SchemaQueries {
    /// Edge cases: a level over 5,000 objects is truncated.
    static let limit = 5000

    /// R8: `SELECT * FROM schema.name LIMIT 500`, the only generated SQL the user sees.
    static func selectAll(_ node: SchemaNode) -> String? {
        guard case .relation = node.kind, let name = node.qualifiedName else { return nil }
        return "SELECT * FROM \(name) LIMIT 500"
    }

    /// The query loading the children of `parent`, `nil` for a leaf or a static level.
    ///
    /// `limit` fetches one row more than the bound so the caller knows the level is truncated;
    /// `nil` loads everything (the "load all" row).
    static func children(of parent: SchemaNode, showsSystemSchemas: Bool, limit: Int? = limit) -> PostgresQuery? {
        var binds = PostgresBindings()
        let sql: String
        switch parent.kind {
        case .database:
            binds.append(showsSystemSchemas)
            sql = """
                SELECT n.nspname FROM pg_catalog.pg_namespace n
                WHERE $1 OR (n.nspname NOT IN ('pg_catalog', 'information_schema')
                    AND n.nspname NOT LIKE 'pg\\_toast%' AND n.nspname NOT LIKE 'pg\\_temp%')
                ORDER BY n.nspname
                """
        case .category(let category, let schema):
            binds.append(schema)
            switch category {
            case .tables, .views, .materializedViews, .sequences:
                binds.append(relkinds(category))
                sql = """
                    SELECT c.relname FROM pg_catalog.pg_class c
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = $1 AND c.relkind::text = ANY($2)
                    ORDER BY c.relname
                    """
            case .functions:
                sql = """
                    SELECT p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid),
                        pg_catalog.pg_get_function_result(p.oid)
                    FROM pg_catalog.pg_proc p
                    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = $1
                    ORDER BY p.proname, 2
                    """
            case .types:
                sql = """
                    SELECT t.typname, pg_catalog.array_to_string(ARRAY(
                        SELECT e.enumlabel FROM pg_catalog.pg_enum e WHERE e.enumtypid = t.oid ORDER BY e.enumsortorder
                    ), ', ')
                    FROM pg_catalog.pg_type t
                    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = $1 AND t.typtype = 'e'
                    ORDER BY t.typname
                    """
            }
        case .section(let section, let schema, let relation, _):
            binds.append(schema)
            binds.append(relation)
            switch section {
            case .columns:
                sql = """
                    SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod), a.attnotnull,
                        pg_catalog.pg_get_expr(d.adbin, d.adrelid),
                        EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                            WHERE k.conrelid = a.attrelid AND k.contype = 'p' AND a.attnum = ANY (k.conkey))
                    FROM pg_catalog.pg_attribute a
                    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                    WHERE n.nspname = $1 AND c.relname = $2 AND a.attnum > 0 AND NOT a.attisdropped
                    ORDER BY a.attnum
                    """
            case .indexes:
                sql = """
                    SELECT i.relname, pg_catalog.pg_get_indexdef(i.oid)
                    FROM pg_catalog.pg_index x
                    JOIN pg_catalog.pg_class i ON i.oid = x.indexrelid
                    JOIN pg_catalog.pg_class c ON c.oid = x.indrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = $1 AND c.relname = $2
                    ORDER BY i.relname
                    """
            case .constraints:
                sql = """
                    SELECT k.conname, pg_catalog.pg_get_constraintdef(k.oid, true)
                    FROM pg_catalog.pg_constraint k
                    JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = $1 AND c.relname = $2
                    ORDER BY k.contype, k.conname
                    """
            case .incomingForeignKeys:
                sql = """
                    SELECT n2.nspname, c2.relname, k.conname, pg_catalog.pg_get_constraintdef(k.oid, true)
                    FROM pg_catalog.pg_constraint k
                    JOIN pg_catalog.pg_class c ON c.oid = k.confrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    JOIN pg_catalog.pg_class c2 ON c2.oid = k.conrelid
                    JOIN pg_catalog.pg_namespace n2 ON n2.oid = c2.relnamespace
                    WHERE k.contype = 'f' AND n.nspname = $1 AND c.relname = $2
                    ORDER BY n2.nspname, c2.relname, k.conname
                    """
            case .definition:
                sql = """
                    SELECT pg_catalog.pg_get_viewdef(c.oid, true)
                    FROM pg_catalog.pg_class c
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = $1 AND c.relname = $2
                    """
            }
        case .schema, .relation, .function, .sequence, .type, .column, .detail, .truncated:
            return nil
        }
        guard let limit else { return PostgresQuery(unsafeSQL: sql, binds: binds) }
        binds.append(limit + 1)
        return PostgresQuery(unsafeSQL: sql + "\nLIMIT $\(binds.count)", binds: binds)
    }

    /// R8: the server's definition of a function, for *View the DDL*.
    static func functionDefinition(schema: String, name: String, arguments: String) -> PostgresQuery {
        var binds = PostgresBindings()
        binds.append(schema)
        binds.append(name)
        binds.append(arguments)
        return PostgresQuery(
            unsafeSQL: """
                SELECT pg_catalog.pg_get_functiondef(p.oid)
                FROM pg_catalog.pg_proc p
                JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = $1 AND p.proname = $2
                    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = $3
                """, binds: binds)
    }

    private static func relkinds(_ category: SchemaNode.Category) -> [String] {
        switch category {
        case .tables:
            return ["r", "p", "f"]
        case .views:
            return ["v"]
        case .materializedViews:
            return ["m"]
        case .sequences:
            return ["S"]
        case .functions, .types:
            return []
        }
    }

    // MARK: - Rows to nodes

    /// The children of `parent` from the rows of `children(of:)`.
    static func nodes(for parent: SchemaNode, rows: [PostgresRow]) throws -> [SchemaNode] {
        try rows.map { row in try node(for: parent, row: row.makeRandomAccess()) }
    }

    private static func node(for parent: SchemaNode, row: PostgresRandomAccessRow) throws -> SchemaNode {
        switch parent.kind {
        case .database:
            let name = try row[0].decode(String.self)
            return SchemaNode(id: "\(parent.id)/\(name)", kind: .schema(name), title: name)
        case .category(let category, let schema):
            let name = try row[0].decode(String.self)
            switch category {
            case .tables:
                return SchemaNode(
                    id: "\(parent.id)/\(name)", kind: .relation(schema: schema, name: name, kind: .table), title: name)
            case .views:
                return SchemaNode(
                    id: "\(parent.id)/\(name)", kind: .relation(schema: schema, name: name, kind: .view), title: name)
            case .materializedViews:
                return SchemaNode(
                    id: "\(parent.id)/\(name)", kind: .relation(schema: schema, name: name, kind: .materializedView),
                    title: name)
            case .functions:
                let arguments = try row[1].decode(String.self)
                let result = try row[2].decode(String?.self)
                return SchemaNode(
                    id: "\(parent.id)/\(name)(\(arguments))",
                    kind: .function(schema: schema, name: name, arguments: arguments),
                    title: "\(name)(\(arguments))", subtitle: result)
            case .sequences:
                return SchemaNode(id: "\(parent.id)/\(name)", kind: .sequence(schema: schema, name: name), title: name)
            case .types:
                let labels = try row[1].decode(String.self)
                return SchemaNode(
                    id: "\(parent.id)/\(name)", kind: .type(schema: schema, name: name), title: name,
                    subtitle: labels.isEmpty ? nil : labels)
            }
        case .section(let section, _, _, _):
            switch section {
            case .columns:
                let column = SchemaNode.Column(
                    name: try row[0].decode(String.self), type: try row[1].decode(String.self),
                    isNotNull: try row[2].decode(Bool.self), defaultValue: try row[3].decode(String?.self),
                    isPrimaryKey: try row[4].decode(Bool.self))
                return SchemaNode(
                    id: "\(parent.id)/\(column.name)", kind: .column(column), title: column.name,
                    subtitle: columnSubtitle(column))
            case .indexes, .constraints:
                let name = try row[0].decode(String.self)
                return SchemaNode(
                    id: "\(parent.id)/\(name)", kind: .detail, title: name, subtitle: try row[1].decode(String.self))
            case .incomingForeignKeys:
                let table = SQLIdentifier.qualified(try row[0].decode(String.self), try row[1].decode(String.self))
                let name = try row[2].decode(String.self)
                return SchemaNode(
                    id: "\(parent.id)/\(table)/\(name)", kind: .detail, title: "\(table) \(name)",
                    subtitle: try row[3].decode(String.self))
            case .definition:
                let definition = try row[0].decode(String.self)
                return SchemaNode(id: "\(parent.id)/definition", kind: .detail, title: definition)
            }
        case .schema, .relation, .function, .sequence, .type, .column, .detail, .truncated:
            throw PostgresError.underlying(PostgresDecodingError.Code.failure)
        }
    }

    /// R6: `type NOT NULL DEFAULT x, PK` next to the column's name.
    static func columnSubtitle(_ column: SchemaNode.Column) -> String {
        var parts = [column.type]
        if column.isPrimaryKey {
            parts.append("PK")
        }
        if column.isNotNull {
            parts.append("NOT NULL")
        }
        if let defaultValue = column.defaultValue {
            parts.append("DEFAULT \(defaultValue)")
        }
        return parts.joined(separator: " ")
    }

    /// Edge cases: over `limit` rows, the level keeps `limit` of them and ends with the
    /// "load all" row.
    static func truncated(_ nodes: [SchemaNode], parent: SchemaNode, limit: Int = limit) -> [SchemaNode] {
        guard nodes.count > limit else { return nodes }
        return Array(nodes.prefix(limit)) + [
            SchemaNode(
                id: "\(parent.id)/…", kind: .truncated(parent: parent.id),
                title: "… more than \(limit) objects (click to load all)")
        ]
    }
}
