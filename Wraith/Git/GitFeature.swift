import AppKit
import Foundation
import SwiftUI
import os

/// Entry point of `git`: the `git.changes` panel, the repos and their `GitCLI`, the status runs
/// and the per-file actions (git R1–R9, R28).
@MainActor
final class GitFeature {
    static let panelID: PanelID = "git.changes"
    static let diffTabKind = "git.diff"
    static let historyPanelID: PanelID = "git.history"

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
    let history = GitHistoryModel()
    private let layout: LayoutManager
    private let workspace: Workspace
    private let editor: EditorFeature
    private let theme: ThemeService
    private let highlighter: Highlighter
    private var diffModels: [TabID: GitDiffModel] = [:]
    private var pinnedDiffs: Set<TabID> = []
    private var isOpeningPreview = false
    private var toolchain: Task<Toolchain?, Never>?
    private var clients: [String: GitCLI] = [:]
    private var gitDirectories: [String: URL] = [:]
    private var coalescer = RefreshCoalescer()
    private var commitTasks: [String: Task<Void, Never>] = [:]
    private var remoteOperations = RemoteOperations()
    /// git R23: the repo whose branch sheet is open.
    var branchSheetRepo: String?
    private(set) var branches: [GitBranch] = []
    private var isActive = false
    private var activation: Task<Void, Never>?
    private var watches: [Task<Void, Never>] = []
    private var configWatch: Task<Void, Never>?
    private var statusSubscribers: [UUID: AsyncStream<GitStatusChange>.Continuation] = [:]
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "git")

    init(
        layout: LayoutManager, workspace: Workspace, editor: EditorFeature, explorer: ExplorerFeature.Registration,
        theme: ThemeService, highlighter: Highlighter
    ) {
        self.layout = layout
        self.workspace = workspace
        self.editor = editor
        self.theme = theme
        self.highlighter = highlighter
        if let state = try? workspace.state.section("git", as: GitState.self) {
            model.restore(state)
        }
        let model = model
        let theme = theme
        layout.register(
            panel: PanelDescriptor(
                id: Self.panelID, title: "Changes", side: .right, icon: "arrow.triangle.branch",
                defaultShortcut: "cmd+shift+g",
                makeView: { [unowned self] in AnyView(GitChangesPanelView(model: model, feature: self, theme: theme)) },
                activate: { [weak self] in self?.activate() },
                deactivate: { [weak self] in self?.deactivate() }))
        let history = history
        layout.register(
            panel: PanelDescriptor(
                id: Self.historyPanelID, title: "History", side: .right, icon: "clock", defaultShortcut: "cmd+shift+h",
                makeView: { [unowned self] in
                    AnyView(GitHistoryPanelView(model: history, changes: model, feature: self, theme: theme))
                },
                activate: { [weak self] in self?.activateHistory() },
                deactivate: { [weak self] in self?.history.reload(with: nil) }))
        // agents R10b: `cmd+e` on a diff tab sends its file, or the sha of a whole commit.
        layout.shortcuts.register(
            ShortcutAction(
                id: "git.sendToAgent", title: "Send to Agent", scope: .tab(kind: Self.diffTabKind),
                defaultShortcut: "cmd+e"
            ) { [weak self] in self?.sendActiveDiffToAgent() })
        explorer.actions.fileHistory = { [weak self] node in
            guard let self, let repo = repoContaining(node.relativePath) else { return }
            showHistory(repo: repo.id, path: Self.path(node.relativePath, in: repo, root: workspace.root))
        }
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: Self.diffTabKind,
                makeView: { [weak self] id, payload in self?.diffView(id, payload: payload) },
                serialize: { [weak self] id in self?.diffModels[id]?.payload.encoded() },
                onClose: { [weak self] id in
                    self?.diffModels[id] = nil
                    self?.pinnedDiffs.remove(id)
                }))
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
            if let output = try? await client.run(GitCommand.stashList) {
                model.setStashes(id, RefParser.stashes(output.stdout))
            }
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

    /// git R28: nothing runs while git is missing or too old.
    var isInert: Bool {
        model.banner != nil
    }

    func toggleStashList(in id: String) {
        model.toggleStashList(id)
    }

    // MARK: - Remote (git R21, R22)

    func fetch(in id: String) {
        remote(.fetch, GitCommand.fetch, in: id)
    }

    func pull(in id: String) {
        remote(.pull, GitCommand.pull, in: id)
    }

    /// git R21: with no upstream, a confirmation naming the remote, then `push -u origin <branch>`.
    func push(in id: String) {
        guard let status = model.section(id)?.status, case .branch(let branch) = status.head else { return }
        if status.upstream != nil {
            remote(.push, GitCommand.push(branch: branch, hasUpstream: true), in: id)
            return
        }
        confirm(
            "Push \u{201c}\(branch)\u{201d} to origin?",
            "The branch has no upstream yet; origin/\(branch) is created and tracked.", "Push"
        ) {
            [weak self] in self?.remote(.push, GitCommand.push(branch: branch, hasUpstream: false), in: id)
        }
    }

    /// git R21, R22: one at a time per repo; an interaction git could not have → the banner.
    private func remote(_ kind: RemoteOperations.Kind, _ arguments: [String], in id: String) {
        guard let client = clients[id], let repo = model.section(id)?.repo, remoteOperations.start(kind, in: id)
        else { return }
        model.setRemoteOperation(id, kind)
        Task { [weak self] in
            defer {
                self?.remoteOperations.finish(id)
                self?.model.setRemoteOperation(id, nil)
                self?.refresh(id)
            }
            do throws(GitError) {
                _ = try await client.run(arguments, kind: .remote)
                self?.model.setActionError(id, nil)
                self?.model.setAuthRequired(id, nil)
            } catch .needsInteraction {
                self?.model.setAuthRequired(id, GitAuthRequired(arguments: arguments, cwd: repo.url))
            } catch {
                self?.model.setActionError(id, error)
            }
        }
    }

    // MARK: - Branches (git R23)

    /// git R23: the sheet, with the list loaded fresh.
    func showBranches(in id: String) {
        guard let client = clients[id] else { return }
        branches = []
        branchSheetRepo = id
        Task { [weak self] in
            guard let output = try? await client.run(GitCommand.branches) else { return }
            self?.branches = RefParser.branches(output.stdout)
        }
    }

    func checkout(_ branch: GitBranch, in id: String) {
        branchSheetRepo = nil
        write([GitCommand.checkout(branch)], in: id)
    }

    func newBranch(in id: String) {
        branchSheetRepo = nil
        askText("New Branch from HEAD", placeholder: "branch-name") { [weak self] name in
            self?.write([GitCommand.newBranch(name)], in: id)
        }
    }

    func renameBranch(_ branch: GitBranch, in id: String) {
        branchSheetRepo = nil
        askText("Rename \u{201c}\(branch.name)\u{201d}", placeholder: branch.name, button: "Rename") {
            [weak self] name in
            self?.write([GitCommand.renameBranch(branch.name, to: name)], in: id)
        }
    }

    /// git R23: `-d`; when git refuses (not merged), `-D` is offered with the name.
    func deleteBranch(_ branch: GitBranch, in id: String) {
        branchSheetRepo = nil
        guard let client = clients[id] else { return }
        Task { [weak self] in
            do throws(GitError) {
                _ = try await client.run(GitCommand.deleteBranch(branch.name, force: false), kind: .write)
                self?.model.setActionError(id, nil)
                self?.refresh(id)
            } catch {
                self?.confirm(
                    "Force-delete \u{201c}\(branch.name)\u{201d}?", "git refused: \(error.description)", "Delete Anyway"
                ) { self?.write([GitCommand.deleteBranch(branch.name, force: true)], in: id) }
            }
        }
    }

    func setUpstream(of branch: GitBranch, in id: String) {
        branchSheetRepo = nil
        askText("Upstream of \u{201c}\(branch.name)\u{201d}", placeholder: "origin/\(branch.name)", button: "Set") {
            [weak self] upstream in self?.write([GitCommand.setUpstream(of: branch.name, to: upstream)], in: id)
        }
    }

    // MARK: - Stash (git R24)

    func stash(includeUntracked: Bool, in id: String) {
        askText(
            includeUntracked ? "Stash Including Untracked" : "Stash", placeholder: "message (optional)",
            button: "Stash", allowsEmpty: true
        ) {
            [weak self] message in
            self?.write([GitCommand.stashPush(message: message, includeUntracked: includeUntracked)], in: id)
        }
    }

    func stash(_ action: GitCommand.StashAction, _ stash: GitStash, in id: String) {
        guard action == .drop else {
            write([GitCommand.stash(action, stash.ref)], in: id)
            return
        }
        confirm("Drop \(stash.ref)?", stash.message, "Drop") { [weak self] in
            self?.write([GitCommand.stash(.drop, stash.ref)], in: id)
        }
    }

    // MARK: - History (git R18–R20)

    /// git R18: the repo of the changes panel by default; the repos come from the same discovery.
    private func activateHistory() {
        Task { [weak self] in
            guard let self else { return }
            if model.sections.isEmpty {
                await discoverAndRefresh()
            }
            if history.repoID == nil || model.section(history.repoID ?? "") == nil {
                history.repoID = model.sections.first { !$0.sections.isEmpty }?.id ?? model.sections.first?.id
            }
            guard let id = history.repoID else { return }
            history.reload(with: await client(for: id))
        }
    }

    /// git R18, R20: shows the panel on `repo`, on one file when `path` is set.
    func showHistory(repo: String, path: String?) {
        history.repoID = repo
        history.query.path = path
        history.selection = []
        if !layout.panels.isVisible(Self.historyPanelID) {
            layout.panels.show(Self.historyPanelID)
        }
        Task { [weak self] in
            guard let self else { return }
            history.reload(with: await client(for: repo))
        }
    }

    func filterHistory(_ text: String) {
        history.query.filter = text.trimmingCharacters(in: .whitespaces)
        guard let repo = history.repoID else { return }
        Task { [weak self] in
            guard let self else { return }
            history.reload(with: await client(for: repo))
        }
    }

    func loadMoreHistory() {
        guard let repo = history.repoID else { return }
        Task { [weak self] in
            guard let self else { return }
            history.loadMore(with: await client(for: repo))
        }
    }

    /// git R19: the commit's diff, a preview on a click, pinned on a double click.
    func openCommitDiff(_ commit: GitCommit, preview: Bool) {
        guard let repo = history.repoID else { return }
        let source: GitDiffPayload.Source =
            history.query.path.map { .commitFile(sha: commit.sha, subject: commit.subject, path: $0) }
            ?? .commit(sha: commit.sha, subject: commit.subject)
        openDiff(GitDiffPayload(repo: repo, source: source), preview: preview)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// git R19: confirmed; the reflog keeps everything.
    func checkout(_ commit: GitCommit) {
        confirm(
            "Check out \(commit.shortSha)?", "HEAD becomes detached; the current branch is left as it is.", "Checkout"
        ) {
            [weak self] in self?.runInHistoryRepo([GitCommand.checkoutDetached(commit.sha)])
        }
    }

    func createBranch(at commit: GitCommit) {
        askText("New Branch at \(commit.shortSha)", placeholder: "branch-name") { [weak self] name in
            self?.runInHistoryRepo([GitCommand.createBranch(name, at: commit.sha)])
        }
    }

    func cherryPick(_ commit: GitCommit) {
        confirm("Cherry-pick \(commit.shortSha)?", commit.subject, "Cherry-pick") { [weak self] in
            self?.runInHistoryRepo([GitCommand.cherryPick(commit.sha)])
        }
    }

    func revert(_ commit: GitCommit) {
        confirm(
            "Revert \(commit.shortSha)?", "A new commit undoing \u{201c}\(commit.subject)\u{201d} is created.", "Revert"
        ) {
            [weak self] in self?.runInHistoryRepo([GitCommand.revert(commit.sha)])
        }
    }

    func reset(to commit: GitCommit, mode: GitCommand.ResetMode) {
        confirm(
            "Reset \(mode == .soft ? "soft" : "mixed") to \(commit.shortSha)?",
            mode == .soft ? "The later commits become staged changes." : "The later commits become unstaged changes.",
            "Reset"
        ) { [weak self] in self?.runInHistoryRepo([GitCommand.reset(to: commit.sha, mode: mode)]) }
    }

    private func runInHistoryRepo(_ commands: [[String]]) {
        guard let repo = history.repoID else { return }
        Task { [weak self] in
            guard let self, let client = await client(for: repo) else { return }
            do throws(GitError) {
                for arguments in commands {
                    _ = try await client.run(arguments, kind: .write)
                }
                model.setActionError(repo, nil)
            } catch {
                model.setActionError(repo, error)
            }
            refresh(repo)
            history.reload(with: client)
        }
    }

    private func confirm(_ title: String, _ text: String, _ button: String, _ done: @escaping () -> Void) {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            done()
        }
    }

    private func askText(
        _ title: String, placeholder: String, button: String = "Create", allowsEmpty: Bool = false,
        _ done: @escaping (String) -> Void
    ) {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, allowsEmpty || !text.isEmpty else { return }
            done(text)
        }
    }

    /// The deepest repo whose folder contains `relativePath` (relative to the workspace root).
    private func repoContaining(_ relativePath: String) -> GitRepo? {
        model.sections.map(\.repo).filter {
            $0.id == "." || relativePath == $0.id || relativePath.hasPrefix($0.id + "/")
        }
        .max { $0.id.count < $1.id.count }
    }

    /// `relativePath` (to the root) as git wants it: relative to the repo.
    nonisolated static func path(_ relativePath: String, in repo: GitRepo, root: URL) -> String {
        Workspace.persistedPath(for: root.appending(path: relativePath), root: repo.url)
    }

    private func client(for id: String) async -> GitCLI? {
        guard let repo = model.section(id)?.repo else { return clients[id] }
        return await client(for: repo)
    }

    // MARK: - Diff tabs (git R13, R14, R17; layout R28)

    /// git R13: a preview replaced by the next one in its group, pinned on a double click
    /// (explorer R12 by analogy); the same diff already open is activated instead.
    func openDiff(_ payload: GitDiffPayload, preview: Bool) {
        let group = layout.model.activeGroup
        if let existing = layout.model.active.tabs.first(where: { diffModels[$0.id]?.payload == payload }) {
            if !preview {
                pinDiff(existing.id)
            }
            layout.activate(existing.id, in: group)
            return
        }
        let replaced =
            preview
            ? layout.model.active.tabs.first { diffModels[$0.id] != nil && !pinnedDiffs.contains($0.id) } : nil
        isOpeningPreview = preview
        defer { isOpeningPreview = false }
        guard
            layout.openTab(kind: Self.diffTabKind, title: payload.title, payload: payload.encoded(), isPreview: preview)
                != nil
        else { return }
        if let replaced {
            Task { await layout.closeTab(replaced.id) }
        }
    }

    /// agents R10b, R10d: set by `Agents/` once it exists.
    var sendToAgent: ((AgentMention) -> Void)?

    private func sendActiveDiffToAgent() {
        guard let id = layout.model.active.active?.id, let payload = diffModels[id]?.payload, let sendToAgent else {
            return
        }
        switch payload.source {
        case .commit(let sha, _):
            sendToAgent(.literal(String(sha.prefix(7))))
        case .workingTree(let path), .staged(let path), .commitFile(_, _, let path):
            sendToAgent(.path(fileURL(path, in: payload.repo), lines: nil, isDirectory: false))
        case .session:
            // No single path: the lines have their own menu.
            break
        }
    }

    /// agents R10b: one line of a diff, from its context menu.
    func sendLineToAgent(path: String, line: Int, in repo: String) {
        sendToAgent?(.path(fileURL(path, in: repo), lines: line...line, isDirectory: false))
    }

    /// A repo-relative path as an absolute URL; the root when the repo is not known any more.
    private func fileURL(_ path: String, in repo: String) -> URL {
        (model.section(repo)?.repo.url ?? workspace.root).appending(path: path)
    }

    func pinDiff(_ id: TabID) {
        guard let model = diffModels[id], !pinnedDiffs.contains(id) else { return }
        pinnedDiffs.insert(id)
        layout.update(id, title: model.payload.title, isDirty: false, isPreview: false)
    }

    /// The tab's view, or `nil` when the payload cannot be restored (layout R28).
    ///
    /// A restored tab is pinned; the client comes lazily, once the toolchain is resolved.
    private func diffView(_ id: TabID, payload: String) -> AnyView? {
        guard let decoded = GitDiffPayload.decode(payload) else { return nil }
        let repo =
            model.section(decoded.repo)?.repo
            ?? GitRepo(
                id: decoded.repo,
                url: Workspace.url(forPersistedPath: decoded.repo == "." ? "" : decoded.repo, root: workspace.root))
        let diffModel = GitDiffModel(
            payload: decoded, client: { [weak self] in await self?.client(for: repo) }, repo: repo,
            highlighter: highlighter, theme: theme, statusChanges: decoded.source.isImmutable ? nil : statusChanges())
        diffModels[id] = diffModel
        if !isOpeningPreview {
            pinnedDiffs.insert(id)
        }
        return AnyView(
            GitDiffView(
                model: diffModel, theme: theme,
                sendLine: { [weak self] path, line in
                    self?.sendLineToAgent(path: path, line: line, in: diffModel.payload.repo)
                }))
    }

    // MARK: - Session diff (git R30–R32)

    /// git R30: the snapshot of the repo containing `cwd`; `nil` outside any repo or without git.
    func snapshot(for cwd: URL) async -> (repo: String, tree: String)? {
        guard let repo = await repo(containing: cwd), let client = await client(for: repo) else { return nil }
        do {
            return (repo.id, try await client.snapshotTree())
        } catch {
            logger.error("snapshot failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// git R31a: the session diff tab, reused when already open.
    func openSessionDiff(repo: String, base: String, title: String) {
        openDiff(GitDiffPayload(repo: repo, source: .session(base: base, title: title)), preview: false)
    }

    /// The known repo `cwd` is under (the deepest), the discovery when the panel never ran, or
    /// `cwd` itself when it has a `.git` entry (a worktree, agents R12).
    private func repo(containing cwd: URL) async -> GitRepo? {
        let path = cwd.standardizedFileURL.path(percentEncoded: false)
        func deepest(_ repos: [GitRepo]) -> GitRepo? {
            repos.filter {
                path == $0.url.path(percentEncoded: false) || path.hasPrefix($0.url.path(percentEncoded: false) + "/")
            }
            .max { $0.url.path().count < $1.url.path().count }
        }
        if let repo = deepest(model.sections.map(\.repo)) { return repo }
        if let repo = deepest(await GitRepo.discover(root: workspace.root, declared: workspace.config.repos)) {
            return repo
        }
        return GitRepo.hasGitEntry(cwd) ? GitRepo(url: cwd, root: workspace.root) : nil
    }

    /// The repo's `GitCLI`, created on demand for a tab restored before the panel ran (git R26).
    private func client(for repo: GitRepo) async -> GitCLI? {
        if let client = clients[repo.id] {
            return client
        }
        guard let toolchain = await resolveToolchain() else { return nil }
        let client = GitCLI(executable: toolchain.executable, repo: repo.url, loginEnvironment: toolchain.environment)
        clients[repo.id] = client
        return client
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
