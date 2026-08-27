import SwiftUI

/// The right panel `git.changes` (git R2, R6): a banner, then one section per repo.
struct GitChangesPanelView: View {
    let model: GitModel
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Changes")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            if let banner = model.banner {
                // git R28: git missing or too old; nothing else happens.
                Label(banner, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
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
                } else {
                    Spacer()
                }
            } else {
                List {
                    ForEach(model.sections) { section in
                        GitRepoSectionView(section: section, feature: feature, theme: theme)
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { feature.branchSheetRepo != nil }, set: { if !$0 { feature.branchSheetRepo = nil } })
        ) {
            if let repo = feature.branchSheetRepo {
                GitBranchesSheet(repo: repo, feature: feature)
            }
        }
    }
}

/// git R23: local and remote branches with a search field, and the branch actions.
struct GitBranchesSheet: View {
    let repo: String
    let feature: GitFeature
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [GitBranch] {
        Self.filter(feature.branches, query: query)
    }

    nonisolated static func filter(_ branches: [GitBranch], query: String) -> [GitBranch] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? branches : branches.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search branches", text: $query)
                .textFieldStyle(.roundedBorder)
            List(shown) { branch in
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { feature.checkout(branch, in: repo) }
                .contextMenu {
                    Button("Checkout") { feature.checkout(branch, in: repo) }
                        .disabled(branch.isCurrent)
                    if !branch.isRemote {
                        Button("Rename\u{2026}") { feature.renameBranch(branch, in: repo) }
                        Button("Set Upstream\u{2026}") { feature.setUpstream(of: branch, in: repo) }
                        Button("Delete") { feature.deleteBranch(branch, in: repo) }
                            .disabled(branch.isCurrent)
                    }
                }
            }
            HStack {
                Button("New Branch from HEAD\u{2026}") { feature.newBranch(in: repo) }
                Spacer()
                Text("Double-click to check out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 420, height: 380)
    }
}

/// One repo (git R2): the header, the banners, then Conflicts / Staged / Changes (R6).
struct GitRepoSectionView: View {
    let section: GitModel.Section
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        Section {
            if !section.isCollapsed {
                let sections = section.sections
                group("Conflicts", entries: sections.conflicts, kind: .conflicts)
                group("Staged", entries: sections.staged, kind: .staged)
                group("Changes", entries: sections.changes, kind: .changes)
                GitCommitView(section: section, feature: feature)
            }
        } header: {
            header
        }
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
                Text(section.repo.name)
                    .font(.headline)
                    .lineLimit(1)
                if let status = section.status {
                    Text(Self.headText(status))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if status.ahead > 0 || status.behind > 0 {
                        Text(Self.aheadBehindText(ahead: status.ahead, behind: status.behind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if section.isLoading || section.remoteOperation != nil {
                    ProgressView()
                        .controlSize(.mini)
                }
                remoteButtons
            }
            if let operation = section.remoteOperation {
                Text("\(operation.rawValue)\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let auth = section.authRequired {
                // git R22: the exact command to run elsewhere; no secret ever enters Wraith.
                VStack(alignment: .leading, spacing: 2) {
                    Label("Authentication required", systemImage: "key")
                        .font(.callout.bold())
                    Text(auth.command)
                        .font(.system(.caption, design: .monospaced))
                    Text(auth.cwd.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Copy the Command") { feature.copy(auth.copyText) }
                        .controlSize(.small)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            if !section.stashes.isEmpty {
                stashList
            }
            if let operation = section.status?.operation {
                // git R9: the state and its two exits.
                HStack(spacing: 6) {
                    Text(Self.operationText(operation))
                        .font(.caption.bold())
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

    /// git R21, R23, R24: fetch / pull / push and the menu.
    private var remoteButtons: some View {
        HStack(spacing: 2) {
            Button {
                feature.fetch(in: section.id)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Fetch (prune)")
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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .disabled(section.remoteOperation != nil || feature.isInert)
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
                .font(.caption)
            }
            .buttonStyle(.plain)
            if section.isStashListExpanded {
                ForEach(section.stashes) { stash in
                    HStack(spacing: 6) {
                        Text(stash.ref)
                            .font(.system(.caption, design: .monospaced))
                        Text(stash.message)
                            .font(.caption)
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
            .font(.callout)
            .foregroundStyle(.red)
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
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                groupActions(entries, kind: kind)
            }
            .padding(.top, 4)
            ForEach(entries) { entry in
                GitChangeRowView(
                    entry: entry, letter: Self.letter(of: entry, kind: kind),
                    color: Color(nsColor: theme.color(for: entry.fileStatus)),
                    actions: rowActions(entry, kind: kind), open: { feature.open(entry.path, in: section.id) },
                    select: { preview in
                        // git R13, US3: a click previews the diff, a double click pins it.
                        feature.openDiff(
                            GitDiffPayload(repo: section.id, source: Self.diffSource(entry, kind: kind)),
                            preview: preview)
                    },
                    history: { feature.showHistory(repo: section.id, path: entry.path) })
            }
        }
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

    /// git R7, R9: the hover buttons of a row.
    private func rowActions(_ entry: GitStatusEntry, kind: GroupKind) -> [GitChangeRowView.Action] {
        switch kind {
        case .conflicts:
            return [
                GitChangeRowView.Action(title: "Mark as Resolved", icon: "checkmark.circle") {
                    feature.markResolved(entry.path, in: section.id)
                }
            ]
        case .staged:
            return [
                GitChangeRowView.Action(title: "Unstage", icon: "minus.circle") {
                    feature.unstage([entry.path], in: section.id)
                }
            ]
        case .changes:
            return [
                GitChangeRowView.Action(title: "Discard", icon: "arrow.uturn.backward.circle") {
                    feature.discard([entry], in: section.id)
                },
                GitChangeRowView.Action(title: "Stage", icon: "plus.circle") {
                    feature.stage([entry.path], in: section.id)
                },
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
        case .timeout: return "status took more than 30 s; remove this repo from \"repos\" in .wraith/config.json."
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
    let feature: GitFeature

    private var canCommit: Bool {
        CommitMessage.canCommit(
            message: section.message, stagedCount: section.sections.staged.count, amend: section.isAmending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(
                text: Binding(get: { section.message }, set: { feature.setMessage($0, in: section.id) })
            )
            .font(.body)
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
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(subject > CommitMessage.subjectLimit ? .red : .secondary)
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
}

/// git R6: status, name in bold, folder in grey, the actions on hover.
struct GitChangeRowView: View {
    struct Action: Identifiable {
        let title: String
        let icon: String
        let perform: () -> Void

        var id: String {
            title
        }
    }

    let entry: GitStatusEntry
    let letter: String
    let color: Color
    let actions: [Action]
    let open: () -> Void
    let select: (_ preview: Bool) -> Void
    let history: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(letter)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if !folder.isEmpty {
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isHovering {
                ForEach(actions) { action in
                    Button {
                        action.perform()
                    } label: {
                        Image(systemName: action.icon)
                    }
                    .buttonStyle(.borderless)
                    .help(action.title)
                }
                Button {
                    open()
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open File")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { select(false) }
        .onTapGesture { select(true) }
        .contextMenu {
            Button("Open File") { open() }
            Button("Git History") { history() }
        }
    }

    private var name: String {
        entry.path.split(separator: "/").last.map(String.init) ?? entry.path
    }

    private var folder: String {
        let parent = entry.path.split(separator: "/").dropLast().joined(separator: "/")
        guard let origin = entry.originalPath else { return parent }
        return parent.isEmpty ? "\u{2190} \(origin)" : "\(parent)  \u{2190} \(origin)"
    }
}
