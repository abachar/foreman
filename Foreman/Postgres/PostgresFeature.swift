import AppKit
import Foundation
import PostgresNIO
import SwiftUI
import os

/// Entry point of the postgres feature (postgres R1–R5).
///
/// It owns the config, the window's client, the password chain (Keychain, `.pgpass`, a sheet)
/// and the connection's lifecycle. Panels register in their own tasks.
@MainActor
final class PostgresFeature {
    static let schemaPanelID: PanelID = "postgres.schema"
    static let queryTabKind = "postgres.query"
    /// R12: free-form SQL stops here.
    static let rowLimit = 50_000

    let model = PostgresModel()
    /// R20: one history per workspace, created with the feature.
    let history: PostgresHistoryModel
    /// R6: the schema tree, created with the panel.
    private(set) lazy var schema = PostgresSchemaModel(feature: self)
    /// R8: set by the query panel (5.6); `nil` hides the actions that need it.
    var runQuery: ((String) -> Void)?
    var insertIntoEditor: ((String) -> Void)?
    var queryTabs: [TabID: PostgresQueryTab] = [:]
    var queryCount = 0
    /// R14: one execution per window.
    var execution = QueryExecution.State.idle
    var executionTask: Task<Void, Never>?
    let layout: LayoutManager
    let theme: ThemeService
    /// postgres R9: the shared highlighter, on the `sql` grammar (2026-08-28).
    let highlighter: Highlighter
    private let workspace: Workspace
    private let secrets: SecretStore
    private(set) var config: PostgresConfig?
    private(set) var client: PostgresClient?
    private var visiblePanels = 0
    /// R3: after a refusal, the next attempt skips the Keychain and `.pgpass` and asks.
    private var mustAsk = false
    private var isShown = false
    private var stateWatch: Task<Void, Never>?
    private var configWatch: Task<Void, Never>?
    private let logger = os.Logger(subsystem: "dev.crafters.foreman", category: "postgres")

