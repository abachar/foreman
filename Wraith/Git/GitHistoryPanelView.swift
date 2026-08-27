import SwiftUI

/// The right panel `git.history` (git R18–R20): a repo picker, a filter, the linear log.
struct GitHistoryPanelView: View {
    let model: GitHistoryModel
    let changes: GitModel
    let feature: GitFeature
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.error {
                Label(error.description, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            if model.repoID == nil {
                ContentUnavailableView("No Repository", systemImage: "clock.arrow.circlepath")
            } else if model.commits.isEmpty, model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.commits.isEmpty {
                ContentUnavailableView("No Commits", systemImage: "clock.arrow.circlepath")
            } else {
                table
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker(
                "Repository",
                selection: Binding(
                    get: { model.repoID ?? "" }, set: { feature.showHistory(repo: $0, path: nil) })
            ) {
                ForEach(changes.sections) { section in
                    Text(section.repo.name).tag(section.id)
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
            TextField("Filter subject or author", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { feature.filterHistory(filterText) }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var table: some View {
        Table(model.commits, selection: Bindable(model).selection) {
            TableColumn("Commit") { commit in
                Text(commit.shortSha)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Subject") { commit in
                HStack(spacing: 4) {
                    ForEach(commit.refs, id: \.self) { ref in
                        Text(ref)
                            .font(.caption)
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
            // git R19: a click previews the commit's diff.
            if let sha = selection.first, let commit = model.commits.first(where: { $0.sha == sha }) {
                feature.openCommitDiff(commit, preview: true)
            }
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
