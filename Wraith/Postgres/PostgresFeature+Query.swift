import AppKit
import Foundation
import PostgresNIO
import SwiftUI

/// The `postgres.query` center tabs (postgres R9, R10, R12–R14, R17, R19; decision 2026-08-27:
/// a center tab, not the bottom panel).
extension PostgresFeature {
    func registerQueryTab() {
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.queryTabKind,
                makeView: { [weak self] id, payload in self?.queryView(id, payload: payload) },
                serialize: { [weak self] id in self?.queryTabs[id]?.payload.encoded() },
                onClose: { [weak self] id in
                    guard let self else { return }
                    if case .running(let tab) = execution, tab == id {
                        stop()
                    }
                    queryTabs[id] = nil
                }))
        layout.shortcuts.register(
            ShortcutAction(id: Self.queryTabKind, title: "New Query", defaultShortcut: "cmd+shift+q") { [weak self] in
                self?.newQueryTab()
            })
        // R9: `cmd+/` toggles `--` comments, like the file editor's `editor.comment`.
        layout.shortcuts.register(
            ShortcutAction(
                id: "postgres.comment", title: "Comment SQL", scope: .tab(kind: Self.queryTabKind),
                defaultShortcut: "cmd+/"
            ) { [weak self] in
                self?.toggleComment()
            })
        runQuery = { [weak self] sql in
            guard let self, let tab = newQueryTab(text: sql) else { return }
            run(tab)
        }
        insertIntoEditor = { [weak self] name in
            guard let self, let tab = activeQueryTab ?? newQueryTab() else { return }
            tab.pendingInsertion = name
        }
    }

    private func queryView(_ id: TabID, payload: String) -> AnyView? {
        let decoded = PostgresQueryTab.Payload.decode(payload) ?? PostgresQueryTab.Payload(title: "Query", text: "")
        let tab = PostgresQueryTab(id: id, title: decoded.title, text: decoded.text)
        queryTabs[id] = tab
        return AnyView(PostgresQueryView(tab: tab, connection: model, feature: self, theme: theme))
    }

    /// `cmd+shift+q`: a new tab, `Query N`, in the active group.
    @discardableResult
    func newQueryTab(text: String = "") -> PostgresQueryTab? {
        queryCount += 1
        let payload = PostgresQueryTab.Payload(title: "Query \(queryCount)", text: text)
        guard let id = layout.openTab(kind: Self.queryTabKind, title: payload.title, payload: payload.encoded())
        else { return nil }
        return queryTabs[id]
    }

    var activeQueryTab: PostgresQueryTab? {
        guard let active = layout.model.active.active, active.kind == Self.queryTabKind else { return nil }
        return queryTabs[active.id]
    }

    private func toggleComment() {
        guard let tab = activeQueryTab, let textView = tab.textView else { return }
        let edit = TextEditing.toggleComment(textView.selectedRange(), in: textView.string as NSString, prefix: "--")
        textView.insertText(edit.replacement, replacementRange: edit.range)
        textView.setSelectedRange(edit.selection)
    }

    // MARK: - Running (R10, R12, R14, R17, R19)

    /// R10: the selection or the buffer, as one statement; R14: refused (a beep) while another
    /// runs.
    func run(_ tab: PostgresQueryTab) {
        guard let client else { return }
        guard let next = execution.starting(tab.id) else {
            NSSound.beep()
            return
        }
        guard let statement = QueryExecution.statement(in: tab.text, selection: tab.selection) else { return }
        execution = next
        tab.start()
        let clock = ContinuousClock()
        let started = clock.now
        executionTask = Task { [weak self] in
            defer {
                self?.execution = .idle
                self?.executionTask = nil
            }
            do {
                let sequence = try await client.execute(PostgresQuery(unsafeSQL: statement.sql))
                var page: [PostgresQueryTab.Result.Row] = []
                var count = 0
                var isTruncated = false
                for try await row in sequence {
                    if count == 0 {
                        tab.setColumns(row.map(\.columnName))
                    }
                    page.append(PostgresQueryTab.Result.Row(id: count, cells: row.map(QueryCell.text(of:))))
                    count += 1
                    if page.count == Self.pageSize {
                        tab.append(page)
                        page = []
                    }
                    if count >= Self.rowLimit {
                        // R12: the task stops reading and the server is told to stop too (R13).
                        isTruncated = true
                        break
                    }
                }
                tab.append(page)
                if isTruncated {
                    try? await client.cancelRunning()
                }
                tab.finish(duration: clock.now - started, isTruncated: isTruncated)
                self?.model.error = nil
            } catch {
                let classified = PostgresError.classify(error)
                var position: Int?
                if case .server(_, _, let at) = classified {
                    position = at
                }
                let cursor = QueryExecution.cursorLocation(
                    position: position, sent: statement.range, textLength: (tab.text as NSString).length)
                tab.fail(classified, cursor: classified.isServerError ? cursor : nil)
                if case .authenticationFailed = classified {
                    self?.invalidatePasswordIfAsked()
                }
            }
        }
    }

    /// R13: *Stop* / `cmd+.`: the task is cancelled and the server told; no answer within 5 s
    /// → the connection is closed.
    func stop() {
        guard case .running = execution, let client else { return }
        executionTask?.cancel()
        Task {
            let clock = ContinuousClock()
            let started = clock.now
            var answered = false
            let cancel = Task { try await client.cancelRunning() }
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await cancel.value }
                    group.addTask {
                        try await Task.sleep(for: QueryExecution.cancelLimit)
                        throw PostgresError.timeout(QueryExecution.cancelLimit)
                    }
                    try await group.next()
                    group.cancelAll()
                }
                answered = true
            } catch {
                answered = false
            }
            if QueryExecution.shouldDropConnection(answered: answered, elapsed: clock.now - started) {
                await client.close()
            }
        }
    }
}

extension PostgresError {
    /// R19: only a server error carries a position worth moving the cursor to.
    var isServerError: Bool {
        if case .server = self {
            return true
        }
        return false
    }
}