    init(
        layout: LayoutManager, workspace: Workspace, secrets: SecretStore, theme: ThemeService,
        highlighter: Highlighter
    ) {
        self.highlighter = highlighter
        self.workspace = workspace
        self.secrets = secrets
        self.layout = layout
        self.theme = theme
        history = PostgresHistoryModel(root: workspace.root)
        registerQueryTab()
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges() {
                self?.apply(config)
            }
        }
    }

    isolated deinit {
        configWatch?.cancel()
        stateWatch?.cancel()
        executionTask?.cancel()
        if let client {
            Task { await client.close() }
        }
    }

    // MARK: - Config (R1, R2; config R6)

    /// The section decoded again; a changed connection closes the previous one (R2).
    private func apply(_ workspaceConfig: WorkspaceConfig) {
        let outcome = PostgresConfig.decode(from: workspaceConfig)
        var decoded: PostgresConfig?
        if case .configured(let config, _) = outcome {
            decoded = config
        }
        // R2 (2026-08-29), layout R36: the panel and the global shortcuts exist only with a section.
        show(decoded != nil)
        guard decoded != config || client == nil else {
            model.apply(outcome)
            return
        }
        config = decoded
        mustAsk = false
        model.apply(outcome)
        replaceClient(with: decoded.map(makeClient))
        schema.setDatabase(decoded?.database)
    }

    private func show(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        guard shown else {
            layout.unregister(panel: Self.schemaPanelID)
            layout.shortcuts.unregister(Self.queryTabKind)
            layout.shortcuts.unregister("postgres.history")
            return
        }
        // R4: `activate` connects nothing; the tree's first expansion does.
        layout.register(
            panel: PanelDescriptor(
                id: Self.schemaPanelID, title: "Schema", side: .right, icon: "cylinder", defaultShortcut: "cmd+shift+b",
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(
                        PostgresSchemaPanelView(model: schema, connection: model, feature: self, theme: theme))
                },
                activate: { [weak self] in self?.panelActivated() },
                deactivate: { [weak self] in self?.panelDeactivated() }))
        layout.shortcuts.register(
            ShortcutAction(id: Self.queryTabKind, title: "New Query", defaultShortcut: "cmd+shift+q") { [weak self] in
                self?.newQueryTab()
            })
        // R20: no default shortcut (`cmd+opt+h` is macOS Hide Others), `config.shortcuts` can set one.
        layout.shortcuts.register(
            ShortcutAction(id: "postgres.history", title: "Query History", defaultShortcut: nil) { [weak self] in
                guard let self, let tab = activeQueryTab ?? newQueryTab() else { return }
                showHistory(for: tab)
            })
    }

    private func makeClient(_ config: PostgresConfig) -> PostgresClient {
        PostgresClient(config: config) { [weak self] () async throws(PostgresError) -> String in
            guard let self else { throw PostgresError.passwordRequired }
            return try await resolvePassword(for: config)
        }
    }

    private func replaceClient(with client: PostgresClient?) {
        stateWatch?.cancel()
        if let previous = self.client {
            Task { await previous.close() }
        }
        self.client = client
        guard let client else { return }
        stateWatch = Task { [weak self] in
            for await state in client.states {
                self?.model.setState(state)
            }
        }
    }

    // MARK: - Password (R3)

    /// The section's `password` if set, else Keychain, then `~/.pgpass`, then a sheet; the choice to
    /// save goes back to the Keychain.
    private func resolvePassword(for config: PostgresConfig) async throws(PostgresError) -> String {
        if let password = config.password {
            return password
        }
        let account = config.keychainAccount
        if !mustAsk {
            if let secret = Self.stored(in: secrets, account: account) {
                return secret
            }
            var warnings: [String] = []
            let fromFile = PgPass.password(
                in: PgPass.defaultFile(), host: config.host, port: config.port, database: config.database,
                user: config.user, warnings: &warnings)
            for warning in warnings {
                model.addWarning(warning)
            }
            if let fromFile {
                return fromFile
            }
        }
        guard let answer = await askPassword(label: config.label) else { throw PostgresError.passwordRequired }
        mustAsk = false
        if answer.saveToKeychain {
            do {
                try secrets.write(answer.password, account)
            } catch {
                model.addWarning("Password not saved: \(error.description)")
            }
        }
        return answer.password
    }

    private nonisolated static func stored(in secrets: SecretStore, account: String) -> String? {
        do {
            return try secrets.read(account)
        } catch {
            return nil
        }
    }

    private struct PasswordAnswer {
        let password: String
        let saveToKeychain: Bool
    }

    /// R3: a sheet with a secure field and *Save to the Keychain* checked by default.
    private func askPassword(label: String) async -> PasswordAnswer? {
        guard let window = NSApp.keyWindow else { return nil }
        let alert = NSAlert()
        alert.messageText = "Password for \(label)"
        alert.informativeText = "Foreman keeps it in your login keychain when the box is checked."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let checkbox = NSButton(checkboxWithTitle: "Save to the Keychain", target: nil, action: nil)
        checkbox.state = .on
        let stack = NSStackView(views: [field, checkbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = await alert.beginSheetModal(for: window)
        guard response == .alertFirstButtonReturn else { return nil }
        return PasswordAnswer(password: field.stringValue, saveToKeychain: checkbox.state == .on)
    }

    // MARK: - Lifecycle (R4)

    /// A panel of the feature became visible; nothing connects here (R4: lazy).
    func panelActivated() {
        visiblePanels += 1
    }

    /// A panel was hidden: with none left and nothing running, the connection closes.
    func panelDeactivated() {
        visiblePanels = max(0, visiblePanels - 1)
        guard let client else { return }
        Task { [weak self] in
            let idle = ContinuousClock.now - (await client.lastActivity)
            // R4: a query tab still running, or a catalog query still streaming, keeps it.
            let isBusy = await client.isBusy
            guard let self,
                ConnectionLifecycle.action(
                    visiblePanels: visiblePanels, isBusy: isBusy || execution.isBusy, idle: idle) == .close
            else { return }
            await client.close()
        }
    }

    // MARK: - Queries (R7, R15)

    /// Every row of a Foreman-generated query; a refused password invalidates the Keychain entry
    /// and asks once more (R3).
    func rows(_ query: PostgresQuery) async throws(PostgresError) -> [PostgresRow] {
        guard let client, let config else { throw PostgresError.notConfigured(model.configMessage ?? "") }
        do {
            let rows = try await client.rows(query)
            model.error = nil
            return rows
        } catch .authenticationFailed where config.password == nil {
            // A password written in the config is the user's: refused stays refused (R3).
            invalidatePassword(config)
            let rows = try await client.rows(query)
            model.error = nil
            return rows
        } catch {
            model.error = error.description
            throw error
        }
    }

    /// R3 for the query path: a refused config password is not invalidated.
    func invalidatePasswordIfAsked() {
        guard let config, config.password == nil else { return }
        invalidatePassword(config)
    }

    private func invalidatePassword(_ config: PostgresConfig) {
        mustAsk = true
        do {
            try secrets.delete(config.keychainAccount)
        } catch {
            logger.warning("keychain entry not removed: \(error.description, privacy: .public)")
        }
    }

    // MARK: - Schema actions (R8)

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyQualifiedName(_ node: SchemaNode) {
        node.qualifiedName.map(copy)
    }

    func insertName(_ node: SchemaNode) {
        guard let name = node.qualifiedName else { return }
        insertIntoEditor?(name)
    }

    /// US7: `SELECT * FROM schema.table LIMIT 500` in the query panel.
    func selectAll(_ node: SchemaNode) {
        guard let sql = SchemaQueries.selectAll(node) else { return }
        runQuery?(sql)
    }

    /// R11: the *Allow writes* toggle.
    func setAllowWrites(_ allowed: Bool) {
        model.setAllowWrites(allowed)
        guard let client else { return }
        Task {
            do {
                try await client.setAllowWrites(allowed)
            } catch {
                model.error = PostgresError.classify(error).description
            }
        }
    }
}
