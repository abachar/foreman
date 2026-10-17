import AppKit
import Foundation
import Observation
import SwiftUI
import os

/// The two grounds a diff line can have, read from the theme once per render.
nonisolated struct DiffTint: Sendable {
    let added: Color
    let removed: Color
}

/// git R13b: one side of a row; `nil` when nothing faces the other side.
nonisolated struct RenderedCell: Sendable {
    /// What the gutter shows: the old file's number on the left, the new one on the right.
    let number: String
    let text: AttributedString
    let kind: DiffLine.Kind
    /// The line in the file as it is now, `nil` for a removed line: what an agent can be pointed
    /// at (agents R10b).
    let newNumber: Int?
}

/// git R13b: one row of the side-by-side view.
nonisolated struct RenderedRow: Sendable, Identifiable {
    let id: Int
    let left: RenderedCell?
    let right: RenderedCell?
}

/// A hunk as the view draws it, side by side (git R13, R13b).
nonisolated struct RenderedHunk: Sendable, Identifiable {
    let id: String
    let header: String
    let rows: [RenderedRow]
}

/// git R13b, R16 (M23 23.11): the diff tab's rows, flat, so one lazy stack builds only what is near
/// the viewport — a lazy stack nested in a hunk's `VStack` was sized by its parent and built every row.
///
/// A hunk's id (`oldStart-newStart`) repeats across files (every new file is `0-1`), so the hunk and
/// row ids carry the file's path.
nonisolated enum DiffRow: Identifiable, Sendable {
    case file(FileDiff)
    /// git R16: the "binary, N KB → M KB" line of an open binary file.
    case binary(FileDiff)
    case hunk(RenderedHunk, path: String)
    case row(RenderedRow, path: String, hunk: String)

    var id: String {
        switch self {
        case .file(let file): "file:\(file.id)"
        case .binary(let file): "binary:\(file.id)"
        case .hunk(let hunk, let path): "hunk:\(path):\(hunk.id)"
        case .row(let row, let path, let hunk): "row:\(path):\(hunk):\(row.id)"
        }
    }
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
    private(set) var expandedFiles: Set<String> = []

    private let client: () async -> GitCLI?
    private let repo: GitRepo
    private let highlighter: Highlighter
    private let theme: ThemeService
    private var loading: Task<Void, Never>?
    private var refreshWatch: Task<Void, Never>?
    /// git R16: the folded files of a large diff being rendered because they were just unfolded.
    private var rendering: [String: Task<Void, Never>] = [:]

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
        for task in rendering.values {
            task.cancel()
        }
    }

    /// git R16: a file is shown open unless the diff is large and it was not opened by hand.
    func isExpanded(_ file: FileDiff) -> Bool {
        guard let diff, diff.isLarge else { return true }
        return expandedFiles.contains(file.id)
    }

    /// git R16: opens or folds a file of a large diff; a file opened for the first time is rendered
    /// now, not with the diff.
    func toggleExpanded(_ id: String) {
        guard !expandedFiles.contains(id) else {
            expandedFiles.remove(id)
            return
        }
        expandedFiles.insert(id)
        guard let diff, diff.isLarge, rendered[id] == nil, rendering[id] == nil,
            let file = diff.files.first(where: { $0.id == id && !$0.isBinary })
        else { return }
        rendering[id] = Task { [weak self] in
            await self?.render([file], previous: nil)
            // A load cancelled this task and may have started another for the same file.
            guard !Task.isCancelled else { return }
            self?.rendering[id] = nil
        }
    }

    /// git R16: the text files a load renders, in diff order.
    ///
    /// A diff under the threshold renders every one; a large diff only the files opened by hand,
    /// the others when they are unfolded (audit 2026-10-17 M2).
    nonisolated static func filesToRender(_ diff: GitDiff, expanded: Set<String>) -> [FileDiff] {
        diff.files.filter { !$0.isBinary && (!diff.isLarge || expanded.contains($0.id)) }
    }

    /// git R13b, R16 (M23 23.11): the tab's flat rows, in diff order.
    ///
    /// Every file's header, then, if it is open, its binary line or its rendered hunks — each hunk's
    /// header then its rows. A folded file, or one not rendered yet, contributes its header only.
    nonisolated static func rows(
        of diff: GitDiff, expanded: (FileDiff) -> Bool, rendered: [String: [RenderedHunk]]
    ) -> [DiffRow] {
        var rows: [DiffRow] = []
        for file in diff.files {
            rows.append(.file(file))
            guard expanded(file) else { continue }
            if file.isBinary {
                rows.append(.binary(file))
                continue
            }
            for hunk in rendered[file.id] ?? [] {
                rows.append(.hunk(hunk, path: file.path))
                rows.append(contentsOf: hunk.rows.map { .row($0, path: file.path, hunk: hunk.id) })
            }
        }
        return rows
    }

    /// git R17: a refresh renders again only the files whose hunks changed; an unchanged file keeps
    /// what is on screen, so a diff an agent is writing to does not flicker (audit 2026-10-17 M2).
    nonisolated static func needsRender(_ file: FileDiff, previous: GitDiff?, isRendered: Bool) -> Bool {
        !isRendered || previous?.files.first(where: { $0.id == file.id }) != file
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
                let previous = diff
                diff = loaded
                error = nil
                // What the previous diff was still rendering on demand is dropped.
                for task in rendering.values {
                    task.cancel()
                }
                rendering = [:]
                // A changed file keeps its old hunks until the new ones replace them; a file that is
                // gone, binary now, or folded loses them (a folded one is rendered when unfolded).
                let files = Self.filesToRender(loaded, expanded: expandedFiles)
                let kept = Set(files.map(\.id))
                rendered = rendered.filter { kept.contains($0.key) }
                binarySizes = await Self.sizes(of: loaded, payload: payload, client: client, repo: repo)
                await render(files, previous: previous)
            } catch {
                // A load the next one superseded: its cancellation is not a failure to show, and
                // the spinner it would clear is the one the load that replaced it put up.
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
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
        // git R36b: a range's old side is the merge base, read once per load.
        var mergeBase: String?
        if case .range(let base, let head) = payload.source, diff.files.contains(where: \.isBinary) {
            mergeBase = try? await client.run(GitCommand.mergeBase(base, head)).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for file in diff.files where file.isBinary {
            let oldObject =
                payload.oldObject(for: file) ?? mergeBase.flatMap { sha in file.oldPath.map { "\(sha):\($0)" } }
            async let old = objectSize(oldObject, client: client)
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

    /// Highlights each file once (the grammar from its name, editor R12), then colors the lines;
    /// each file is shown as soon as it is rendered, not when the whole diff is (audit 2026-10-17 M2).
    /// `previous` is the diff on screen before a refresh, `nil` for a file rendered on demand.
    private func render(_ files: [FileDiff], previous: GitDiff?) async {
        let interval = Perf.signposter.beginInterval("diff.render", id: Perf.signposter.makeSignpostID())
        defer { Perf.signposter.endInterval("diff.render", interval) }
        // The theme is read once, here, so the slicing below needs nothing from the main actor.
        let tint = DiffTint(
            added: Color(nsColor: theme.diffLineBackground(added: true)),
            removed: Color(nsColor: theme.diffLineBackground(added: false)))
        for file in files where Self.needsRender(file, previous: previous, isRendered: rendered[file.id] != nil) {
            let code = file.hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")
            let language = Language.forFile(URL(filePath: file.path))
            let highlighted = language == nil ? nil : await highlighter.highlight(code, language: language ?? .json)
            guard !Task.isCancelled else { return }
            let hunks = await Self.render(file, highlighted: highlighted, tint: tint)
            // A load that superseded this one has reset `rendered`: nothing of this diff goes in.
            guard !Task.isCancelled else { return }
            rendered[file.id] = hunks
            // One event per file shows which file of a large diff holds the time (audit 2026-10-17 M2).
            Perf.signposter.emitEvent("diff.render.file")
        }
    }

    /// The highlighted text recoloured for SwiftUI and sliced back per line, the `+`/`−` tint,
    /// then the side-by-side rows.
    ///
    /// Off the main actor: a large diff builds an `AttributedString` per line, and that ran
    /// between the user and every frame (audit M3b); so does the recolouring (audit 2026-10-17 M2).
    @concurrent
    private static func render(
        _ file: FileDiff, highlighted: AttributedString?, tint: DiffTint
    ) async
        -> [RenderedHunk]
    {
        var highlighted = highlighted
        if let neon = highlighted {
            highlighted = await Highlighter.withSwiftUIColors(neon)
        }
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
                case .added: piece.backgroundColor = tint.added
                case .removed: piece.backgroundColor = tint.removed
                }
                if line.hasNoNewline {
                    piece.append(AttributedString(" \u{23CE}\u{0338}"))
                }
                pieces.append(piece)
            }
            let pieceOf = Dictionary(zip(hunk.lines.indices, pieces)) { first, _ in first }
            let indexOf = Dictionary(hunk.lines.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
            let rows = SideBySideRow.rows(of: hunk).enumerated().map { offset, row in
                RenderedRow(
                    id: offset,
                    left: row.left.flatMap { line in
                        indexOf[line].flatMap { pieceOf[$0] }.map {
                            RenderedCell(
                                number: line.oldNumber.map(String.init) ?? "", text: $0, kind: line.kind,
                                newNumber: line.newNumber)
                        }
                    },
                    right: row.right.flatMap { line in
                        indexOf[line].flatMap { pieceOf[$0] }.map {
                            RenderedCell(
                                number: line.newNumber.map(String.init) ?? "", text: $0, kind: line.kind,
                                newNumber: line.newNumber)
                        }
                    })
            }
            result.append(
                RenderedHunk(id: hunk.id, header: hunk.header, rows: rows))
        }
        return result
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
        // The merge base, which the model reads at each load.
        case .range: return nil
        }
    }

    nonisolated func newObject(for file: FileDiff) -> String? {
        guard let path = file.newPath else { return nil }
        switch source {
        case .workingTree, .session: return nil
        case .range(_, let head): return "\(head):\(path)"
        case .staged: return ":\(path)"
        case .commit(let sha, _), .commitFile(let sha, _, _): return "\(sha):\(path)"
        }
    }

    nonisolated var newObjectIsWorktree: Bool {
        switch source {
        case .workingTree, .session: return true
        case .staged, .commit, .commitFile, .range: return false
        }
    }
}
