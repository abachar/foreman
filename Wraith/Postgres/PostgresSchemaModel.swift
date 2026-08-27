import Foundation
import Observation
import PostgresNIO
import os

/// The state of the schema tree (postgres R6, R7): levels loaded on expansion, one query each,
/// nothing before (architecture P4).
@Observable
@MainActor
final class PostgresSchemaModel {
    /// The tree's root; `nil` until a database is configured.
    private(set) var root: SchemaNode?
    private(set) var levels: [String: [SchemaNode]] = [:]
    private(set) var loading: Set<String> = []
    /// R6: `pg_catalog`, `information_schema`, `pg_toast*` behind a toggle.
    var showsSystemSchemas = false
    /// R8: a case-insensitive filter over the loaded names.
    var filter = ""
    /// Bumped at every change of a level; the outline view reloads what changed.
    private(set) var version = 0
    private(set) var lastLoaded: String?
    /// R8: the DDL being shown.
    var ddl: DDLDocument?

    private let feature: PostgresFeature
    private var tasks: [String: Task<Void, Never>] = [:]
    private let logger = os.Logger(subsystem: "dev.crafters.wraith", category: "postgres")

    struct DDLDocument: Identifiable {
        let id: String
        let text: String
    }

    init(feature: PostgresFeature) {
        self.feature = feature
    }

    /// R2: the root follows the configured database; a new database drops every level.
    func setDatabase(_ name: String?) {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        levels = [:]
        loading = []
        root = name.map { SchemaNode(id: "db", kind: .database, title: $0) }
        bump(nil)
    }

    // MARK: - Reading

    func level(_ id: String) -> [SchemaNode]? {
        levels[id]
    }

    /// The rows the outline shows under `node`: the loaded level through the filter.
    func visibleChildren(of node: SchemaNode) -> [SchemaNode] {
        guard let children = levels[node.id] else { return [] }
        guard !filter.isEmpty else { return children }
        return children.filter { matches($0) }
    }

    /// R8: a row stays when its name matches or any loaded descendant does.
    private func matches(_ node: SchemaNode) -> Bool {
        if node.title.localizedCaseInsensitiveContains(filter) {
            return true
        }
        if case .truncated = node.kind {
            return true
        }
        return levels[node.id]?.contains { matches($0) } ?? false
    }

    // MARK: - Loading (R7)

    /// Loads the children of `node` once; `all` ignores the 5,000 bound (edge cases).
    func load(_ node: SchemaNode, all: Bool = false) async {
        guard node.isExpandable, tasks[node.id] == nil else { return }
        if let children = node.staticChildren {
            levels[node.id] = children
            bump(node.id)
            return
        }
        guard
            let query = SchemaQueries.children(
                of: node, showsSystemSchemas: showsSystemSchemas, limit: all ? nil : SchemaQueries.limit)
        else { return }
        loading.insert(node.id)
        let task = Task { [weak self] in
            defer { self?.loading.remove(node.id) }
            do {
                let rows = try await self?.feature.rows(query) ?? []
                guard let self, !Task.isCancelled else { return }
                let nodes = try SchemaQueries.nodes(for: node, rows: rows)
                levels[node.id] = all ? nodes : SchemaQueries.truncated(nodes, parent: node)
                bump(node.id)
            } catch {
                // R5: the feature's model carries the banner; the level stays unloaded.
                self?.logger.debug("level \(node.id, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
        tasks[node.id] = task
        await task.value
        tasks[node.id] = nil
    }

    /// Edge cases: the "load all" row.
    func loadAll(parent id: String) async {
        guard let parent = node(id) else { return }
        forget(id)
        await load(parent, all: true)
    }

    /// R7: *Refresh* on a node drops its level and every level under it; the outline reloads
    /// what is still expanded.
    func refresh(_ node: SchemaNode?) async {
        let target = node ?? root
        guard let target else { return }
        forget(target.id)
        await load(target)
    }

    private func forget(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        for key in levels.keys where key == id || key.hasPrefix(id + "/") {
            levels[key] = nil
        }
    }

    /// The node with `id` among the loaded rows (`nil` once its parent was refreshed).
    func node(_ id: String) -> SchemaNode? {
        if root?.id == id {
            return root
        }
        for level in levels.values {
            if let node = level.first(where: { $0.id == id }) {
                return node
            }
        }
        return nil
    }

    private func bump(_ id: String?) {
        lastLoaded = id
        version += 1
    }

    // MARK: - Actions (R8)

    /// *View the DDL*: tables from the loaded rows, views from `pg_get_viewdef`, functions from
    /// `pg_get_functiondef`, an index from its definition.
    func showDDL(of node: SchemaNode) async {
        switch node.kind {
        case .relation(let schema, let name, let kind):
            await showRelationDDL(node, schema: schema, name: name, kind: kind)
        case .function(let schema, let name, let arguments):
            do {
                let rows = try await feature.rows(
                    SchemaQueries.functionDefinition(schema: schema, name: name, arguments: arguments))
                let text = try rows.first?.makeRandomAccess()[0].decode(String.self) ?? "-- not found"
                ddl = DDLDocument(id: node.id, text: text)
            } catch {
                logger.debug("function DDL failed: \(error, privacy: .public)")
            }
        case .detail:
            if let text = node.subtitle {
                ddl = DDLDocument(id: node.id, text: text + ";")
            }
        case .database, .schema, .category, .sequence, .type, .section, .column, .truncated:
            break
        }
    }

    private func showRelationDDL(
        _ node: SchemaNode, schema: String, name: String, kind: SchemaNode.RelationKind
    ) async {
        for section in node.staticChildren ?? [] where levels[section.id] == nil {
            await load(section)
        }
        func level(_ section: SchemaNode.Section) -> [SchemaNode] {
            levels["\(node.id)/\(section.rawValue)"] ?? []
        }
        let definitions: ([SchemaNode]) -> [SchemaDDL.Definition] = { nodes in
            nodes.compactMap { row in row.subtitle.map { SchemaDDL.Definition(name: row.title, text: $0) } }
        }
        let text: String
        switch kind {
        case .table:
            let columns = level(.columns).compactMap { row -> SchemaNode.Column? in
                guard case .column(let column) = row.kind else { return nil }
                return column
            }
            text = SchemaDDL.table(
                schema: schema, name: name, columns: columns, constraints: definitions(level(.constraints)),
                indexes: definitions(level(.indexes)))
        case .view, .materializedView:
            guard let definition = level(.definition).first?.title else { return }
            text = SchemaDDL.view(
                schema: schema, name: name, isMaterialized: kind == .materializedView, definition: definition)
        }
        ddl = DDLDocument(id: node.id, text: text)
    }
}
