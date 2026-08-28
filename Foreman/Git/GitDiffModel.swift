import AppKit
import Foundation
import Observation
import SwiftUI

/// A column of text with its gutter, as the view draws it (git R13).
nonisolated struct RenderedColumn: Sendable {
    let numbers: String
    let text: AttributedString
}

/// git R13b: one side of a row; `nil` when nothing faces the other side.
nonisolated struct RenderedCell: Sendable {
    let number: String
    let text: AttributedString
    let kind: DiffLine.Kind
}

/// git R13b: one row of the side-by-side view.
nonisolated struct RenderedRow: Sendable, Identifiable {
    let id: Int
    let left: RenderedCell?
    let right: RenderedCell?
}

/// A hunk as the view draws it: inline, or side by side (git R13, R13b).
nonisolated struct RenderedHunk: Sendable, Identifiable {
    let id: String
    let header: String
    let inline: RenderedColumn
    let inlineNewNumbers: String
    let rows: [RenderedRow]
}

/// What one `git.diff` tab shows (git R13, R14, R16, R17).
@Observable
@MainActor
final class GitDiffModel {
    let payload: GitDiffPayload
    private(set) var diff: GitDiff?
    private(set) var rendered: [String: [RenderedHunk]] = [:]
    private(set) var binarySizes: [String: String] = [:]
    private(set) var error: GitError?
    private(set) var isLoading = false
    /// git R16: the files opened by hand in a large diff.
    var expandedFiles: Set<String> = []
    /// git R13b: side by side by default, inline on demand.
    var isSideBySide = true

    private let client: () async -> GitCLI?
    private let repo: GitRepo
    private let highlighter: Highlighter
    private let theme: ThemeService
    private var loading: Task<Void, Never>?
    private var refreshWatch: Task<Void, Never>?

    init(
        payload: GitDiffPayload, client: @escaping () async -> GitCLI?, repo: GitRepo, highlighter: Highlighter,
        theme: ThemeService,
        statusChanges: AsyncStream<GitStatusChange>?
    ) {
        self.payload = payload
        self.client = client
        self.repo = repo
        self.highlighter = highlighter
        self.theme = theme
        // git R17: the worktree and index diffs follow the repo; a commit's diff never changes.
        if let statusChanges, !payload.source.isImmutable {
            refreshWatch = Task { [weak self] in
                for await change in statusChanges where change.repo.id == payload.repo {
                    self?.load()
                }
            }
        }
    }

    isolated deinit {
        loading?.cancel()
        refreshWatch?.cancel()
    }

    /// git R16: a file is shown open unless the diff is large and it was not opened by hand.
    func isExpanded(_ file: FileDiff) -> Bool {
        guard let diff, diff.isLarge else { return true }
        return expandedFiles.contains(file.id)
    }

