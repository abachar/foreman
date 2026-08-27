import Foundation

/// One line of a hunk (git R13).
nonisolated struct DiffLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case added
        case removed
    }

    let kind: Kind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
    /// `\ No newline at end of file` followed this line.
    var hasNoNewline = false
}

/// A `@@ -a,b +c,d @@` block (git R13).
nonisolated struct Hunk: Equatable, Sendable, Identifiable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    /// What follows the second `@@`, often the enclosing function.
    let heading: String
    var lines: [DiffLine]

    var id: String {
        "\(oldStart)-\(newStart)"
    }

    var header: String {
        "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" + (heading.isEmpty ? "" : " \(heading)")
    }
}

/// One file of a diff (git R13, R16).
nonisolated struct FileDiff: Equatable, Sendable, Identifiable {
    /// `nil` for a file that did not exist (an addition).
    var oldPath: String?
    /// `nil` for a deleted file.
    var newPath: String?
    var oldMode: String?
    var newMode: String?
    var isBinary = false
    var hunks: [Hunk] = []

    var id: String {
        path
    }

    var path: String {
        newPath ?? oldPath ?? ""
    }

    var isRename: Bool {
        oldPath != nil && newPath != nil && oldPath != newPath
    }

    var lineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count }
    }

    /// Edge cases: an untracked file has no diff; it is shown as one hunk of added lines.
    static func added(path: String, content: String) -> FileDiff {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        let diffLines = lines.enumerated().map { index, text in
            DiffLine(kind: .added, text: text, oldNumber: nil, newNumber: index + 1)
        }
        return FileDiff(
            oldPath: nil, newPath: path,
            hunks: lines.isEmpty
                ? []
                : [Hunk(oldStart: 0, oldCount: 0, newStart: 1, newCount: lines.count, heading: "", lines: diffLines)])
    }
}

/// What a `git.diff` tab shows (git R13, R14).
nonisolated struct GitDiff: Equatable, Sendable {
    /// git R16: over this many lines, every file starts collapsed.
    static let collapseThreshold = 5000

    var files: [FileDiff]

    var lineCount: Int {
        files.reduce(0) { $0 + $1.lineCount }
    }

    var isLarge: Bool {
        lineCount > Self.collapseThreshold
    }
}

