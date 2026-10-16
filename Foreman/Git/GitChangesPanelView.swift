import SwiftUI

/// The right panel `git.changes` (git R2, R6): a banner, then one section per repo.
struct GitChangesPanelView: View {
    let model: GitModel
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(title: "Changes", theme: theme) { EmptyView() }
            if let banner = model.banner {
                // git R28: git missing or too old; nothing else happens.
                BannerView(text: banner, icon: "exclamationmark.triangle", tone: .error, theme: theme)
            }
            if model.sections.isEmpty {
                if model.isDiscovering {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.banner == nil {
                    ContentUnavailableView(
                        "No Repository", systemImage: "arrow.triangle.branch",
                        description: Text("No .git found up to two levels under the root, and no repos in config.json.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.groups) { group in
                            groupView(group)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.revealed) { _, id in
                        // git R36, agents R5b: once, then forgotten.
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .top)
                        model.clearRevealed()
                    }
                }
                // git R10 (amended 2026-10-16): one commit area, always at the bottom of the panel.
                if let target = model.commitTarget {
                    theme.tokens.separator.color.frame(height: 1)
                    GitCommitView(section: target, sections: model.sections, feature: feature, theme: theme)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.branchSheetRepo != nil }, set: { if !$0 { feature.closeBranchSheet() } })
        ) {
            if let repo = model.branchSheetRepo {
                GitBranchesSheet(repo: repo, model: model, feature: feature, theme: theme)
            }
        }
    }
}

extension GitChangesPanelView {
    /// git R34b: a repo without worktrees is one section; with some, a group whose main folder is
    /// its first child.
    @ViewBuilder
    fileprivate func groupView(_ group: GitRepoGroup) -> some View {
        if group.children.isEmpty {
            sectionView(group.top, style: .repo)
        } else {
            let isCollapsed = model.isGroupCollapsed(group.id)
            Section {
            } header: {
                GitRepoGroupHeaderView(
                    section: group.top, isCollapsed: isCollapsed, feature: feature, theme: theme)
            }
            if !isCollapsed {
                sectionView(group.top, style: .main)
                ForEach(group.children) { child in
                    sectionView(child, style: .worktree)
                }
            }
        }
    }

    fileprivate func sectionView(_ section: GitModel.Section, style: GitRepoSectionView.Style) -> some View {
        GitRepoSectionView(
            section: section, style: style, agents: model.agentSessions(in: section.id), feature: feature,
            theme: theme)
    }
}

/// git R34b: the header of a repo with worktrees — its name, *Fetch*, and a chevron folding it all.
struct GitRepoGroupHeaderView: View {
    let section: GitModel.Section
    let isCollapsed: Bool
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        HStack(spacing: 6) {
            Button {
                feature.toggleGroupCollapsed(section.id)
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            Text(section.repo.name)
                .font(theme.font(.title, weight: .medium))
                .lineLimit(1)
            Spacer()
            if section.remoteOperation == .fetch {
                ProgressView()
                    .controlSize(.mini)
            }
            Button {
                feature.fetch(in: section.id)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Fetch (prune)")
            .disabled(section.remoteOperation != nil || feature.isInert)
        }
        .padding(.vertical, 2)
        .id(section.id + "#group")
    }
}

/// git R34c: an agent tab working in a folder — its icon, its title, its state; a click shows it.
struct GitAgentBadgeView: View {
    let session: GitAgentSession
    let theme: ThemeService
    let activate: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            if let image = IconImage.resolve(session.icon) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
            }
            Text(session.title)
                .lineLimit(1)
            if session.isRunning {
                Circle()
                    .fill(theme.tokens.statusGreen.color)
                    .frame(width: 6, height: 6)
            }
            if session.isMarked {
                Image(systemName: "bell.fill")
                    .foregroundStyle(theme.tokens.statusOrange.color)
            }
        }
        .font(theme.font(.small))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.quaternary, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: activate)
        .help("Show \(session.title)")
        .fixedSize()
    }
}

/// git R34: `worktree`, `lock` — a word in a thin capsule.
struct GitTagView: View {
    let text: String
    let theme: ThemeService
    var help: String?

    var body: some View {
        Text(text)
            .font(theme.font(.small))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .overlay(Capsule().strokeBorder(.tertiary))
            .help(help ?? "")
            .fixedSize()
    }
}

