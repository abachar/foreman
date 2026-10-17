import Foundation

/// The breakpoints of a workspace (debug R4): per file, relative to the root, as lines.
///
/// A plain value with no window and no session in it: the feature keeps one, the tests drive it.
/// What the adapter said about each line (`verified`) lives beside the lines and is dropped with
/// the session.
nonisolated struct BreakpointStore: Equatable, Sendable {
    /// The `debug` section of `state.json` (debug R4): `{ "breakpoints": { "<relative path>": [lines] } }`.
    struct State: Codable, Equatable, Sendable {
        var breakpoints: [String: [Int]]
    }

    /// What one edit did to the lines of a text (debug R4: a breakpoint moves with the text).
    struct Edit: Equatable, Sendable {
        /// The 1-based line the edit starts on, in the text before the edit.
        var startLine: Int
        /// Line breaks the edit removed, and line breaks it put in.
        var removed: Int
        var inserted: Int
        /// Whole lines pushed down: a break inserted at the start of a line moves that line's content.
        var insertsWholeLines: Bool

        /// The edit of `oldLength` characters at `location` replaced by `replacement`, read against
        /// the line starts the text had **before** it. `nil` when no line break is involved, and for
        /// a whole-text replacement (a reload, a formatter) — the lines keep their numbers then.
        static func make(
            oldStarts: [Int], oldTextLength: Int, location: Int, oldLength: Int, replacement: String
        )
            -> Edit?
        {
            guard !(location == 0 && oldLength >= oldTextLength) else { return nil }
            let removed = oldStarts.count { $0 > location && $0 <= location + oldLength }
            let inserted = replacement.utf16.count { $0 == 0x0A }
            guard removed > 0 || inserted > 0 else { return nil }
            let startLine = IndentGuides.line(at: location, starts: oldStarts)
            return Edit(
                startLine: startLine, removed: removed, inserted: inserted,
                insertsWholeLines: oldLength == 0 && oldStarts[startLine - 1] == location && replacement.hasSuffix("\n")
            )
        }
    }

    /// Relative path → the lines, ascending, no duplicate.
    private(set) var lines: [String: [Int]] = [:]
    /// Relative path → line → whether the adapter verified it; empty without a session.
    private(set) var verified: [String: [Int: Bool]] = [:]

    init(state: State? = nil) {
        for (path, lines) in state?.breakpoints ?? [:] {
            let kept = Set(lines.filter { $0 > 0 }).sorted()
            if !kept.isEmpty {
                self.lines[path] = kept
            }
        }
    }

    var state: State {
        State(breakpoints: lines)
    }

    /// The key of a file in `state.json`; `nil` outside the root, where a tab takes no breakpoint.
    static func key(for url: URL, root: URL) -> String? {
        Workspace.contains(url, under: root) && url.standardizedFileURL != root.standardizedFileURL
            ? Workspace.persistedPath(for: url, root: root) : nil
    }

    /// The number of lines the editor shows for `text`.
    static func lineCount(of text: String) -> Int {
        max(1, text.utf8.count { $0 == 0x0A } + (text.hasSuffix("\n") ? 0 : 1))
    }

    mutating func toggle(_ line: Int, in path: String) {
        var current = lines[path] ?? []
        if let index = current.firstIndex(of: line) {
            current.remove(at: index)
        } else {
            current.append(line)
            current.sort()
        }
        set(current, in: path)
    }

    /// Restoration: a line past the end of the file is dropped. `true` when something went.
    @discardableResult
    mutating func drop(pastLine count: Int, in path: String) -> Bool {
        guard let current = lines[path], current.last.map({ $0 > count }) == true else { return false }
        set(current.filter { $0 <= count }, in: path)
        return true
    }

    /// The lines after an edit: the ones after it move, the ones whose line break it removed go.
    @discardableResult
    mutating func apply(_ edit: Edit, in path: String) -> Bool {
        guard let current = lines[path] else { return false }
        let anchor = edit.insertsWholeLines ? edit.startLine - 1 : edit.startLine
        let moved = current.compactMap { line -> Int? in
            guard line > anchor else { return line }
            guard line > anchor + edit.removed else { return nil }
            return line - edit.removed + edit.inserted
        }
        guard moved != current else { return false }
        set(moved, in: path)
        return true
    }

    private mutating func set(_ new: [Int], in path: String) {
        lines[path] = new.isEmpty ? nil : new
        verified[path] = nil
    }

    // MARK: - What the adapter said (debug R4)

    /// The adapter's answer to `setBreakpoints` for the `requested` lines of `path`.
    ///
    /// One entry per line in the same order; ignored when the lines changed since (a later request
    /// answers for them).
    mutating func record(_ response: DAPSetBreakpointsResponse, requested: [Int], in path: String) {
        guard lines[path] == requested else { return }
        verified[path] = Dictionary(
            uniqueKeysWithValues: requested.enumerated().map { index, line in
                (line, response.breakpoints.indices.contains(index) && response.breakpoints[index].verified)
            })
    }

    /// The session is over: every dot is hollow again.
    mutating func forgetVerification() {
        verified.removeAll()
    }

    /// The dots of one file: line → filled (verified) or hollow.
    func marks(in path: String) -> [Int: Bool] {
        Dictionary(uniqueKeysWithValues: (lines[path] ?? []).map { ($0, verified[path]?[$0] ?? false) })
    }

    /// The `setBreakpoints` of one file, with its absolute path.
    func file(_ path: String, root: URL) -> DAPSession.FileBreakpoints {
        DAPSession.FileBreakpoints(
            path: root.appending(path: path).standardizedFileURL.path(percentEncoded: false),
            lines: lines[path] ?? [])
    }

    /// Every file, in path order: what a session sends at its start.
    func files(root: URL) -> [DAPSession.FileBreakpoints] {
        lines.keys.sorted().map { file($0, root: root) }
    }
}
