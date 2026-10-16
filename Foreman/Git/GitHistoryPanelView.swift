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
                // git R19b: the selected commit's files under the log.
                VSplitView {
                    table
                        .frame(minHeight: 120)
                    GitCommitFilesView(commit: commit, model: model, feature: feature, theme: theme)
                        .frame(minHeight: 100)
                }
            } else {
                table
            }
        }
    }

    private var header: some View {
        PanelHeaderView(title: "History", theme: theme) {
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
            if let path = model.query.path {
                // git R20: a file's history.
                Text(path)
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
            if let range = model.query.range {
                // git R36b: only what the branch adds.
                Text("vs \(range.base)")
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: Capsule())
                Button {
                    feature.showHistory(repo: model.repoID ?? ".", path: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Whole history")
            }
            TextField("Filter subject or author", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { feature.filterHistory(filterText) }
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var table: some View {
        Table(model.commits, selection: Bindable(model).selection) {
            TableColumn("Commit") { commit in
                Text(commit.shortSha)
                    .font(theme.codeFont())
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Subject") { commit in
                HStack(spacing: 4) {
                    ForEach(commit.refs, id: \.self) { ref in
                        Text(ref)
                            .font(theme.font(.small))
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(commit.subject)
                        .lineLimit(1)
                }
            }
            TableColumn("Author") { commit in
                Text(commit.author)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140, max: 240)
            TableColumn("Date") { commit in
                Text(LogParser.relativeText(commit.date, now: Date()))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90, max: 120)
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

/// git R19b: the files a commit changed, as a tree; a click previews one file's diff in the center.
struct GitCommitFilesView: View {
    let commit: GitCommit
    let model: GitHistoryModel
    let feature: GitFeature
    let theme: ThemeService

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(commit.shortSha)
                    .font(theme.codeFont(.small))
                Text(commit.subject)
                    .font(theme.font(.small, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if model.isLoadingFiles {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(model.files.count == 1 ? "1 file" : "\(model.files.count) files")
                        .font(theme.font(.small))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.tokens.surfaceRaised.color)
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

    private static func treeEntry(_ entry: GitStatusEntry) -> FileTreeEntry {
        FileTreeEntry(
            path: entry.path, status: entry.fileStatus, mark: String(entry.index.rawValue),
            detail: entry.originalPath.map { "\u{2190} \($0)" })
    }
}
