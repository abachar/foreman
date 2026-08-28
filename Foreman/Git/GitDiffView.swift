import SwiftUI

/// The `git.diff` tab (git R13, R16): a header per file, numbered hunks, `+`/`−` tinted lines.
struct GitDiffView: View {
    let model: GitDiffModel
    let theme: ThemeService
    /// agents R10b: the line's context menu (side by side only: the inline column is one text).
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

    private func content(_ diff: GitDiff) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                // git R13b: side by side by default, inline on demand.
                Picker("Layout", selection: Bindable(model).isSideBySide) {
                    Image(systemName: "rectangle.split.2x1").tag(true)
                    Image(systemName: "list.bullet.rectangle").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Side by side / inline")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            theme.tokens.separator.color.frame(height: 1)
            files(diff)
        }
    }

    private func files(_ diff: GitDiff) -> some View {
        ScrollView(model.isSideBySide ? .vertical : [.vertical, .horizontal]) {
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
                                hunkView(hunk, path: file.path)
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

    private func hunkView(_ hunk: RenderedHunk, path: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(Font(theme.editorFont))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.tokens.surfaceSunken.color)
            if model.isSideBySide {
                // git R13b: one row per pair, both cells the height of the taller one, lines wrap.
                LazyVStack(spacing: 0) {
                    ForEach(hunk.rows) { row in
                        HStack(alignment: .top, spacing: 0) {
                            cell(row.left, path: path)
                            Divider()
                            cell(row.right, path: path)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    gutter(hunk.inline.numbers)
                    gutter(hunk.inlineNewNumbers)
                    code(hunk.inline.text)
                }
                .padding(.vertical, 2)
            }
        }
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
            if let line = cell.flatMap({ Int($0.number) }) {
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

    private func code(_ text: AttributedString) -> some View {
        Text(text)
            .font(Font(theme.editorFont))
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 8)
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
