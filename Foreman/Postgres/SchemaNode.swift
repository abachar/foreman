import Foundation

/// One row of the schema tree (postgres R6): the feature's own type, built from `pg_catalog`
/// rows by `SchemaQueries` (architecture: third-party types stay near their use).
nonisolated struct SchemaNode: Identifiable, Hashable, Sendable {
    /// R6: the six groups under a schema.
    enum Category: String, CaseIterable, Sendable {
        case tables = "Tables"
        case views = "Views"
        case materializedViews = "Materialized Views"
        case functions = "Functions"
        case sequences = "Sequences"
        case types = "Types"
    }

    /// R6: what a relation unfolds into.
    enum Section: String, CaseIterable, Sendable {
        case columns = "Columns"
        case indexes = "Indexes"
        case constraints = "Constraints"
        case incomingForeignKeys = "Incoming Foreign Keys"
        case definition = "Definition"
    }

    enum RelationKind: Sendable {
        case table
        case view
        case materializedView
    }

    /// R6: a column, as shown and as the DDL needs it.
    struct Column: Hashable, Sendable {
        let name: String
        /// Formatted by the server's `format_type` (decision 2026-08-27).
        let type: String
        let isNotNull: Bool
        let defaultValue: String?
        let isPrimaryKey: Bool
    }

    enum Kind: Hashable, Sendable {
        case database
        case schema(String)
        case category(Category, schema: String)
        case relation(schema: String, name: String, kind: RelationKind)
        case function(schema: String, name: String, arguments: String)
        case sequence(schema: String, name: String)
        case type(schema: String, name: String)
        case section(Section, schema: String, relation: String, kind: RelationKind)
        case column(Column)
        /// An index, a constraint, a foreign key or a definition: a title and its text.
        case detail
        /// Edge cases: the "more than 5,000" row, a click loads everything.
        case truncated(parent: String)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?

    init(id: String, kind: Kind, title: String, subtitle: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
    }

    var isExpandable: Bool {
        switch kind {
        case .database, .schema, .category, .relation, .section:
            return true
        case .function, .sequence, .type, .column, .detail, .truncated:
            return false
        }
    }

    /// R8: `schema.name`, quoted for SQL; `nil` for a row that is not an object.
    var qualifiedName: String? {
        switch kind {
        case .schema(let name):
            return SQLIdentifier.quote(name)
        case .relation(let schema, let name, _), .function(let schema, let name, _), .sequence(let schema, let name),
            .type(let schema, let name):
            return SQLIdentifier.qualified(schema, name)
        case .database, .category, .section, .column, .detail, .truncated:
            return nil
        }
    }

    /// R6: the children that need no query; `nil` when a query is needed or the row is a leaf.
    var staticChildren: [SchemaNode]? {
        switch kind {
        case .schema(let schema):
            return Category.allCases.map {
                SchemaNode(id: "\(id)/\($0.rawValue)", kind: .category($0, schema: schema), title: $0.rawValue)
            }
        case .relation(let schema, let name, let kind):
            let sections: [Section]
            switch kind {
            case .table:
                sections = [.columns, .indexes, .constraints, .incomingForeignKeys]
            case .view:
                sections = [.columns, .definition]
            case .materializedView:
                sections = [.columns, .indexes, .definition]
            }
            return sections.map {
                SchemaNode(
                    id: "\(id)/\($0.rawValue)", kind: .section($0, schema: schema, relation: name, kind: kind),
                    title: $0.rawValue)
            }
        case .database, .category, .section, .function, .sequence, .type, .column, .detail, .truncated:
            return nil
        }
    }
}