/// git R23: local and remote branches with a search field, and the branch actions.
struct GitBranchesSheet: View {
    let repo: String
    let model: GitModel
    let feature: GitFeature
    let theme: ThemeService
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [GitBranch] {
        Self.filter(model.branches, query: query)
    }

    nonisolated static func filter(_ branches: [GitBranch], query: String) -> [GitBranch] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? branches : branches.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search branches", text: $query)
                .textFieldStyle(.roundedBorder)
            if model.isLoadingBranches {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                branchList
            }
            HStack {
                Button("New Branch from HEAD\u{2026}") { feature.newBranch(in: repo) }
                Spacer()
                Text("Double-click to check out")
                    .font(theme.font(.small))
                    .foregroundStyle(.secondary)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 420, height: 380)
    }

    private var branchList: some View {
        List(shown) { branch in
            // git R36: a branch checked out in another working copy of the repo.
            let holder = feature.holder(of: branch, besides: repo)
            HStack(spacing: 6) {
                Image(
                    systemName: branch.isCurrent
                        ? "checkmark" : (branch.isRemote ? "cloud" : "arrow.triangle.branch")
                )
                .frame(width: 14)
                .foregroundStyle(.secondary)
                Text(branch.name)
                if let upstream = branch.upstream {
                    Text("\u{2192} \(upstream)")
                        .font(theme.font(.small))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let holder {
                    GitTagView(text: holder.repo.name, theme: theme, help: holder.repo.url.path(percentEncoded: false))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let holder {
                    feature.showChanges(of: holder.id)
                } else {
                    feature.checkout(branch, in: repo)
                }
            }
            .contextMenu {
                if let holder {
                    if holder.repo.parent == repo {
                        Button("Check Out Here") { feature.checkOutHere(holder.id) }
                    }
                    Button("Show Changes") { feature.showChanges(of: holder.id) }
                } else {
                    Button("Checkout") { feature.checkout(branch, in: repo) }
                        .disabled(branch.isCurrent)
                }
                if !branch.isRemote {
                    Button("Rename\u{2026}") { feature.renameBranch(branch, in: repo) }
                    Button("Set Upstream\u{2026}") { feature.setUpstream(of: branch, in: repo) }
                    Button("Delete") { feature.deleteBranch(branch, in: repo) }
                        .disabled(branch.isCurrent)
                }
            }
        }
    }
}

/// One repo (git R2): the header, the banners, then Conflicts / Staged / Changes (R6).
struct GitRepoSectionView: View {
    /// git R34b: a repo alone, or one working copy of a group.
    enum Style {
        case repo
        case main
        case worktree
    }

    let section: GitModel.Section
    var style: Style = .repo
    /// git R34c: the agent tabs working in this folder.
    var agents: [GitAgentSession] = []
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        Section {
            if !section.isCollapsed {
                let sections = section.sections
                group("Conflicts", entries: sections.conflicts, kind: .conflicts)
                group("Staged", entries: sections.staged, kind: .staged)
                group("Changes", entries: sections.changes, kind: .changes)
            }
        } header: {
            header
                .padding(.leading, inset)
                .id(section.id)
        }
    }

    /// git R34b: a working copy of a group sits under the group's header.
    private var inset: CGFloat {
        style == .repo ? 0 : 14
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    feature.toggleCollapsed(section.id)
                } label: {
                    Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .disabled(section.status.map { GitSections($0.entries).isEmpty } ?? true)
                if style == .repo {
                    Text(section.repo.name)
                        .font(theme.font(.title, weight: .medium))
                        .lineLimit(1)
                }
                if let status = section.status {
                    // git R34: in a group the branch names the row; the full name in the tooltip.
                    Text(Self.headText(status))
                        .font(style == .repo ? theme.font() : theme.font(weight: .medium))
                        .foregroundStyle(style == .repo ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(Self.headText(status))
                        .layoutPriority(1)
                    if status.ahead > 0 || status.behind > 0 {
                        Text(Self.aheadBehindText(ahead: status.ahead, behind: status.behind))
                            .font(theme.font(.small))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                if style == .worktree {
                    Text(section.repo.name)
                        .font(theme.font(.small))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(section.repo.url.path(percentEncoded: false))
                }
                Spacer(minLength: 4)
                ForEach(agents) { session in
                    GitAgentBadgeView(session: session, theme: theme) { feature.activateAgentTab?(session.id) }
                }
                if style == .worktree {
                    GitTagView(text: "worktree", theme: theme)
                    if let reason = section.repo.lockReason {
                        GitTagView(text: "lock", theme: theme, help: reason.isEmpty ? "Locked" : reason)
                    }
                }
                if section.isLoading || section.remoteOperation != nil {
                    ProgressView()
                        .controlSize(.mini)
                }
                remoteButtons
                    .fixedSize()
            }
            if let operation = section.remoteOperation {
                Text("\(operation.rawValue)\u{2026}")
                    .font(theme.font(.small))
                    .foregroundStyle(.secondary)
            }
            if let auth = section.authRequired {
                // git R22: the exact command to run elsewhere; no secret ever enters Foreman.
                VStack(alignment: .leading, spacing: 2) {
                    Label("Authentication required", systemImage: "key")
                        .font(theme.font(weight: .medium))
                    Text(auth.command)
                        .font(theme.codeFont(.small))
                    Text(auth.cwd.path(percentEncoded: false))
                        .font(theme.font(.small))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Copy the Command") { feature.copy(auth.copyText) }
                        .controlSize(.small)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.tokens.surfaceRaised.color)
            }
            if !section.stashes.isEmpty {
                stashList
            }
            if let operation = section.status?.operation {
                // git R9: the state and its two exits.
                HStack(spacing: 6) {
                    Text(Self.operationText(operation))
                        .font(theme.font(.small, weight: .medium))
                        .foregroundStyle(Color(nsColor: theme.color(for: .conflicted)))
                    Button("Abort") { feature.abort(operation, in: section.id) }
                    Button("Continue") { feature.continueOperation(operation, in: section.id) }
                    Spacer()
                }
                .controlSize(.small)
            }
            if let error = section.error {
                banner(Self.errorText(error), icon: "exclamationmark.triangle")
            }
            if let error = section.actionError {
                banner(error.description, icon: "xmark.octagon")
            }
        }
        .padding(.vertical, 2)
    }

    /// git R21, R23, R24: fetch / pull / push and the menu; in a group, *Fetch* is the group's
    /// (R34b).
    private var remoteButtons: some View {
        HStack(spacing: 2) {
            if style == .repo {
                Button {
                    feature.fetch(in: section.id)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Fetch (prune)")
            }
            Button {
                feature.pull(in: section.id)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .help("Pull")
            Button {
                feature.push(in: section.id)
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .help("Push")
            Menu {
                Button("Branches\u{2026}") { feature.showBranches(in: section.id) }
                Button("New Branch from HEAD\u{2026}") { feature.newBranch(in: section.id) }
                Divider()
                Button("Stash\u{2026}") { feature.stash(includeUntracked: false, in: section.id) }
                Button("Stash Including Untracked\u{2026}") { feature.stash(includeUntracked: true, in: section.id) }
                if !section.stashes.isEmpty {
                    Button(section.isStashListExpanded ? "Hide Stashes" : "Show Stashes (\(section.stashes.count))") {
                        feature.toggleStashList(in: section.id)
                    }
                }
                if style == .worktree {
                    worktreeMenu
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .disabled(section.remoteOperation != nil || feature.isInert)
    }

    /// git R36b–R39: what only a worktree offers.
    @ViewBuilder
    private var worktreeMenu: some View {
        Divider()
        if let base = feature.defaultCompareBase(for: section.id) {
            Button("Compare with \(base)") { feature.compare(section.id, with: base) }
        }
        Button("Compare with\u{2026}") { feature.chooseCompareBase(section.id) }
        Divider()
        if case .branch = section.status?.head {
            Button("Check Out Here") { feature.checkOutHere(section.id) }
        }
        Button("Remove Worktree\u{2026}") { feature.removeWorktree(section.id) }
            .disabled(section.repo.lockReason != nil)
        Button("Open as Workspace") { feature.openAsWorkspace(section.id) }
    }

    /// git R24: collapsed by default; apply, pop, drop.
    private var stashList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                feature.toggleStashList(in: section.id)
            } label: {
                Label(
                    "Stashes (\(section.stashes.count))",
                    systemImage: section.isStashListExpanded ? "chevron.down" : "chevron.right"
                )
                .font(theme.font(.small))
            }
            .buttonStyle(.plain)
            if section.isStashListExpanded {
                ForEach(section.stashes) { stash in
                    HStack(spacing: 6) {
                        Text(stash.ref)
                            .font(theme.codeFont(.small))
                        Text(stash.message)
                            .font(theme.font(.small))
                            .lineLimit(1)
                        Spacer()
                        Button("Apply") { feature.stash(.apply, stash, in: section.id) }
                        Button("Pop") { feature.stash(.pop, stash, in: section.id) }
                        Button("Drop") { feature.stash(.drop, stash, in: section.id) }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                }
            }
        }
    }

    private func banner(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(theme.font())
            .foregroundStyle(theme.tokens.statusRed.color)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum GroupKind {
        case conflicts
        case staged
        case changes
    }

    @ViewBuilder
    private func group(_ title: String, entries: [GitStatusEntry], kind: GroupKind) -> some View {
        if !entries.isEmpty {
            HStack {
                Text("\(title) (\(entries.count))")
                    .font(theme.font(.small, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                groupActions(entries, kind: kind)
            }
            .padding(.top, 4)
            .padding(.leading, inset)
            // git R6b: one tree per group, open at first sight, no per-folder action; the
            // explorer's look (design R23), the status letter at the end of the row.
            let byPath = Dictionary(entries.map { ($0.path, $0) }) { first, _ in first }
            FittedFileTreeView(
                entries: entries.map { Self.treeEntry($0, kind: kind) }, theme: theme,
                open: { treeEntry, pinned in
                    guard let entry = byPath[treeEntry.path] else { return }
                    feature.setCommitTarget(section.id)
                    // git R13, US3: a click previews the diff, a double click pins it.
                    feature.openDiff(
                        GitDiffPayload(repo: section.id, source: Self.diffSource(entry, kind: kind)), preview: !pinned)
                },
                actions: { treeEntry in byPath[treeEntry.path].map { rowActions($0, kind: kind) } ?? [] },
                menu: { treeEntry in
                    guard let entry = byPath[treeEntry.path] else { return [] }
                    return [
                        FileTreeAction(title: "Open File", symbol: "doc.text") {
                            feature.open(entry.path, in: section.id)
                        },
                        FileTreeAction(title: "Git History", symbol: "clock") {
                            feature.showHistory(repo: section.id, path: entry.path)
                        },
                    ] + rowActions(entry, kind: kind).dropLast()
                }
            )
            .padding(.leading, inset)
        }
    }

    /// git R6, R6b: a row of the tree — the name coloured by the group's side, the letter, a
    /// rename's origin.
    private static func treeEntry(_ entry: GitStatusEntry, kind: GroupKind) -> FileTreeEntry {
        let side: GitFileStatus =
            switch kind {
            case .conflicts: .conflicted
            case .staged: GitStatusEntry.fileStatus(of: entry.index)
            case .changes: entry.isUntracked ? .untracked : GitStatusEntry.fileStatus(of: entry.worktree)
            }
        return FileTreeEntry(
            path: entry.path, status: side, mark: letter(of: entry, kind: kind),
            detail: entry.originalPath.map { "\u{2190} \($0)" })
    }

    /// git R7: the per-section actions.
    @ViewBuilder
    private func groupActions(_ entries: [GitStatusEntry], kind: GroupKind) -> some View {
        let paths = entries.map(\.path)
        switch kind {
        case .conflicts:
            EmptyView()
        case .staged:
            Button("Unstage All") { feature.unstage(paths, in: section.id) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        case .changes:
            HStack(spacing: 8) {
                Button("Discard All") { feature.discard(entries, in: section.id) }
                Button("Stage All") { feature.stage(paths, in: section.id) }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    /// git R7, R9: the hover buttons of a row, *Open File* last.
    private func rowActions(_ entry: GitStatusEntry, kind: GroupKind) -> [FileTreeAction] {
        let open = FileTreeAction(title: "Open File", symbol: "doc.text") { feature.open(entry.path, in: section.id) }
        switch kind {
        case .conflicts:
            return [
                FileTreeAction(title: "Mark as Resolved", symbol: "checkmark.circle") {
                    feature.markResolved(entry.path, in: section.id)
                },
                open,
            ]
        case .staged:
            return [
                FileTreeAction(title: "Unstage", symbol: "minus.circle") {
                    feature.unstage([entry.path], in: section.id)
                },
                open,
            ]
        case .changes:
            return [
                FileTreeAction(title: "Discard", symbol: "arrow.uturn.backward.circle") {
                    feature.discard([entry], in: section.id)
                },
                FileTreeAction(title: "Stage", symbol: "plus.circle") {
                    feature.stage([entry.path], in: section.id)
                },
                open,
            ]
        }
    }

    // MARK: - Texts (git R2, R6, R9)

    nonisolated static func headText(_ status: GitStatus) -> String {
        switch status.head {
        case .branch(let name): return name
        case .detached(let sha): return "detached HEAD @ \(sha)"
        case .unborn(let name): return name.map { "\($0) (no commits)" } ?? "no commits"
        }
    }

    nonisolated static func aheadBehindText(ahead: Int, behind: Int) -> String {
        [ahead > 0 ? "\u{2191}\(ahead)" : nil, behind > 0 ? "\u{2193}\(behind)" : nil].compactMap { $0 }
            .joined(separator: " ")
    }

    nonisolated static func operationText(_ operation: GitOperation) -> String {
        switch operation {
        case .merging: return "MERGING"
        case .rebasing: return "REBASING"
        case .cherryPicking: return "CHERRY-PICKING"
        }
    }

    /// git, edge cases: a `status` over 30 s names the way out.
    nonisolated static func errorText(_ error: GitError) -> String {
        switch error {
        case .timeout: return "status took more than 30 s; remove this repo from \"repos\" in .foreman/config.json."
        default: return error.description
        }
    }

    /// git R14: the staged group shows the index against HEAD, the others the worktree.
    private static func diffSource(_ entry: GitStatusEntry, kind: GroupKind) -> GitDiffPayload.Source {
        switch kind {
        case .staged: return .staged(path: entry.path)
        case .changes, .conflicts: return .workingTree(path: entry.path)
        }
    }

    /// git R6: the side of the entry the group shows.
    private static func letter(of entry: GitStatusEntry, kind: GroupKind) -> String {
        switch kind {
        case .conflicts: return "U"
        case .staged: return String(entry.index.rawValue)
        case .changes: return String(entry.worktree.rawValue)
        }
    }
}

/// git R10–R12: the message, its counter, *Amend*, *Commit* and `cmd+enter` (a key of the field,
/// decision 2026-08-27), *Cancel* while a hook runs.
struct GitCommitView: View {
    let section: GitModel.Section
    /// git R10: every working copy the area can commit in.
    let sections: [GitModel.Section]
    let feature: GitFeature
    let theme: ThemeService

    private var canCommit: Bool {
        CommitMessage.canCommit(
            message: section.message, stagedCount: section.sections.staged.count, amend: section.isAmending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // git R10: where the commit goes — the working copy last worked in, or another one.
            Picker(
                "Commit in",
                selection: Binding(get: { section.id }, set: { feature.setCommitTarget($0) })
            ) {
                ForEach(sections) { candidate in
                    Text(Self.label(candidate)).tag(candidate.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            TextEditor(
                text: Binding(get: { section.message }, set: { feature.setMessage($0, in: section.id) })
            )
            .font(theme.font())
            .frame(minHeight: 48, maxHeight: 120)
            .overlay(alignment: .topLeading) {
                if section.message.isEmpty {
                    Text("Commit message")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.command), canCommit else { return .ignored }
                feature.commit(in: section.id)
                return .handled
            }
            HStack(spacing: 8) {
                let subject = CommitMessage.subject(of: section.message).count
                Text("\(subject)/\(CommitMessage.subjectLimit)")
                    .font(theme.font(.small).monospacedDigit())
                    .foregroundStyle(
                        subject > CommitMessage.subjectLimit
                            ? theme.tokens.statusRed.color : theme.tokens.textSecondary.color)
                Toggle(
                    "Amend",
                    isOn: Binding(get: { section.isAmending }, set: { feature.setAmending($0, in: section.id) })
                )
                .toggleStyle(.checkbox)
                Spacer()
                if section.isCommitting {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel") { feature.cancelCommit(in: section.id) }
                } else {
                    Button("Commit") { feature.commit(in: section.id) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canCommit)
                }
            }
            .controlSize(.small)
        }
        .padding(.top, 6)
    }

    /// `app · main (2 staged)`: the folder, its branch, what a commit would take.
    private static func label(_ section: GitModel.Section) -> String {
        let head = section.status.map(GitRepoSectionView.headText).map { " \u{00b7} \($0)" } ?? ""
        let staged = section.sections.staged.count
        return section.repo.name + head + (staged > 0 ? " (\(staged) staged)" : "")
    }
}
