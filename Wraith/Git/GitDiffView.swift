import SwiftUI

/// The `git.diff` tab (git R13, R16): a header per file, numbered hunks, `+`/`−` tinted lines.
struct GitDiffView: View {
    let model: GitDiffModel
    let theme: ThemeService

    var body: some View {
        Group {
            if let error = model.error {
                ContentUnavailableView(
                    "Diff Unavailable", systemImage: "exclamationmark.triangle", description: Text(error.description))
            } else if let diff = model.diff {
                if diff.files.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                } else {
                    content(diff)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            model.load()
        }
    }

    private func content(_ diff: GitDiff) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.files) { file in
                    fileHeader(file, isLarge: diff.isLarge)
                    if model.isExpanded(file) {
                        if file.isBinary {
                            Text(model.binarySizes[file.id] ?? "binary")
                                .foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            ForEach(model.rendered[file.id] ?? []) { hunk in
                                hunkView(hunk)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    /// git R16: the path, a rename arrow, a mode change; a large diff opens each file on demand.
    private func fileHeader(_ file: FileDiff, isLarge: Bool) -> some View {
        HStack(spacing: 6) {
            if isLarge {
                Button {
                    if model.expandedFiles.contains(file.id) {
                        model.expandedFiles.remove(file.id)
                    } else {
                        model.expandedFiles.insert(file.id)
                    }
                } label: {
                    Image(systemName: model.isExpanded(file) ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            }
            Text(Self.headerText(file))
                .font(.headline)
                .lineLimit(1)
            if let old = file.oldMode, let new = file.newMode {
                Text("mode \(old) \u{2192} \(new)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isLarge {
                Text("\(file.lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    nonisolated static func headerText(_ file: FileDiff) -> String {
        if file.isRename, let old = file.oldPath, let new = file.newPath {
            return "\(old) \u{2192} \(new)"
        }
        if file.newPath == nil, let old = file.oldPath {
            return "\(old) (deleted)"
        }
        if file.oldPath == nil {
            return "\(file.path) (new)"
        }
        return file.path
    }

    private func hunkView(_ hunk: RenderedHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(Font(theme.editorFont))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))
            HStack(alignment: .top, spacing: 0) {
                gutter(hunk.oldNumbers)
                gutter(hunk.newNumbers)
                Text(hunk.text)
                    .font(Font(theme.editorFont))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 8)
            }
            .padding(.vertical, 2)
        }
    }

    private func gutter(_ numbers: String) -> some View {
        Text(numbers)
            .font(Font(theme.editorFont))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 40, alignment: .trailing)
            .padding(.trailing, 4)
    }
}
