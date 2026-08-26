import Foundation
import Observation
import os

/// A folder opened in a window, and everything Wraith knows about it: its config, its persisted
/// state and the FSEvents stream the features share (config, architecture).
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

    /// The single FSEvents stream of this workspace (architecture: shared services).
    let fsWatch: FSWatchService

    /// Every config accepted after a change on disk (config R6).
    ///
    /// Features subscribe from a task they own; nothing is emitted for a rejected file.
    let configChanges: AsyncStream<WorkspaceConfig>

    private let configChangesContinuation: AsyncStream<WorkspaceConfig>.Continuation
    private let stateWriteDelay: Duration
    private var pendingStateWrite: Task<Void, Never>?
    private var isPersistenceDisabled = false
    private var configWatch: Task<Void, Never>?
    /// terminal R3: resolved once, see `Workspace+LoginEnvironment`.
    var loginEnvironmentTask: Task<[String: String], Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "workspace")

    init(root: URL, stateWriteDelay: Duration = .seconds(1)) {
        self.root = root
        self.stateWriteDelay = stateWriteDelay
        fsWatch = FSWatchService(roots: [root])
        (configChanges, configChangesContinuation) = AsyncStream.makeStream()
    }

    isolated deinit {
        configWatch?.cancel()
        configChangesContinuation.finish()
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
            configChangesContinuation.yield(loaded)
        } catch let error as WorkspaceError {
            logger.error("config.json rejected: \(error.description, privacy: .public)")
            configError = error
        } catch {
            logger.error("config.json rejected: \(error.localizedDescription, privacy: .public)")
            configError = .invalidJSON(file: root, line: nil, message: error.localizedDescription)
        }
    }

    /// config R6: reloads the config whenever the file changes on disk.
    func watchConfig() {
        guard configWatch == nil else { return }
        let file = WorkspaceConfig.file(under: root)
        configWatch = Task { [weak self, fsWatch] in
            for await _ in await fsWatch.changes(under: file) {
                guard let self else { return }
                await self.reloadConfig()
            }
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
        guard !isPersistenceDisabled else { return }
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

    /// Stops persisting for good: a window that closes without having been used writes nothing.
    func disablePersistence() {
        isPersistenceDisabled = true
        pendingStateWrite?.cancel()
        pendingStateWrite = nil
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