    func load() {
        loading?.cancel()
        isLoading = true
        loading = Task { [weak self] in
            guard let self else { return }
            do throws(GitError) {
                guard let client = await client() else { throw .gitNotFound }
                let loaded = try await Self.fetch(payload, client: client, repo: repo)
                guard !Task.isCancelled else { return }
                diff = loaded
                error = nil
                binarySizes = await Self.sizes(of: loaded, payload: payload, client: client, repo: repo)
                await render(loaded)
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    /// The diff of the payload; an untracked file is synthesized from its content (edge cases).
    @concurrent
    private static func fetch(
        _ payload: GitDiffPayload, client: GitCLI, repo: GitRepo
    ) async throws(GitError) -> GitDiff {
        // git R31: the current tree is rebuilt on every refresh.
        let currentTree: String? =
            if case .session = payload.source { try await client.snapshotTree() } else { nil }
        let output = try await client.run(payload.arguments(currentTree: currentTree))
        var diff = DiffParser.parse(output.stdout)
        if case .workingTree(let path) = payload.source, diff.files.isEmpty,
            let content = try? String(contentsOf: repo.url.appending(path: path), encoding: .utf8)
        {
            diff.files = [FileDiff.added(path: path, content: content)]
        }
        return diff
    }

    /// git R16: "binary, N KB → M KB" from the object sizes; a side without an object reads as 0.
    @concurrent
    private static func sizes(
        of diff: GitDiff, payload: GitDiffPayload, client: GitCLI, repo: GitRepo
    ) async
        -> [String: String]
    {
        var result: [String: String] = [:]
        for file in diff.files where file.isBinary {
            async let old = objectSize(payload.oldObject(for: file), client: client)
            async let new =
                payload.newObjectIsWorktree
                ? diskSize(repo.url.appending(path: file.path))
                : objectSize(payload.newObject(for: file), client: client)
            result[file.id] = Self.binaryText(old: await old, new: await new)
        }
        return result
    }

    private static func objectSize(_ object: String?, client: GitCLI) async -> Int {
        guard let object, let output = try? await client.run(["cat-file", "-s", object]) else { return 0 }
        return Int(output.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func diskSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    nonisolated static func binaryText(old: Int, new: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return
            "binary, \(formatter.string(fromByteCount: Int64(old))) \u{2192} \(formatter.string(fromByteCount: Int64(new)))"
    }

    // MARK: - Rendering (git R13)

    /// Highlights each file once (the grammar from its name, editor R12), then colors the lines.
    private func render(_ diff: GitDiff) async {
        var rendered: [String: [RenderedHunk]] = [:]
        for file in diff.files where !file.isBinary {
            let code = file.hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")
            let language = Language.forFile(URL(filePath: file.path))
            let highlighted = language == nil ? nil : await highlighter.highlight(code, language: language ?? .json)
            guard !Task.isCancelled else { return }
            rendered[file.id] = Self.render(file, highlighted: highlighted, theme: theme)
        }
        self.rendered = rendered
    }

    /// The highlighted text sliced back per line, the `+`/`−` tint, then both layouts.
    private static func render(_ file: FileDiff, highlighted: AttributedString?, theme: ThemeService) -> [RenderedHunk]
    {
        var cursor = highlighted?.startIndex
        var result: [RenderedHunk] = []
        for hunk in file.hunks {
            var pieces: [AttributedString] = []
            for line in hunk.lines {
                var piece: AttributedString
                if let highlighted, let start = cursor {
                    let end = highlighted.characters.index(start, offsetBy: line.text.count)
                    piece = AttributedString(highlighted[start..<end])
                    cursor = end < highlighted.endIndex ? highlighted.characters.index(after: end) : end
                } else {
                    piece = AttributedString(line.text)
                }
                switch line.kind {
                case .context: break
                case .added: piece.backgroundColor = Color(nsColor: theme.diffLineBackground(added: true))
                case .removed: piece.backgroundColor = Color(nsColor: theme.diffLineBackground(added: false))
                }
                if line.hasNoNewline {
                    piece.append(AttributedString(" \u{23CE}\u{0338}"))
                }
                pieces.append(piece)
            }
            let inline = column(hunk.lines, pieces: pieces, number: \.oldNumber)
            let pieceOf = Dictionary(zip(hunk.lines.indices, pieces)) { first, _ in first }
            let indexOf = Dictionary(hunk.lines.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
            let rows = SideBySideRow.rows(of: hunk).enumerated().map { offset, row in
                RenderedRow(
                    id: offset,
                    left: row.left.flatMap { line in
                        indexOf[line].flatMap { pieceOf[$0] }.map {
                            RenderedCell(number: line.oldNumber.map(String.init) ?? "", text: $0, kind: line.kind)
                        }
                    },
                    right: row.right.flatMap { line in
                        indexOf[line].flatMap { pieceOf[$0] }.map {
                            RenderedCell(number: line.newNumber.map(String.init) ?? "", text: $0, kind: line.kind)
                        }
                    })
            }
            result.append(
                RenderedHunk(
                    id: hunk.id, header: hunk.header, inline: inline,
                    inlineNewNumbers: hunk.lines.map { $0.newNumber.map(String.init) ?? "" }.joined(separator: "\n"),
                    rows: rows))
        }
        return result
    }

    private static func column(
        _ lines: [DiffLine], pieces: [AttributedString], number: KeyPath<DiffLine, Int?>
    )
        -> RenderedColumn
    {
        var text = AttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                text.append(AttributedString("\n"))
            }
            text.append(piece)
        }
        return RenderedColumn(
            numbers: lines.map { $0[keyPath: number].map(String.init) ?? "" }.joined(separator: "\n"), text: text)
    }
}

extension GitDiffPayload {
    /// The object holding the old side of `file`, as `cat-file` names it; `nil` when there is none.
    nonisolated func oldObject(for file: FileDiff) -> String? {
        guard let path = file.oldPath else { return nil }
        switch source {
        case .workingTree: return ":\(path)"
        case .staged: return "HEAD:\(path)"
        case .commit(let sha, _), .commitFile(let sha, _, _): return "\(sha)^:\(path)"
        case .session(let base, _): return "\(base):\(path)"
        }
    }

    nonisolated func newObject(for file: FileDiff) -> String? {
        guard let path = file.newPath else { return nil }
        switch source {
        case .workingTree, .session: return nil
        case .staged: return ":\(path)"
        case .commit(let sha, _), .commitFile(let sha, _, _): return "\(sha):\(path)"
        }
    }

    nonisolated var newObjectIsWorktree: Bool {
        switch source {
        case .workingTree, .session: return true
        case .staged, .commit, .commitFile: return false
        }
    }
}
