import Foundation
import Observation
import os

/// A folder opened in a window, and everything Foreman knows about it: its config, its persisted
/// state and the FSEvents stream the features share (config, architecture).
@Observable
@MainActor
final class Workspace {
    let root: URL

    /// The last valid configuration: an invalid file never replaces it (config R7).
    private(set) var config: WorkspaceConfig = .empty

    /// Why the last reload was rejected, one per file (config R4, R7); empty when both are current.
    private(set) var configErrors: [WorkspaceError] = []

    /// config R4: the file merged under the workspace's, watched and reloaded the same way.
    let globalConfigFile: URL

    /// The persisted state, as read at startup then updated by the features (config R8).
    private(set) var state: WorkspaceState = .empty

    /// `false` once a write of `state.json` failed: the app runs without persistence and says so
    /// once (config, edge cases: read-only root).
    private(set) var isStatePersisted = true

    /// The single FSEvents stream of this workspace (architecture: shared services).
    let fsWatch: FSWatchService

    private var configSubscribers: [UUID: AsyncStream<WorkspaceConfig>.Continuation] = [:]
    /// config R7: the last valid version of each file; an invalid one never replaces its own.
    private var globalSections: [String: Data] = [:]
    private var workspaceSections: [String: Data] = [:]
    private let stateWriteDelay: Duration
    private var pendingStateWrite: Task<Void, Never>?
    private var isPersistenceDisabled = false
    private var configWatch: Task<Void, Never>?
    /// terminal R3: resolved once, see `Workspace+LoginEnvironment`.
    var loginEnvironmentTask: Task<[String: String], Never>?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "workspace")

    init(
        root: URL, stateWriteDelay: Duration = .seconds(1),
        globalConfigFile: URL = WorkspaceConfig.globalFile()
    ) {
        self.root = root
        self.stateWriteDelay = stateWriteDelay
        self.globalConfigFile = globalConfigFile
        // config R4, R6: one stream for both files; FSEvents needs a folder that exists.
        fsWatch = FSWatchService(roots: [root] + (Self.existingFolder(of: globalConfigFile).map { [$0] } ?? []))
        Self.migrateLegacyFolder(in: root)
    }

    /// The deepest folder above `file` that exists, so FSEvents has something to watch.
    ///
    /// `~/.config/foreman/` is often absent; watching `~/.config/` still catches the file being
    /// created, and the subscription filters on the path anyway.
    nonisolated static func existingFolder(of file: URL) -> URL? {
        var folder = file.deletingLastPathComponent()
        while folder.path(percentEncoded: false) != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return folder
            }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    /// The app was Wraith until 2026-08-28 (product decision): a `.wraith/` folder with no
    /// `.foreman/` next to it is renamed once, config, state and history included.
    nonisolated static func migrateLegacyFolder(in root: URL) {
        let legacy = root.appending(path: ".wraith")
        let current = root.appending(path: ".foreman")
        let files = FileManager.default
        guard files.fileExists(atPath: legacy.path(percentEncoded: false)),
            !files.fileExists(atPath: current.path(percentEncoded: false))
        else { return }
        try? files.moveItem(at: legacy, to: current)
    }

    /// Every config accepted after a change on disk (config R6), one stream per consumer.
    ///
    /// Features subscribe from a task they own; nothing is emitted for a rejected file.
    func configChanges() -> AsyncStream<WorkspaceConfig> {
        let (stream, continuation) = AsyncStream<WorkspaceConfig>.makeStream()
        let key = UUID()
        configSubscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.configSubscribers[key] = nil }
        }
        return stream
    }

    isolated deinit {
        configWatch?.cancel()
        for continuation in configSubscribers.values {
            continuation.finish()
        }
    }

    // MARK: - Config

    /// Reads both `config.json` again and merges them (config R4).
    ///
    /// Warnings are logged; a file that does not parse keeps the last valid version of *that* file
    /// and is reported on its own (config R7), so a broken global never hides the workspace's.
    func reloadConfig() async {
        var errors: [WorkspaceError] = []
        var read = false
        for file in [globalConfigFile, WorkspaceConfig.file(under: root)] {
            do {
                let sections = try await WorkspaceConfig.readSections(file)
                if file == globalConfigFile {
                    globalSections = sections
                } else {
                    workspaceSections = sections
                }
                read = true
            } catch let error as WorkspaceError {
                logger.error("config rejected: \(error.description, privacy: .public)")
                errors.append(error)
            } catch {
                logger.error("config rejected: \(error.localizedDescription, privacy: .public)")
                errors.append(.invalidJSON(file: file, line: nil, message: error.localizedDescription))
            }
        }
        configErrors = errors
        guard read else { return }
        let merged = WorkspaceConfig.make(
            WorkspaceConfig.merge(global: globalSections, workspace: workspaceSections), root: root)
        for warning in merged.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        config = merged
        for continuation in configSubscribers.values {
            continuation.yield(merged)
        }
    }

    /// config R4, R6: reloads whenever either file changes on disk.
    func watchConfig() {
        guard configWatch == nil else { return }
        let files = [WorkspaceConfig.file(under: root), globalConfigFile]
        configWatch = Task { [weak self, fsWatch] in
            await withDiscardingTaskGroup { group in
                for file in files {
                    group.addTask {
                        for await _ in await fsWatch.changes(under: file) {
                            guard let self else { return }
                            await self.reloadConfig()
                        }
                    }
                }
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
