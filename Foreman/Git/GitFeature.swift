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

    /// The `git` section of `.foreman/config.json` (git R26).
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

    /// The panels the git panels' headers list as tabs (design R17).
    var panels: PanelManager {
        layout.panels
    }
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
    /// git R35: each top-level repo's common git folder, whose `worktrees/` lists its worktrees.
    private var commonDirectories: [String: URL] = [:]
    /// git R35: the folders outside the root (worktrees, their git folders), on a stream of their own.
    private var externalWatch: FSWatchService?
    private var externalRoots: [URL] = []
    private var rediscovery: Task<Void, Never>?
    /// agents R5b: a working copy to reveal once the discovery answers.
    private var pendingReveal: URL?
    private var coalescer = RefreshCoalescer()
    private var commitTasks: [String: Task<Void, Never>] = [:]
    private var remoteOperations = RemoteOperations()
    private var isActive = false
    private var activation: Task<Void, Never>?
    private var arePanelsShown = false
    private var presence: Task<Void, Never>?
    private var watches: [Task<Void, Never>] = []
    private var configWatch: Task<Void, Never>?
    private var statusSubscribers: [UUID: AsyncStream<GitStatusChange>.Continuation] = [:]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "git")

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
        // git R1b: the panels exist only with a repo; the root or `config.repos` answers at once,
        // the depth-2 scan answers off the main actor. A root excluded by a `!` entry does not
        // answer for itself: `checkPresence` decides.
        let root = workspace.root.standardizedFileURL
        let rootIgnored = workspace.config.ignoredRepos.contains { $0.standardizedFileURL == root }
        showPanels(!workspace.config.repos.isEmpty || (GitRepo.hasGitEntry(workspace.root) && !rootIgnored))
        presence = Task { [weak self] in await self?.checkPresence() }
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
                },
                // layout (status bar, 2026-10-16): the lines the diff adds and removes.
                statusItems: { [weak self] id in
                    guard let stats = self?.diffModels[id]?.diff?.lineStats else { return [] }
                    return [StatusItem(id: "git.diff.stats", text: "+\(stats.added) \u{2212}\(stats.removed)")]
                }))
        configWatch = Task { [weak self, workspace] in
            for await _ in workspace.configChanges() {
                guard let self else { return }
                await checkPresence()
                guard isActive else { continue }
                // git R1: the repos follow `config.repos`; a new `git.path` waits for the next window.
                await discoverAndRefresh()
            }
        }
    }

    // MARK: - Presence (git R1b, layout R36)

    private func checkPresence() async {
        let repos = await GitRepo.discover(
            root: workspace.root, declared: workspace.config.repos, ignored: workspace.config.ignoredRepos)
        guard !Task.isCancelled else { return }
        showPanels(!repos.isEmpty)
    }

    private func showPanels(_ shown: Bool) {
        guard shown != arePanelsShown else { return }
        arePanelsShown = shown
        guard shown else {
            layout.unregister(panel: Self.panelID)
            layout.unregister(panel: Self.historyPanelID)
            layout.removeToolbarItem(Self.branchWidgetID)
            deactivate()
            return
        }
        // git (surfaces, amended 2026-10-16): the status is followed while the window has a repo,
        // not only while Changes is shown — the Changes tab counts the files, History may be shown
        // alone in its own slot, and the toolbar names the branch (`architecture` P4, an exception).
        activate()
        let model = model
        let theme = theme
        registerBranchWidget()
        layout.register(
            panel: PanelDescriptor(
                // git (surfaces, amended 2026-10-16): Changes is the left slot's second tab.
                id: Self.panelID, title: "Changes", side: .left, icon: "arrow.triangle.branch", order: 1,
                badge: { model.changedFileCount > 0 ? .count(model.changedFileCount, .orange) : .none },
                defaultShortcut: "cmd+shift+g",
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(GitChangesPanelView(model: model, feature: self, theme: theme))
                }))
        let history = history
        layout.register(
            panel: PanelDescriptor(
                // git (surfaces, amended 2026-10-16): History is the bottom slot's first tab.
                id: Self.historyPanelID, title: "History", side: .bottom, icon: "clock", order: 0,
                defaultShortcut: "cmd+shift+h",
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(GitHistoryPanelView(model: history, changes: model, feature: self, theme: theme))
                },
                activate: { [weak self] in self?.activateHistory() },
                deactivate: { [weak self] in self?.history.reload(with: nil) }))
    }

    // MARK: - Worktrees from the branch menu (git R41, M22 22.2)

    /// The agents a worktree can be opened in, and how to open one in a folder; set by the window
    /// (architecture: features call each other through closures, agents R5).
    var agents: (() -> [GitBranchMenu.Agent])?
    var launchAgent: ((String, URL) -> Void)?

    /// git R41: a branch name asked for, a new branch from `HEAD` checked out in a worktree beside
    /// the repo (`<repo>-wt/<branch>`).
    func newWorktree(in id: String) {
        guard let repo = model.section(id)?.repo else { return }
        askText("New Worktree of \u{201c}\(repo.name)\u{201d}", placeholder: "branch-name") { [weak self] branch in
            let folder = GitBranchMenu.worktreeFolder(repo: repo.url, branch: branch)
            Task {
                do throws(GitError) {
                    try await self?.addWorktree(in: repo.url, folder: folder, branch: branch)
                    self?.model.setActionError(id, nil)
                } catch {
                    self?.model.setActionError(id, error)
                }
                await self?.discoverAndRefresh()
            }
        }
    }

    /// git R41: the worktree's branch merged into the main folder, confirmed; refused while the
    /// main folder holds tracked changes.
    func mergeIntoMain(_ id: String) {
        guard let section = model.section(id), let parentID = section.repo.parent, let parent = model.section(parentID),
            case .branch(let branch) = section.status?.head
        else { return }
        let base = parent.status.map(GitRepoSectionView.headText) ?? parent.repo.name
        guard GitBranchMenu.canMerge(into: parent.status) else {
            model.setActionError(
                parentID,
                .commandFailed(
                    "\(parent.repo.name) has uncommitted changes: commit or stash them before merging \(branch)."))
            layout.panels.show(Self.panelID)
            showChanges(of: parentID)
            return
        }
        confirm(
            "Merge \u{201c}\(branch)\u{201d} into \u{201c}\(base)\u{201d}?",
            "git merge --no-ff \(branch), in \(parent.repo.url.path(percentEncoded: false)). A conflict stops the merge "
                + "and shows in Changes.",
            "Merge"
        ) { [weak self] in
            self?.write([GitCommand.merge(branch)], in: parentID)
        }
    }

    // MARK: - Branch widget (git, branch menu, M21 21.3–21.4)

    static let branchWidgetID = "git.branch"

    /// layout R30 (amended 2026-10-16): after the project, the branch of the working copy last
    /// worked in (git R10) and how many worktrees its repo has.
    private func registerBranchWidget() {
        let model = model
        let theme = theme
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: Self.branchWidgetID, title: "Branch", icon: "arrow.triangle.branch", placement: .leading,
                kind: .widget(
                    view: { openMenu in AnyView(GitBranchWidget(model: model, theme: theme, openMenu: openMenu)) },
                    menu: { [weak self] in self?.branchMenu() ?? ToolbarMenu(entries: []) })))
    }

    /// git R40: worktrees, branches and the remote actions of every repo, with a filter field.
    private func branchMenu() -> ToolbarMenu {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = model.commitTarget?.id
        let repos = model.groups.map { group in
            GitBranchMenu.Repo(
                id: group.top.id, name: group.top.repo.name,
                main: menuCopy(group.top, top: nil, target: target, home: home),
                worktrees: group.children.map { menuCopy($0, top: group.top.repo.url, target: target, home: home) },
                branches: model.refs[group.top.id] ?? [])
        }
        var actions = GitBranchMenu.Actions()
        actions.showChanges = { [weak self] id in
            self?.layout.panels.show(Self.panelID)
            self?.showChanges(of: id)
        }
        actions.compare = { [weak self] id in
            guard let self else { return }
            if let base = defaultCompareBase(for: id) {
                compare(id, with: base)
            } else {
                chooseCompareBase(id)
            }
        }
        actions.checkOutInMain = { [weak self] in self?.checkOutHere($0) }
        actions.reveal = { [weak self] id in
            guard let url = self?.model.section(id)?.repo.url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        actions.removeWorktree = { [weak self] in self?.removeWorktree($0) }
        actions.checkout = { [weak self] branch, id in self?.checkout(branch, in: id) }
        actions.fetch = { [weak self] in self?.fetch(in: $0) }
        actions.pull = { [weak self] in self?.pull(in: $0) }
        actions.push = { [weak self] in self?.push(in: $0) }
        actions.newBranch = { [weak self] in self?.newBranch(in: $0) }
        actions.stash = { [weak self] in self?.stash(includeUntracked: false, in: $0) }
        actions.newWorktree = { [weak self] in self?.newWorktree(in: $0) }
        actions.merge = { [weak self] in self?.mergeIntoMain($0) }
        actions.openAgent = { [weak self] agent, id in
            guard let url = self?.model.section(id)?.repo.url else { return }
            self?.launchAgent?(agent, url)
        }
        return ToolbarMenu(
            entries: GitBranchMenu.entries(
                repos, agents: agents?() ?? [], compareBase: { [weak self] in self?.defaultCompareBase(for: $0) },
                actions: actions),
            filter: "Filter branches and worktrees")
    }

    private func menuCopy(_ section: GitModel.Section, top: URL?, target: String?, home: URL) -> GitBranchMenu.Copy {
        let sessions = model.agentSessions(in: section.id)
        let badge: ToolbarBadge =
            sessions.contains(where: \.isMarked)
            ? .dot(.orange) : sessions.contains(where: \.isRunning) ? .dot(.green) : .none
        return GitBranchMenu.Copy(
            id: section.id, head: section.status.map(GitRepoSectionView.headText) ?? section.repo.name,
            path: GitBranchMenu.displayPath(section.repo.url, relativeTo: top, home: home),
            ahead: section.status?.ahead ?? 0, agents: sessions.map(\.title), agentBadge: badge,
            isCurrent: section.id == target, isLocked: section.repo.lockReason != nil)
    }

    isolated deinit {
        activation?.cancel()
        presence?.cancel()
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
                        "git \(version.major).\(version.minor).\(version.patch) found; \(GitVersion.minimum.major).\(GitVersion.minimum.minor) or newer is required."
                    )
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
        let found = await GitRepo.discover(
            root: workspace.root, declared: workspace.config.repos, ignored: workspace.config.ignoredRepos)
        guard isActive, !Task.isCancelled else {
            model.setDiscovering(false)
            return
        }
        for repo in found where clients[repo.id] == nil {
            clients[repo.id] = GitCLI(
                executable: toolchain.executable, repo: repo.url, loginEnvironment: toolchain.environment)
        }
        // git R33, R33a: every repo's worktrees become its children.
        let lists = await Self.worktreeLists(of: found, clients: clients)
        guard isActive, !Task.isCancelled else {
            model.setDiscovering(false)
            return
        }
        let repos = GitRepo.arrange(found, worktrees: lists, root: workspace.root)
        model.setRepos(repos)
        model.setDiscovering(false)
        for repo in repos where clients[repo.id] == nil {
            clients[repo.id] = GitCLI(
                executable: toolchain.executable, repo: repo.url, loginEnvironment: toolchain.environment)
        }
        // git R1: a repo that left `config.repos` or the disk leaves its client behind. A diff tab
        // still open on one keeps it, since the instance is what serialises that repo's writes
        // (decision 2026-08-27); anything else is created again on demand.
        let kept = Set(repos.map(\.id)).union(diffModels.values.map(\.payload.repo))
        clients = clients.filter { kept.contains($0.key) }
        gitDirectories = await Self.externalGitDirectories(of: repos)
        commonDirectories = await Self.commonDirectories(of: repos.filter { $0.parent == nil })
        watch(repos)
        for repo in repos {
            refresh(repo.id)
        }
        if let cwd = pendingReveal {
            pendingReveal = nil
            reveal(cwd)
        }
    }

    /// git R33: `worktree list` of each repo, in parallel; a failure reads as no worktree.
    @concurrent
    private static func worktreeLists(of repos: [GitRepo], clients: [String: GitCLI]) async -> [String: [GitWorktree]] {
        await withTaskGroup(of: (String, [GitWorktree]).self) { group in
            for repo in repos {
                guard let client = clients[repo.id] else { continue }
                group.addTask {
                    let output = try? await client.run(WorktreeParser.arguments)
                    return (repo.id, output.map { WorktreeParser.parse($0.stdout) } ?? [])
                }
            }
            var result: [String: [GitWorktree]] = [:]
            for await (id, list) in group {
                result[id] = list
            }
            return result
        }
    }

    @concurrent
    private static func commonDirectories(of repos: [GitRepo]) async -> [String: URL] {
        var result: [String: URL] = [:]
        for repo in repos {
            result[repo.id] = GitRepo.commonDirectory(of: repo.url)
        }
        return result
    }

    /// git R35: a worktree added, removed or locked elsewhere (terminal, agent) changes the
    /// sections without a relaunch; one discovery at a time.
    private func rediscover() {
        guard isActive, rediscovery == nil else { return }
        rediscovery = Task { [weak self] in
            await self?.discoverAndRefresh()
            self?.rediscovery = nil
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

    /// git R4, R35: one subscription per watched folder; a hidden panel has none.
    ///
    /// The repos, the git folders that live outside their repo (worktrees) and each common
    /// folder's `worktrees/`; what lies outside the root goes through a stream of its own.
    private func watch(_ repos: [GitRepo]) {
        for watch in watches {
            watch.cancel()
        }
        let root = workspace.root
        let locations =
            repos.map(\.url) + Array(gitDirectories.values)
            + commonDirectories.values.map { $0.appending(path: "worktrees") }
        let isInside = { (url: URL) in Workspace.contains(url, under: root) }
        let outside = locations.filter { !isInside($0) }
        if outside.map(GitRepo.canonicalPath) != externalRoots.map(GitRepo.canonicalPath) {
            externalRoots = outside
            externalWatch = outside.isEmpty ? nil : FSWatchService(roots: outside)
        }
        let directories = gitDirectories
        let commons = commonDirectories
        watches = locations.compactMap { location in
            guard let service = isInside(location) ? workspace.fsWatch : externalWatch else { return nil }
            return Task { [weak self] in
                for await batch in await service.changes(under: location) {
                    guard let self else { return }
                    if !GitModel.reposToRediscover(batch, commonDirectories: commons).isEmpty {
                        rediscover()
                    }
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
            // git R40: the branch menu opens on what was read last, without waiting for git.
            if section.repo.parent == nil, let output = try? await client.run(GitCommand.branches) {
                model.setRefs(id, RefParser.branches(output.stdout))
            }
            let change = GitStatusChange(repo: section.repo, statuses: status.fileStatuses)
            for continuation in statusSubscribers.values {
                continuation.yield(change)
            }
        } catch {
            logger.error("status failed for \(id, privacy: .public): \(error.description, privacy: .public)")
            model.setError(id, error)
            // git R33, edge cases: a worktree folder deleted by hand leaves at the next read.
            if section.repo.parent != nil,
                !FileManager.default.fileExists(atPath: section.repo.url.path(percentEncoded: false))
            {
                rediscover()
            }
        }
    }

    @concurrent
    private static func loadStatus(_ client: GitCLI, repo: GitRepo) async throws(GitError) -> GitStatus {
        let output = try await client.run(GitCommand.status)
        var status = StatusParser.parse(output.stdout)
        status.operation = GitRepo.gitDirectory(of: repo.url).flatMap { GitOperation.current(inGitDirectory: $0) }
        return status
    }

    /// git R1b: the panels exist, so there is a repo to show.
    var hasPanels: Bool {
        arePanelsShown
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
                // The refs are shared: a fetch or a pull moves every worktree's ↑n ↓m (R34).
                for child in self?.model.children(of: id) ?? [] {
                    self?.refresh(child.id)
                }
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
        model.setBranchSheet(id)
        Task { [weak self] in
            let output = try? await client.run(GitCommand.branches)
            // The sheet may have been closed, or reopened on another repo, while git ran.
            guard let self, model.branchSheetRepo == id else { return }
            model.setBranches(output.map { RefParser.branches($0.stdout) } ?? [])
        }
    }

    func closeBranchSheet() {
        model.setBranchSheet(nil)
    }

    func checkout(_ branch: GitBranch, in id: String) {
        model.setBranchSheet(nil)
        write([GitCommand.checkout(branch)], in: id)
    }

    func newBranch(in id: String) {
        model.setBranchSheet(nil)
        askText("New Branch from HEAD", placeholder: "branch-name") { [weak self] name in
            self?.write([GitCommand.newBranch(name)], in: id)
        }
    }

    func renameBranch(_ branch: GitBranch, in id: String) {
        model.setBranchSheet(nil)
        askText("Rename \u{201c}\(branch.name)\u{201d}", placeholder: branch.name, button: "Rename") {
            [weak self] name in
            self?.write([GitCommand.renameBranch(branch.name, to: name)], in: id)
        }
    }

    /// git R23: `-d`; when git refuses (not merged), `-D` is offered with the name.
    func deleteBranch(_ branch: GitBranch, in id: String) {
        model.setBranchSheet(nil)
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
        model.setBranchSheet(nil)
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
        history.query.range = nil
        history.selection = []
        if !layout.panels.isVisible(Self.historyPanelID) {
            layout.panels.show(Self.historyPanelID)
        }
        Task { [weak self] in
            guard let self else { return }
            history.reload(with: await client(for: repo))
        }
    }

    /// git R18 (amended 2026-10-16): *All branches* or the current branch's line.
    func setHistoryAllBranches(_ value: Bool) {
        guard history.query.allBranches != value else { return }
        history.query.allBranches = value
        guard let repo = history.repoID else { return }
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

    /// git R19b: a click on a commit lists its files under the log.
    func selectCommit(_ commit: GitCommit?) {
        guard let repo = history.repoID else { return }
        Task { [weak self] in
            guard let self else { return }
            history.showFiles(of: commit, with: await client(for: repo))
        }
    }

    /// git R19b: one file of the selected commit, a preview on a click, pinned on a double click.
    func openCommitFileDiff(_ commit: GitCommit, path: String, preview: Bool) {
        guard let repo = history.repoID else { return }
        openDiff(
            GitDiffPayload(repo: repo, source: .commitFile(sha: commit.sha, subject: commit.subject, path: path)),
            preview: preview)
    }

    /// git R19: the commit's whole diff, pinned (a double click on the commit).
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            done()
        }
    }

    private func askText(
        _ title: String, placeholder: String, button: String = "Create", allowsEmpty: Bool = false,
        _ done: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { response in
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, allowsEmpty || !text.isEmpty else { return }
            done(text)
        }
    }

    /// The alert as a sheet of the window the panels live in, which is not always the key one when
    /// several workspaces are open; with no window at all it is run modally, never dropped.
    private func present(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = layout.window ?? NSApp.keyWindow else {
            done(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window) { response in
            done(response)
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
        case .session, .range:
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
        let repo: GitRepo
        if let known = model.section(decoded.repo)?.repo {
            repo = known
        } else if let url = Workspace.url(
            forPersistedPath: decoded.repo == "." ? "" : decoded.repo, root: workspace.root)
        {
            repo = GitRepo(id: decoded.repo, url: url)
        } else {
            return nil
        }
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

    /// agents R12: a new branch and its worktree, through the repo at `repoURL` (git R26).
    func addWorktree(in repoURL: URL, folder: URL, branch: String) async throws(GitError) {
        guard let client = await client(for: GitRepo(url: repoURL, root: workspace.root)) else { throw .gitNotFound }
        _ = try await client.run(
            ["worktree", "add", "-b", branch, folder.path(percentEncoded: false), "HEAD"], kind: .write)
    }

    /// agents R13, git R37–R38: the worktree folder removed and forgotten by git, the branch kept.
    ///
    /// Without `force`, git refuses a worktree holding modified or untracked files.
    func removeWorktree(in repoURL: URL, folder: URL, force: Bool) async throws(GitError) {
        guard let client = await client(for: GitRepo(url: repoURL, root: workspace.root)) else { throw .gitNotFound }
        _ = try await client.run(GitCommand.removeWorktree(folder, force: force), kind: .write)
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
        if let repo = deepest(
            await GitRepo.discover(
                root: workspace.root, declared: workspace.config.repos, ignored: workspace.config.ignoredRepos))
        {
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

    // MARK: - Worktrees (git R34c, R36–R39)

    /// git R34c: set by `Agents/`, like `sendToAgent`.
    var activateAgentTab: ((TabID) -> Void)?

    /// git R34c: the agent tabs of the window, each matched to the working copy it runs in.
    func setAgentSessions(_ sessions: [GitAgentSession]) {
        model.setAgentSessions(sessions)
    }

    /// agents R5b: the panel shown, the working copy holding `cwd` opened and scrolled to; when the
    /// discovery has not answered yet, once it does.
    func showInChanges(cwd: URL) {
        if !layout.panels.isVisible(Self.panelID) {
            layout.panels.show(Self.panelID)
        }
        guard !model.sections.isEmpty else {
            pendingReveal = cwd
            return
        }
        reveal(cwd)
    }

    private func reveal(_ cwd: URL) {
        guard let id = GitModel.owner(of: cwd, among: model.sections.map(\.repo)) else { return }
        model.reveal(id)
        workspace.setState("git", to: model.persisted)
    }

    /// git R36: *Show Changes* from the branch list.
    func showChanges(of id: String) {
        model.setBranchSheet(nil)
        model.reveal(id)
        workspace.setState("git", to: model.persisted)
    }

    /// git R36: the section holding `branch` in another working copy of the same repo, if any.
    func holder(of branch: GitBranch, besides id: String) -> GitModel.Section? {
        guard let path = branch.worktreePath, let section = model.section(id) else { return nil }
        let group = section.repo.parent ?? section.id
        return model.sections.first {
            ($0.id == group || $0.repo.parent == group) && $0.id != id
                && GitRepo.canonicalPath($0.repo.url) == GitRepo.canonicalPath(URL(filePath: path))
        }
    }

    /// git R37: the worktree removed without `--force` (git refuses a dirty one, nothing else
    /// happens), then its branch checked out in the parent.
    func checkOutHere(_ id: String) {
        model.setBranchSheet(nil)
        guard let section = model.section(id), let parent = section.repo.parent, let client = clients[parent],
            case .branch(let branch) = section.status?.head
        else { return }
        Task { [weak self] in
            do throws(GitError) {
                _ = try await client.run(GitCommand.removeWorktree(section.repo.url, force: false), kind: .write)
            } catch {
                self?.model.setActionError(parent, error)
                return
            }
            do throws(GitError) {
                _ = try await client.run(GitCommand.checkout(GitBranch(local: branch)), kind: .write)
                self?.model.setActionError(parent, nil)
            } catch {
                self?.model.setActionError(
                    parent,
                    .commandFailed(
                        "The worktree was removed (it was clean) and \u{201c}\(branch)\u{201d} is intact, but the "
                            + "checkout was refused: \(error.description)"))
            }
            await self?.discoverAndRefresh()
        }
    }

    /// git R38: confirmed with the folder and the branch; without `--force`; the branch is kept.
    func removeWorktree(_ id: String) {
        guard let section = model.section(id), let parent = section.repo.parent, section.repo.lockReason == nil,
            let client = clients[parent]
        else { return }
        let branch = section.status.map(GitRepoSectionView.headText) ?? "?"
        confirm(
            "Remove the worktree \u{201c}\(section.repo.name)\u{201d}?",
            "\(section.repo.url.path(percentEncoded: false)) is deleted; the branch \(branch) is kept. git refuses "
                + "while the worktree holds modified or untracked files.",
            "Remove Worktree"
        ) { [weak self] in
            Task {
                do throws(GitError) {
                    _ = try await client.run(GitCommand.removeWorktree(section.repo.url, force: false), kind: .write)
                    self?.model.setActionError(parent, nil)
                } catch {
                    self?.model.setActionError(parent, error)
                }
                await self?.discoverAndRefresh()
            }
        }
    }

    /// git R39: the worktree folder in a window of its own, the path *File › Open…* takes.
    func openAsWorkspace(_ id: String) {
        guard let section = model.section(id) else { return }
        (NSApp.delegate as? ForemanAppDelegate)?.openRecent(section.repo.url)
    }

    /// git R36b: the base *Compare with* offers first — the branch of the parent's main folder.
    func defaultCompareBase(for id: String) -> String? {
        guard let parent = model.section(id)?.repo.parent,
            case .branch(let branch) = model.section(parent)?.status?.head
        else { return nil }
        return branch
    }

    /// git R36b: the history narrowed to what the child's branch adds, and one diff of all of it.
    func compare(_ id: String, with base: String) {
        guard let head = model.section(id)?.status.flatMap(Self.revision) else { return }
        history.repoID = id
        history.query.path = nil
        history.query.range = GitLogQuery.Range(base: base, head: head)
        history.selection = []
        if !layout.panels.isVisible(Self.historyPanelID) {
            layout.panels.show(Self.historyPanelID)
        }
        Task { [weak self] in
            guard let self else { return }
            history.reload(with: await client(for: id))
        }
        openDiff(GitDiffPayload(repo: id, source: .range(base: base, head: head)), preview: false)
    }

    /// git R36b: *Compare with…*, the repo's local branches in a pop-up.
    func chooseCompareBase(_ id: String) {
        guard let client = clients[id] else { return }
        Task { [weak self] in
            let output = try? await client.run(GitCommand.branches)
            let names = (output.map { RefParser.branches($0.stdout) } ?? []).filter { !$0.isRemote }.map(\.name)
            guard let self, !names.isEmpty else { return }
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
            popup.addItems(withTitles: names)
            if let base = defaultCompareBase(for: id) {
                popup.selectItem(withTitle: base)
            }
            let alert = NSAlert()
            alert.messageText = "Compare \u{201c}\(model.section(id)?.repo.name ?? id)\u{201d} with"
            alert.accessoryView = popup
            alert.addButton(withTitle: "Compare")
            alert.addButton(withTitle: "Cancel")
            present(alert) { [weak self] response in
                guard response == .alertFirstButtonReturn, let base = popup.titleOfSelectedItem else { return }
                self?.compare(id, with: base)
            }
        }
    }

    /// The branch, or the sha of a detached `HEAD`; nothing to compare on an unborn branch.
    nonisolated static func revision(_ status: GitStatus) -> String? {
        switch status.head {
        case .branch(let name): return name
        case .detached(let sha): return sha
        case .unborn: return nil
        }
    }

    // MARK: - Actions (git R7–R9)

    /// git R10: the commit area follows the working copy last worked in.
    func setCommitTarget(_ id: String) {
        model.setCommitTarget(id)
    }

    func stage(_ paths: [String], in id: String) {
        model.setCommitTarget(id)
        write([GitCommand.stage(paths)], in: id)
    }

    func unstage(_ paths: [String], in id: String) {
        model.setCommitTarget(id)
        guard let status = model.section(id)?.status else { return }
        var isUnborn = false
        if case .unborn = status.head {
            isUnborn = true
        }
        write([GitCommand.unstage(paths, isUnborn: isUnborn)], in: id)
    }

    /// git R8: always confirmed, with the count and the word "irreversible".
    func discard(_ entries: [GitStatusEntry], in id: String) {
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText =
            entries.count == 1
            ? "Discard the changes in \u{201c}\(entries[0].path)\u{201d}?"
            : "Discard the changes in \(entries.count) files?"
        alert.informativeText = "This is irreversible: the changes are not in git and cannot be recovered."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.write(GitCommand.discard(entries), in: id)
        }
    }

    /// git R9: the file opens with its markers; `add` marks it resolved.
    func markResolved(_ path: String, in id: String) {
        model.setCommitTarget(id)
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

    /// git R34b: the whole group, persisted under the repo id.
    func toggleGroupCollapsed(_ id: String) {
        model.toggleGroupCollapsed(id)
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
            let file = FileManager.default.temporaryDirectory.appending(path: "foreman-commit-\(UUID().uuidString).txt")
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
