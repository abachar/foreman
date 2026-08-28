import Foundation
import Observation
import os

/// The history as the sheet reads it (postgres R20): loaded once, written after every change,
/// off the main actor and one write at a time.
@Observable
@MainActor
final class PostgresHistoryModel {
    private(set) var history = QueryHistory.empty
    private(set) var isLoaded = false
    var filter = ""
    /// The query tab the sheet is open for; `nil` closes it.
    var presentedFor: TabID?

    private let root: URL
    private var pendingWrite: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "postgres")

    init(root: URL) {
        self.root = root
    }

    var entries: [QueryHistory.Entry] {
        history.search(filter)
    }

    func load() async {
        guard !isLoaded else { return }
        history = await QueryHistory.load(root: root)
        isLoaded = true
    }

    /// R20: every run, successful or not; the history is read first so nothing is overwritten.
    func record(_ entry: QueryHistory.Entry) {
        Task {
            await load()
            history.append(entry)
            write()
        }
    }

    func setPinned(_ id: UUID, _ isPinned: Bool) {
        history.setPinned(id, isPinned)
        write()
    }

    private func write() {
        let snapshot = history
        let previous = pendingWrite
        pendingWrite = Task { [root, logger] in
            await previous?.value
            do {
                try await QueryHistory.write(snapshot, root: root)
            } catch {
                logger.error("postgres-history.json not written: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
