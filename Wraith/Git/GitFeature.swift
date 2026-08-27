import AppKit
import Foundation
import SwiftUI
import os

/// Entry point of `git`: the `git.changes` panel, the repos and their `GitCLI`, the status runs
/// and the per-file actions (git R1–R9, R28).
@MainActor
final class GitFeature {
    static let panelID: PanelID = "git.changes"

    /// The `git` section of `.wraith/config.json` (git R26).
    nonisolated struct Settings: Decodable, Equatable, Sendable {
        var path: String?
    }

    /// git R26, decision 2026-08-27: resolved once per window, shared by every `GitCLI`.
    nonisolated struct Toolchain: Sendable {
        let executable: URL
        let environment: [String: String]
        let version: GitVersion
    }

    let model = GitModel()
    private let layout: LayoutManager
    private let workspace: Workspace
    private let editor: EditorFeature
    private let theme: ThemeService
    private var toolchain: Task<Toolchain?, Never>?
    private var clients: [String: GitCLI] = [:]
    private var gitDirectories: [String: URL] = [:]
    private var coalescer = RefreshCoalescer()
    private var commitTasks: [String: Task<Void, Never>] = [:]
    private var isActive = false
    private var activation: Task<Void, Never>?
    private var watches: [Task<Void, Never>] = []
    private var configWatch: Task<Void, Never>?
    private var statusSubscribers: [UUID: AsyncStream<GitStatusChange>.Continuation] = [:]
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "git")

    init(layout: LayoutManager, workspace: Workspace, editor: EditorFeature, theme: ThemeService) {
        self.layout = layout
        self.workspace = workspace
        self.editor = editor
        self.theme = theme
        if let state = try? workspace.state.section("git", as: GitState.self) {
            model.restore(state)
        }
        let model = model
        let theme = theme
        layout.register(
            panel: PanelDescriptor(
                id: Self.panelID, title: "Changes", side: .right, defaultShortcut: "cmd+shift+g",
                makeView: { [unowned self] in AnyView(GitChangesPanelView(model: model, feature: self, theme: theme)) },
                activate: { [weak self] in self?.activate() },
                deactivate: { [weak self] in self?.deactivate() }))
        configWatch = Task { [weak self, workspace] in
            for await _ in workspace.configChanges() {
                guard let self, isActive else { continue }
                // git R1: the repos follow `config.repos`; a new `git.path` waits for the next window.
                await discoverAndRefresh()
            }
        }
    }

    isolated deinit {
        activation?.cancel()
        for task in commitTasks.values {
            task.cancel()
        }
        configWatch?.cancel()
        for watch in watches {
            watch.cancel()
        }
        for continuation in statusSubscribers.values {
            continuation.finish()
        }
    }

    /// git R5: every status, one stream per consumer (like `Workspace.configChanges`).
    func statusChanges() -> AsyncStream<GitStatusChange> {
        let (stream, continuation) = AsyncStream<GitStatusChange>.makeStream()
        let key = UUID()
        statusSubscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.statusSubscribers[key] = nil }
        }
        return stream
    }

    // MARK: - Activation (git R3, R4; layout R4)

    private func activate() {
        guard !isActive else { return }
        isActive = true
        activation = Task { [weak self] in
            await self?.discoverAndRefresh()
        }
    }

    private func deactivate() {
        isActive = false
        activation?.cancel()
        activation = nil
        for watch in watches {
            watch.cancel()
        }
        watches = []
    }

    /// git R26, R28: the binary and its version, once; a missing or old git leaves the feature inert.
    private func resolveToolchain() async -> Toolchain? {
        if let toolchain {
            return await toolchain.value
        }
        let task = Task<Toolchain?, Never> { [workspace, model] in
            let login = await workspace.loginEnvironment()
            let override = (try? workspace.config.section("git", as: Settings.self))?.path
            guard let executable = GitCLI.resolveExecutable(inPath: login["PATH"], override: override) else {
                model.setBanner(GitError.gitNotFound.description)
                return nil
            }
            let probe = GitCLI(executable: executable, repo: workspace.root, loginEnvironment: login)
            do throws(GitError) {
                let version = try await probe.version()
                guard version.isSupported else {
                    model.setBanner(
                        "git \(version.major).\(version.minor).\(version.patch) found; 2.35 or newer is required.")
                    return nil
                }
                return Toolchain(executable: executable, environment: login, version: version)
            } catch {
                model.setBanner(error.description)
                return nil
            }
        }
        toolchain = task
        return await task.value
    }

    /// git R1, R3: the repos, one `GitCLI` each, a status on each in parallel, then the watches.
    private func discoverAndRefresh() async {
        guard let toolchain = await resolveToolchain() else { return }
        model.setDiscovering(true)
        let repos = await GitRepo.discover(root: workspace.root, declared: workspace.config.repos)
        guard isActive, !Task.isCancelled else {
            model.setDiscovering(false)
            return
        }
        model.setRepos(repos)
        model.setDiscovering(false)
        for repo in repos where clients[repo.id] == nil {
            clients[repo.id] = GitCLI(
                executable: toolchain.executable, repo: repo.url, loginEnvironment: toolchain.environment)
        }
        gitDirectories = await Self.externalGitDirectories(of: repos)
        watch(repos)
        for repo in repos {
            refresh(repo.id)
        }
    }

    /// The git folders that are not `<repo>/.git` (worktrees), watched on their own.
    @concurrent
    private static func externalGitDirectories(of repos: [GitRepo]) async -> [String: URL] {
        var result: [String: URL] = [:]
        for repo in repos {
            if let directory = GitRepo.gitDirectory(of: repo.url), directory != repo.url.appending(path: ".git") {
                result[repo.id] = directory
            }
        }
        return result
    }

    /// git R4: one subscription per repo, plus one per external git folder; a hidden panel has none.
    private func watch(_ repos: [GitRepo]) {
        for watch in watches {
            watch.cancel()
        }
        let locations = repos.map(\.url) + gitDirectories.values.filter { $0.path().hasPrefix(workspace.root.path()) }
        let directories = gitDirectories
        let root = workspace.root
        watches = locations.map { location in
            Task { [weak self, fsWatch = workspace.fsWatch] in
                for await batch in await fsWatch.changes(under: location) {
                    guard let self else { return }
                    for id in GitModel.reposToRefresh(batch, repos: repos, gitDirectories: directories, root: root)
                        .sorted()
                    {
                        refresh(id)
                    }
                }
            }
        }
    }

    // MARK: - Status (git R4, R5)

    func refresh(_ id: String) {
        guard isActive, coalescer.request(id) else { return }
        Task { [weak self] in
            await self?.runStatus(id)
        }
    }

    private func runStatus(_ id: String) async {
        defer {
            if coalescer.finished(id) {
                refresh(id)
            }
        }
        guard let client = clients[id], let section = model.section(id) else { return }
        model.setLoading(id, true)
        defer { model.setLoading(id, false) }
        do {
            let status = try await Self.loadStatus(client, repo: section.repo)
            model.setStatus(id, status)
            let change = GitStatusChange(repo: section.repo, statuses: status.fileStatuses)
            for continuation in statusSubscribers.values {
                continuation.yield(change)
            }
        } catch {
            logger.error("status failed for \(id, privacy: .public): \(error.description, privacy: .public)")
            model.setError(id, error)
        }
    }

    @concurrent
    private static func loadStatus(_ client: GitCLI, repo: GitRepo) async throws(GitError) -> GitStatus {
        let output = try await client.run(GitCommand.status)
        var status = StatusParser.parse(output.stdout)
        status.operation = GitRepo.gitDirectory(of: repo.url).flatMap { GitOperation.current(inGitDirectory: $0) }
        return status
    }

    // MARK: - Actions (git R7–R9)

    func stage(_ paths: [String], in id: String) {
        write([GitCommand.stage(paths)], in: id)
    }

    func unstage(_ paths: [String], in id: String) {
        guard let status = model.section(id)?.status else { return }
        var isUnborn = false
        if case .unborn = status.head {
            isUnborn = true
        }
        write([GitCommand.unstage(paths, isUnborn: isUnborn)], in: id)
    }

    /// git R8: always confirmed, with the count and the word "irreversible".
    func discard(_ entries: [GitStatusEntry], in id: String) {
        guard !entries.isEmpty, let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText =
            entries.count == 1
            ? "Discard the changes in \u{201c}\(entries[0].path)\u{201d}?"
            : "Discard the changes in \(entries.count) files?"
        alert.informativeText = "This is irreversible: the changes are not in git and cannot be recovered."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.write(GitCommand.discard(entries), in: id)
        }
    }

    /// git R9: the file opens with its markers; `add` marks it resolved.
    func markResolved(_ path: String, in id: String) {
        write([GitCommand.stage([path])], in: id)
    }

    func abort(_ operation: GitOperation, in id: String) {
        write([GitCommand.abort(operation)], in: id)
    }

    func continueOperation(_ operation: GitOperation, in id: String) {
        write([GitCommand.continue(operation)], in: id)
    }

    /// git R7: the file itself, as a preview (explorer R12).
    func open(_ path: String, in id: String) {
        guard let repo = model.section(id)?.repo else { return }
        editor.open(repo.url.appending(path: path), preview: true)
    }

    func toggleCollapsed(_ id: String) {
        model.toggleCollapsed(id)
        workspace.setState("git", to: model.persisted)
    }

    // MARK: - Commit (git R10–R12)

    /// git R12: kept per repo in `state.json` (the write is debounced by `Workspace`).
    func setMessage(_ message: String, in id: String) {
        model.setMessage(id, message)
        workspace.setState("git", to: model.persisted)
    }

    /// git R10: *Amend* prefills an empty message from `HEAD`.
    func setAmending(_ value: Bool, in id: String) {
        model.setAmending(id, value)
        guard value, let client = clients[id], let section = model.section(id), CommitMessage.isEmpty(section.message)
        else { return }
        Task { [weak self] in
            guard let output = try? await client.run(GitCommand.headMessage) else { return }
            self?.setMessage(output.text.trimmingCharacters(in: .whitespacesAndNewlines), in: id)
        }
    }

    /// git R10, R11: `commit -F` through the user's hooks and signature; a failure keeps the
    /// message and shows the output; success clears it.
    func commit(in id: String) {
        guard let client = clients[id], let section = model.section(id), commitTasks[id] == nil,
            CommitMessage.canCommit(
                message: section.message, stagedCount: section.sections.staged.count, amend: section.isAmending)
        else { return }
        let message = section.message
        let amend = section.isAmending
        model.setCommitting(id, true)
        commitTasks[id] = Task { [weak self] in
            defer {
                self?.commitTasks[id] = nil
                self?.model.setCommitting(id, false)
                self?.refresh(id)
            }
            let file = FileManager.default.temporaryDirectory.appending(path: "wraith-commit-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: file) }
            do throws(GitError) {
                do {
                    try Data(message.utf8).write(to: file, options: .atomic)
                } catch {
                    throw .commandFailed("The message could not be written: \(error.localizedDescription)")
                }
                _ = try await client.run(GitCommand.commit(messageFile: file, amend: amend), kind: .write)
                self?.model.setActionError(id, nil)
                self?.model.setAmending(id, false)
                self?.setMessage("", in: id)
            } catch {
                self?.model.setActionError(id, error)
            }
        }
    }

    /// Edge cases: a slow hook is killed (`GitCLI` cancellation → `SIGTERM`).
    func cancelCommit(in id: String) {
        commitTasks[id]?.cancel()
    }

    /// Runs the commands in order, stops at the first failure (shown in the section), then a status.
    private func write(_ commands: [[String]], in id: String) {
        guard let client = clients[id] else { return }
        Task { [weak self] in
            do throws(GitError) {
                for arguments in commands {
                    _ = try await client.run(arguments, kind: .write)
                }
                self?.model.setActionError(id, nil)
            } catch {
                self?.model.setActionError(id, error)
            }
            self?.refresh(id)
        }
    }
}
