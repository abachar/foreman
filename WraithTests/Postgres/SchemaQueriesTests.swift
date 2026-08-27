import Foundation
import PostgresNIO
import Testing

@testable import Wraith

/// postgres R6, R7, R15: the catalog queries per level; values bound, never in the text.
struct SchemaQueriesTests {
    private let database = SchemaNode(id: "db", kind: .database, title: "ccoe")
    private let hostile = "x\"y'; DROP TABLE t; --"

    private func count(_ placeholder: String, in sql: String) -> Int {
        sql.components(separatedBy: placeholder).count - 1
    }

    @Test func schemasBindTheSystemToggleAndTheLimit() throws {
        let query = try #require(SchemaQueries.children(of: database, showsSystemSchemas: false))
        #expect(query.sql.contains("pg_catalog.pg_namespace"))
        #expect(query.binds.count == 2)
        #expect(query.sql.hasSuffix("LIMIT $2"))
        #expect(query.sql.contains(#"pg\_toast%"#))
        #expect(!query.sql.contains("information_schema n"))
    }

    @Test func loadAllDropsTheLimit() throws {
        let query = try #require(SchemaQueries.children(of: database, showsSystemSchemas: true, limit: nil))
        #expect(query.binds.count == 1)
        #expect(!query.sql.contains("LIMIT"))
    }

    @Test func schemaChildrenAreStatic() {
        let schema = SchemaNode(id: "db/public", kind: .schema("public"), title: "public")
        #expect(SchemaQueries.children(of: schema, showsSystemSchemas: false) == nil)
        #expect(schema.staticChildren?.map(\.title) == SchemaNode.Category.allCases.map(\.rawValue))
    }

    @Test(arguments: SchemaNode.Category.allCases)
    func everyCategoryBindsItsSchemaAndNeverInterpolatesIt(category: SchemaNode.Category) throws {
        let node = SchemaNode(
            id: "db/s/\(category)", kind: .category(category, schema: hostile), title: category.rawValue)
        let query = try #require(SchemaQueries.children(of: node, showsSystemSchemas: false))
        #expect(!query.sql.contains("DROP"))
        #expect(!query.sql.contains(hostile))
        #expect(query.sql.contains("pg_catalog."))
        #expect(!query.sql.contains("information_schema"))
        #expect(query.binds.count >= 2)
        #expect(count("$1", in: query.sql) >= 1)
        #expect(query.sql.hasSuffix("LIMIT $\(query.binds.count)"))
    }

    @Test(arguments: SchemaNode.Section.allCases)
    func everySectionBindsSchemaAndRelation(section: SchemaNode.Section) throws {
        let node = SchemaNode(
            id: "db/s/t/\(section)", kind: .section(section, schema: hostile, relation: hostile, kind: .table),
            title: section.rawValue)
        let query = try #require(SchemaQueries.children(of: node, showsSystemSchemas: false))
        #expect(!query.sql.contains(hostile))
        #expect(query.binds.count == 3)
        #expect(count("$1", in: query.sql) == 1)
        #expect(count("$2", in: query.sql) == 1)
    }

    @Test func relationSectionsDependOnTheKind() {
        let table = SchemaNode(id: "t", kind: .relation(schema: "public", name: "t", kind: .table), title: "t")
        let view = SchemaNode(id: "v", kind: .relation(schema: "public", name: "v", kind: .view), title: "v")
        let materialized = SchemaNode(
            id: "m", kind: .relation(schema: "public", name: "m", kind: .materializedView), title: "m")
        #expect(table.staticChildren?.map(\.title) == ["Columns", "Indexes", "Constraints", "Incoming Foreign Keys"])
        #expect(view.staticChildren?.map(\.title) == ["Columns", "Definition"])
        #expect(materialized.staticChildren?.map(\.title) == ["Columns", "Indexes", "Definition"])
        #expect(SchemaQueries.children(of: table, showsSystemSchemas: false) == nil)
    }

    @Test func leavesHaveNoQuery() {
        let column = SchemaNode(
            id: "c",
            kind: .column(
                SchemaNode.Column(name: "id", type: "integer", isNotNull: true, defaultValue: nil, isPrimaryKey: true)),
            title: "id")
        #expect(SchemaQueries.children(of: column, showsSystemSchemas: false) == nil)
        #expect(!column.isExpandable)
        #expect(column.staticChildren == nil)
    }

    @Test func selectAllQuotesTheRelationOnly() {
        let table = SchemaNode(
            id: "t", kind: .relation(schema: "My Schema", name: "order", kind: .table), title: "order")
        #expect(SchemaQueries.selectAll(table) == "SELECT * FROM \"My Schema\".\"order\" LIMIT 500")
        let schema = SchemaNode(id: "s", kind: .schema("public"), title: "public")
        #expect(SchemaQueries.selectAll(schema) == nil)
    }

    @Test func qualifiedNamesPerKind() {
        #expect(SchemaNode(id: "s", kind: .schema("Public"), title: "").qualifiedName == "\"Public\"")
        #expect(
            SchemaNode(id: "f", kind: .function(schema: "public", name: "f", arguments: "integer"), title: "")
                .qualifiedName == "public.f")
        #expect(SchemaNode(id: "d", kind: .database, title: "").qualifiedName == nil)
    }

    @Test func functionDefinitionBindsTheSignature() {
        let query = SchemaQueries.functionDefinition(schema: hostile, name: hostile, arguments: hostile)
        #expect(!query.sql.contains(hostile))
        #expect(query.binds.count == 3)
    }

    @Test func columnSubtitleListsTheFlags() {
        let column = SchemaNode.Column(
            name: "id", type: "character varying(255)", isNotNull: true, defaultValue: "'x'::text", isPrimaryKey: true)
        #expect(SchemaQueries.columnSubtitle(column) == "character varying(255) PK NOT NULL DEFAULT 'x'::text")
        let plain = SchemaNode.Column(
            name: "n", type: "numeric(10,2)", isNotNull: false, defaultValue: nil, isPrimaryKey: false)
        #expect(SchemaQueries.columnSubtitle(plain) == "numeric(10,2)")
    }

    @Test func levelsOverTheBoundAreTruncatedWithALoadAllRow() {
        let parent = SchemaNode(id: "p", kind: .category(.tables, schema: "public"), title: "Tables")
        let nodes = (0..<7).map {
            SchemaNode(id: "p/\($0)", kind: .relation(schema: "public", name: "\($0)", kind: .table), title: "\($0)")
        }
        let truncated = SchemaQueries.truncated(nodes, parent: parent, limit: 5)
        #expect(truncated.count == 6)
        #expect(truncated.last?.kind == .truncated(parent: "p"))
        #expect(truncated.last?.title.contains("5") == true)
        #expect(SchemaQueries.truncated(Array(nodes.prefix(5)), parent: parent, limit: 5).count == 5)
    }
}
