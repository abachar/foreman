import Foundation
import Observation
import os

/// A folder opened in a window, and everything Wraith knows about it: its config and persisted
/// state today, file watching with the next task (config, architecture).
@Observable
@MainActor
final class Workspace {
    let root: URL

    /// The last valid configuration: an invalid file never replaces it (config R7).
    private(set) var config: WorkspaceConfig = .empty

    /// Why the last reload was rejected, `nil` when `config` is current.
    private(set) var configError: WorkspaceError?

    /// The persisted state, as read at startup then updated by the features (config R8).
    private(set) var state: WorkspaceState = .empty

    /// `false` once a write of `state.json` failed: the app runs without persistence and says so
    /// once (config, edge cases: read-only root).
    private(set) var isStatePersisted = true

    private let stateWriteDelay: Duration
    private var pendingStateWrite: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "workspace")

    init(root: URL, stateWriteDelay: Duration = .seconds(1)) {
        self.root = root
        self.stateWriteDelay = stateWriteDelay
    }

    // MARK: - Config

    /// Reads `config.json` again.
    ///
    /// Warnings are logged, an error keeps the previous config.
    func reloadConfig() async {
        do {
            let loaded = try await WorkspaceConfig.load(root: root)
            for warning in loaded.warnings {
                logger.warning("\(warning, privacy: .public)")
            }
            config = loaded
            configError = nil
        } catch let error as WorkspaceError {
            logger.error("config.json rejected: \(error.description, privacy: .public)")
            configError = error
        } catch {
            logger.error("config.json rejected: \(error.localizedDescription, privacy: .public)")
            configError = .invalidJSON(file: root, line: nil, message: error.localizedDescription)
        }
    }

    // MARK: - State

    /// Reads `state.json` once, at startup.
    func loadState() async {
        state = await WorkspaceState.load(root: root)
    }

    /// Stores a feature's section and schedules the write: ~1 s after the last change, so a burst
    /// of changes costs one write (config R8).
    func setState(_ name: String, to value: some Encodable) {
        do {
            try state.setSection(name, to: value)
        } catch {
            logger.error(
                "state section \(name, privacy: .public) not encodable: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        pendingStateWrite?.cancel()
        pendingStateWrite = Task { [stateWriteDelay] in
            guard (try? await Task.sleep(for: stateWriteDelay)) != nil else { return }
            await writeState()
        }
    }

    /// Writes now what is pending: called when the window closes (config R8).
    func flushState() async {
        guard let pendingStateWrite else { return }
        pendingStateWrite.cancel()
        self.pendingStateWrite = nil
        await writeState()
    }

    private func writeState() async {
        pendingStateWrite = nil
        do {
            try await WorkspaceState.write(state, root: root)
        } catch {
            guard isStatePersisted else { return }
            isStatePersisted = false
            logger.error(
                "state.json not written, running without persistence: \(error.localizedDescription, privacy: .public)")
        }
    }
}
