import SwiftUI

/// The right panel `git.history` (git R18–R20): a repo picker, a filter, the linear log.
struct GitHistoryPanelView: View {
    let model: GitHistoryModel
    let changes: GitModel
    let feature: GitFeature
    let theme: ThemeService
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.error {
                BannerView(text: error.description, icon: "exclamationmark.triangle", tone: .error, theme: theme)
            }
            if model.repoID == nil {
                ContentUnavailableView("No Repository", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.commits.isEmpty, model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.commits.isEmpty {
                ContentUnavailableView("No Commits", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let commit = model.filesCommit {
                // git R19b (amended 2026-10-16, view 05): the selected commit's details and files
                // beside the log, the panel being as wide as the centre.
                HSplitView {
                    table
                        .frame(minWidth: 480, idealWidth: 1000, maxWidth: .infinity)
                        .layoutPriority(1)
                    GitCommitFilesView(commit: commit, model: model, feature: feature, theme: theme)
                        .frame(minWidth: 240, idealWidth: 340, maxWidth: 480)
                }
            } else {
                table
            }
        }
    }

    private var header: some View {
        PanelHeaderView(panels: feature.panels, current: GitFeature.historyPanelID, theme: theme) {
            if changes.sections.count > 1 {
                Picker(
                    "Repository",
                    selection: Binding(
                        get: { model.repoID ?? "" }, set: { feature.showHistory(repo: $0, path: nil) })
                ) {
                    // git R34a: the worktrees under their repo.
                    ForEach(changes.sections) { section in
                        Text(section.repo.parent == nil ? section.repo.name : "\u{2003}\(section.repo.name)").tag(
                            section.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let path = model.query.path {
                // git R20: a file's history.
                chip(path)
            }
            if let range = model.query.range {
                // git R36b: only what the branch adds.
                chip("vs \(range.base)")
            }
            TextField("Filter message or author", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 280)
                .onSubmit { feature.filterHistory(filterText) }
            Picker(
                "Branches",
                selection: Binding(get: { model.query.allBranches }, set: { feature.setHistoryAllBranches($0) })
            ) {
                Text("Current branch").tag(false)
                Text("All branches").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            .disabled(model.query.range != nil)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    /// A narrowing of the log (a file, a range), closed back to the whole history.
    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                feature.showHistory(repo: model.repoID ?? ".", path: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Whole history")
        }
        .font(theme.font(.small))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.tokens.surfaceRaised.color, in: Capsule())
    }

    /// git R18 (amended 2026-10-16, view 05): the refs as chips then the message, the author, the
    /// date, the short hash at the end.
    private var table: some View {
        let remotes = Set(changes.refs.values.joined().filter(\.isRemote).map(\.name))
        let now = Date()
        return Table(model.commits, selection: Bindable(model).selection) {
            TableColumn("Message") { commit in
                HStack(spacing: 6) {
                    ForEach(GitRefChip.chips(commit.refs, remotes: remotes)) { chip in
                        GitRefChipView(chip: chip, theme: theme)
                            .fixedSize()
                    }
                    Text(commit.subject)
                        .lineLimit(1)
                }
            }
            TableColumn("Author") { commit in
                Text(commit.author)
                    .lineLimit(1)
                    .foregroundStyle(theme.tokens.textSecondary.color)
            }
            .width(min: 80, ideal: 150, max: 240)
            TableColumn("Date") { commit in
                Text(LogParser.shortDate(commit.date, now: now))
                    .lineLimit(1)
                    .foregroundStyle(theme.tokens.textSecondary.color)
            }
            .width(min: 80, ideal: 120, max: 160)
            TableColumn("Hash") { commit in
                Text(commit.shortSha)
                    .font(theme.codeFont())
                    .foregroundStyle(theme.tokens.textSecondary.color)
            }
            .width(min: 60, ideal: 76, max: 100)
        }
        .contextMenu(forSelectionType: String.self) { shas in
            if let sha = shas.first, let commit = model.commits.first(where: { $0.sha == sha }) {
                menu(commit)
            }
        } primaryAction: { shas in
            // git R19: a double click pins the commit's diff.
            if let sha = shas.first, let commit = model.commits.first(where: { $0.sha == sha }) {
                feature.openCommitDiff(commit, preview: false)
            }
        }
        .onChange(of: model.selection) { _, selection in
            // git R19b: a click lists the commit's files; a double click still opens it whole.
            feature.selectCommit(selection.first.flatMap { sha in model.commits.first { $0.sha == sha } })
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasMore {
                Button("Load 200 More") { feature.loadMoreHistory() }
                    .controlSize(.small)
                    .padding(4)
            }
        }
    }

    /// git R19: the menu; `reset --hard` is absent on purpose.
    @ViewBuilder
    private func menu(_ commit: GitCommit) -> some View {
        Button("Copy SHA") { feature.copy(commit.sha) }
        Divider()
        Button("Checkout (Detached HEAD)…") { feature.checkout(commit) }
        Button("Create Branch Here…") { feature.createBranch(at: commit) }
        Divider()
        Button("Cherry-pick…") { feature.cherryPick(commit) }
        Button("Revert…") { feature.revert(commit) }
        Divider()
        Button("Reset Soft to Here…") { feature.reset(to: commit, mode: .soft) }
        Button("Reset Mixed to Here…") { feature.reset(to: commit, mode: .mixed) }
    }
}

/// git R18 (amended 2026-10-16), design R3: a ref chip — the branch `HEAD` is on in
/// `statusGreen`, a local branch in the accent, a tag in `statusOrange`, a remote in grey; each a
/// tint of its colour behind its text.
struct GitRefChipView: View {
    let chip: GitRefChip
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        let color: ThemeColor =
            switch chip.kind {
            case .head: tokens.statusGreen
            case .local: tokens.accent
            case .tag: tokens.statusOrange
            case .remote: tokens.textSecondary
            }
        Text(chip.name)
            .font(theme.font(.small))
            .foregroundStyle((chip.kind == .remote ? tokens.textSecondary : tokens.textPrimary).color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// git R19b: the files a commit changed, as a tree; a click previews one file's diff in the center.
struct GitCommitFilesView: View {
    let commit: GitCommit
    let model: GitHistoryModel
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // git R19b (amended 2026-10-16, view 05): the commit's details above its files.
            VStack(alignment: .leading, spacing: 6) {
                Text(commit.subject)
                    .font(theme.font(.title, weight: .medium))
                    .lineLimit(3)
                    .textSelection(.enabled)
                detail("Author", commit.author)
                detail("Date", LogParser.shortDate(commit.date, now: Date()))
                detail(
                    "Hash",
                    ([commit.shortSha] + commit.parents.prefix(1).map { "parent \($0)" }).joined(
                        separator: " \u{00B7} "),
                    code: true)
                HStack {
                    Text(model.files.count == 1 ? "FILES \u{00B7} 1" : "FILES \u{00B7} \(model.files.count)")
                        .font(theme.font(.small, weight: .medium))
                        .foregroundStyle(theme.tokens.textSecondary.color)
                    if model.isLoadingFiles {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // design R23: the explorer's tree, the status letter at the end of the row.
            FileTreeView(
                entries: model.files.map(Self.treeEntry), theme: theme, font: theme.interfaceFont(),
                open: { entry, pinned in feature.openCommitFileDiff(commit, path: entry.path, preview: !pinned) },
                menu: { entry in
                    [
                        FileTreeAction(title: "Git History", symbol: "clock") {
                            feature.showHistory(repo: model.repoID ?? ".", path: entry.path)
                        }
                    ]
                })
        }
    }

    private func detail(_ label: String, _ value: String, code: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(theme.tokens.textSecondary.color)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(code ? theme.codeFont(.small) : theme.font())
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private static func treeEntry(_ entry: GitStatusEntry) -> FileTreeEntry {
        FileTreeEntry(
            path: entry.path, status: entry.fileStatus, mark: String(entry.index.rawValue),
            detail: entry.originalPath.map { "\u{2190} \($0)" })
    }
}
