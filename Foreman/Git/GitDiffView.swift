import SwiftUI

/// The `git.diff` tab (git R13, R16): a header per file, numbered hunks, `+`/`−` tinted lines.
struct GitDiffView: View {
    let model: GitDiffModel
    let theme: ThemeService
    /// agents R10b: the line's context menu.
    let sendLine: (String, Int) -> Void

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

    /// git R13b (amended 2026-10-16): side by side only.
    ///
    /// M23 23.11: one lazy stack of flat rows, so only the rows near the viewport are built.
    private func content(_ diff: GitDiff) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(GitDiffModel.rows(of: diff, expanded: model.isExpanded, rendered: model.rendered)) { row in
                    switch row {
                    case .file(let file):
                        fileHeader(file, isLarge: diff.isLarge)
                    case .binary(let file):
                        Text(model.binarySizes[file.id] ?? "binary")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    case .hunk(let hunk, _):
                        hunkHeader(hunk)
                    case .row(let row, let path, _):
                        rowView(row, path: path)
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
                    model.toggleExpanded(file.id)
                } label: {
                    Image(systemName: model.isExpanded(file) ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            }
            Text(Self.headerText(file))
                .font(theme.font(.title, weight: .medium))
                .lineLimit(1)
            if let old = file.oldMode, let new = file.newMode {
                Text("mode \(old) \u{2192} \(new)")
                    .font(theme.font(.small))
                    .foregroundStyle(.secondary)
            }
            if isLarge {
                Text("\(file.lineCount) lines")
                    .font(theme.font(.small))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(theme.tokens.surfaceRaised.color)
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

    private func hunkHeader(_ hunk: RenderedHunk) -> some View {
        Text(hunk.header)
            .font(Font(theme.editorFont))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.tokens.surfaceSunken.color)
            // The gap the hunk's rows kept above them when they were wrapped in a stack (M23 23.11).
            .padding(.bottom, 2)
    }

    /// git R13b: one row per pair, both cells the height of the taller one, lines wrap.
    private func rowView(_ row: RenderedRow, path: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            cell(row.left, path: path)
            Divider()
            cell(row.right, path: path)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ cell: RenderedCell?, path: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(cell?.number ?? "")
                .font(Font(theme.editorFont))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 4)
            Text(cell?.text ?? AttributedString(" "))
                .font(Font(theme.editorFont))
                .textSelection(.enabled)
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cellBackground(cell?.kind))
        .contextMenu {
            // The left cell numbers the old file: a removed line is nowhere in the file the agent
            // would open, so only a line the file still has is offered (agents R10b).
            if let line = cell?.newNumber {
                Button("Send to Agent") { sendLine(path, line) }
            }
        }
    }

    private func cellBackground(_ kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .added: return Color(nsColor: theme.diffLineBackground(added: true))
        case .removed: return Color(nsColor: theme.diffLineBackground(added: false))
        case .context, nil: return .clear
        }
    }
}