/// `diff --no-color --no-ext-diff -M` (and `show`) → `GitDiff` (git R13, R27).
///
/// A minimal unified-diff reader, ~120 lines: nothing in the retained libraries parses diffs.
nonisolated enum DiffParser {
    static func parse(_ data: Data) -> GitDiff {
        parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> GitDiff {
        var files: [FileDiff] = []
        var current: FileDiff?
        var hunk: Hunk?
        var oldLine = 0
        var newLine = 0

        func closeHunk() {
            if let finished = hunk {
                current?.hunks.append(finished)
            }
            hunk = nil
        }
        func closeFile() {
            closeHunk()
            if let finished = current {
                files.append(finished)
            }
            current = nil
        }

        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // The output ends with a newline: what follows it is not a line.
        if rawLines.last == "" {
            rawLines.removeLast()
        }
        for rawLine in rawLines {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                closeFile()
                current = FileDiff()
                let paths = gitPaths(line.dropFirst("diff --git ".count))
                current?.oldPath = paths.old
                current?.newPath = paths.new
                continue
            }
            guard current != nil else { continue }
            if let header = hunkHeader(line) {
                closeHunk()
                hunk = header
                oldLine = header.oldStart
                newLine = header.newStart
                continue
            }
            if hunk != nil {
                switch line.first {
                case " ":
                    hunk?.lines.append(
                        DiffLine(kind: .context, text: String(line.dropFirst()), oldNumber: oldLine, newNumber: newLine)
                    )
                    oldLine += 1
                    newLine += 1
                case "+":
                    hunk?.lines.append(
                        DiffLine(kind: .added, text: String(line.dropFirst()), oldNumber: nil, newNumber: newLine))
                    newLine += 1
                case "-":
                    hunk?.lines.append(
                        DiffLine(kind: .removed, text: String(line.dropFirst()), oldNumber: oldLine, newNumber: nil))
                    oldLine += 1
                case "\\":
                    if let last = hunk?.lines.indices.last {
                        hunk?.lines[last].hasNoNewline = true
                    }
                default:
                    // An empty context line is written as a single space; a bare empty line is one too.
                    if line.isEmpty {
                        hunk?.lines.append(DiffLine(kind: .context, text: "", oldNumber: oldLine, newNumber: newLine))
                        oldLine += 1
                        newLine += 1
                    }
                }
                continue
            }
            if line.hasPrefix("--- ") {
                current?.oldPath = filePath(line.dropFirst(4))
            } else if line.hasPrefix("+++ ") {
                current?.newPath = filePath(line.dropFirst(4))
            } else if line.hasPrefix("rename from ") {
                current?.oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                current?.newPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("old mode ") {
                current?.oldMode = String(line.dropFirst("old mode ".count))
            } else if line.hasPrefix("new mode ") {
                current?.newMode = String(line.dropFirst("new mode ".count))
            } else if line.hasPrefix("new file mode ") {
                current?.oldPath = nil
            } else if line.hasPrefix("deleted file mode ") {
                current?.newPath = nil
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                current?.isBinary = true
            }
        }
        closeFile()
        return GitDiff(files: files)
    }

    /// `a/x b/y` of the `diff --git` line; a path with spaces is read from `---`/`+++` afterwards.
    private static func gitPaths(_ rest: Substring) -> (old: String, new: String) {
        let parts = rest.split(separator: " ")
        guard parts.count == 2 else { return (String(rest), String(rest)) }
        return (stripped(parts[0]), stripped(parts[1]))
    }

    /// `a/path`, `b/path`, or `/dev/null`; a quoted path keeps its quotes off.
    private static func filePath(_ rest: Substring) -> String? {
        let text = rest.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? String(rest)
        guard text != "/dev/null" else { return nil }
        return stripped(Substring(text))
    }

    private static func stripped(_ path: Substring) -> String {
        var text = path
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = text.dropFirst().dropLast()
        }
        if text.hasPrefix("a/") || text.hasPrefix("b/") {
            text = text.dropFirst(2)
        }
        return String(text)
    }

    /// `@@ -a[,b] +c[,d] @@[ heading]`.
    private static func hunkHeader(_ line: String) -> Hunk? {
        guard line.hasPrefix("@@ ") else { return nil }
        let body = line.dropFirst(3)
        guard let end = body.range(of: " @@") else { return nil }
        let ranges = body[..<end.lowerBound].split(separator: " ")
        guard ranges.count == 2, let old = range(ranges[0], sign: "-"), let new = range(ranges[1], sign: "+") else {
            return nil
        }
        let heading = body[end.upperBound...].trimmingCharacters(in: .whitespaces)
        return Hunk(
            oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count, heading: heading,
            lines: [])
    }

    private static func range(_ text: Substring, sign: Character) -> (start: Int, count: Int)? {
        guard text.first == sign else { return nil }
        let numbers = text.dropFirst().split(separator: ",").compactMap { Int($0) }
        guard let start = numbers.first else { return nil }
        return (start, numbers.count > 1 ? numbers[1] : 1)
    }
}

/// What a `git.diff` tab is about (git R14), persisted as the tab's payload (layout R28).
nonisolated struct GitDiffPayload: Codable, Equatable, Sendable {
    enum Source: Codable, Equatable, Sendable {
        /// `diff -- <path>`, refreshed with the repo (R17).
        case workingTree(path: String)
        /// `diff --cached -- <path>`.
        case staged(path: String)
        /// `show <sha>`, immutable (R17).
        case commit(sha: String, subject: String)
        case commitFile(sha: String, subject: String, path: String)

        var isImmutable: Bool {
            switch self {
            case .workingTree, .staged: return false
            case .commit, .commitFile: return true
            }
        }

        var path: String? {
            switch self {
            case .workingTree(let path), .staged(let path), .commitFile(_, _, let path): return path
            case .commit: return nil
            }
        }
    }

    /// `GitRepo.id`.
    let repo: String
    let source: Source

    /// git R14: `path (working tree)` / `path (staged)` / `abc1234 subject`.
    var title: String {
        switch source {
        case .workingTree(let path): return "\(path) (working tree)"
        case .staged(let path): return "\(path) (staged)"
        case .commit(let sha, let subject): return "\(sha.prefix(7)) \(subject)"
        case .commitFile(let sha, _, let path): return "\(path) @ \(sha.prefix(7))"
        }
    }

    /// git R14, R27: the command; `show` prints the subject on its first line (read by the model).
    var arguments: [String] {
        let options = ["--no-color", "--no-ext-diff", "-M"]
        switch source {
        case .workingTree(let path): return ["diff"] + options + ["--", path]
        case .staged(let path): return ["diff", "--cached"] + options + ["--", path]
        case .commit(let sha, _): return ["show", "--format=%s"] + options + [sha, "--"]
        case .commitFile(let sha, _, let path): return ["show", "--format=%s"] + options + [sha, "--", path]
        }
    }

    func encoded() -> String {
        // A two-field Codable struct always encodes.
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }

    static func decode(_ payload: String) -> GitDiffPayload? {
        try? JSONDecoder().decode(GitDiffPayload.self, from: Data(payload.utf8))
    }
}
