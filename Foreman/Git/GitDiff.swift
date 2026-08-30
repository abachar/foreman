import Foundation

/// One line of a hunk (git R13).
nonisolated struct DiffLine: Hashable, Sendable {
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

/// git R13b: one row of the side-by-side view; a side is `nil` when nothing faces the other.
nonisolated struct SideBySideRow: Equatable, Sendable {
    let left: DiffLine?
    let right: DiffLine?

    /// Context on both sides; a run of removed lines faces the run of added lines that follows it,
    /// index by index, the longer run overflowing alone.
    static func rows(of hunk: Hunk) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var removed: [DiffLine] = []
        var added: [DiffLine] = []
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                rows.append(
                    SideBySideRow(
                        left: index < removed.count ? removed[index] : nil,
                        right: index < added.count ? added[index] : nil))
            }
            removed = []
            added = []
        }
        for line in hunk.lines {
            switch line.kind {
            case .context:
                flush()
                rows.append(SideBySideRow(left: line, right: line))
            case .removed:
                if !added.isEmpty {
                    flush()
                }
                removed.append(line)
            case .added:
                added.append(line)
            }
        }
        flush()
        return rows
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
                current?.oldPath = unquoted(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                current?.newPath = unquoted(line.dropFirst("rename to ".count))
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

    /// The `a/x b/y` of a `diff --git` line, whether or not either side is quoted.
    ///
    /// Neither side is delimited: an unquoted path may hold spaces, so the split is a ` b/` that
    /// leaves an `a/` behind, and the pair naming the same path twice wins — everything but a
    /// rename does. `---`/`+++`, which end at a tab, correct whatever stays ambiguous.
    private static func gitPaths(_ rest: Substring) -> (old: String, new: String) {
        // A quoted second path starts at the ` "` that opens the trailing quote; a quote inside a
        // path is written `\"`, never after a space.
        if rest.hasSuffix("\""), let separator = rest.range(of: " \"", options: .backwards) {
            return (stripped(rest[..<separator.lowerBound]), stripped(rest[separator.lowerBound...].dropFirst()))
        }
        var candidates: [(old: String, new: String)] = []
        var start = rest.startIndex
        while let separator = rest.range(of: " b/", range: start..<rest.endIndex) {
            let left = rest[..<separator.lowerBound]
            if left.hasPrefix("a/") || left.hasPrefix("\"a/") {
                candidates.append((stripped(left), stripped(rest[separator.lowerBound...].dropFirst())))
            }
            start = separator.upperBound
        }
        return candidates.first { $0.old == $0.new } ?? candidates.first ?? (old: String(rest), new: String(rest))
    }

    /// `a/path`, `b/path`, or `/dev/null`; git ends the line with a tab when the path has a space.
    private static func filePath(_ rest: Substring) -> String? {
        let text = rest.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? String(rest)
        guard text != "/dev/null" else { return nil }
        return stripped(Substring(text))
    }

    /// One side of a `diff --git` line: the quoting off, then the `a/`/`b/` prefix.
    private static func stripped(_ path: Substring) -> String {
        let text = unquoted(path)
        return text.hasPrefix("a/") || text.hasPrefix("b/") ? String(text.dropFirst(2)) : text
    }

    /// A path as git prints it (git R27).
    ///
    /// It is wrapped in quotes and C-escaped as soon as it holds a quote, a backslash or a control
    /// character — and, while `core.quotepath` is on, every non-ASCII byte as `\###` octals. The
    /// read commands turn that option off; the octal case stays for a diff produced elsewhere.
    private static func unquoted(_ path: Substring) -> String {
        guard path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") else { return String(path) }
        let escaped = Array(path.dropFirst().dropLast().utf8)
        var bytes: [UInt8] = []
        var index = escaped.startIndex
        while index < escaped.endIndex {
            let byte = escaped[index]
            index += 1
            guard byte == UInt8(ascii: "\\"), index < escaped.endIndex else {
                bytes.append(byte)
                continue
            }
            let escape = escaped[index]
            index += 1
            if let literal = literalEscapes[escape] {
                bytes.append(literal)
            } else if octalDigits.contains(escape) {
                // Three octal digits at most, one byte of the path's UTF-8.
                var value = Int(escape - UInt8(ascii: "0"))
                var digits = 1
                while digits < 3, index < escaped.endIndex, octalDigits.contains(escaped[index]) {
                    value = value * 8 + Int(escaped[index] - UInt8(ascii: "0"))
                    index += 1
                    digits += 1
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            } else {
                // `\\` and `\"`, and anything git may add later, stand for themselves.
                bytes.append(escape)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static let literalEscapes: [UInt8: UInt8] = [
        UInt8(ascii: "a"): 0x07, UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0c, UInt8(ascii: "n"): 0x0a,
        UInt8(ascii: "r"): 0x0d, UInt8(ascii: "t"): 0x09, UInt8(ascii: "v"): 0x0b,
    ]
    private static let octalDigits = UInt8(ascii: "0")...UInt8(ascii: "7")

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
        /// git R31: the working tree against the tree snapshotted when an agent started.
        case session(base: String, title: String)

        var isImmutable: Bool {
            switch self {
            case .workingTree, .staged, .session: return false
            case .commit, .commitFile: return true
            }
        }

        var path: String? {
            switch self {
            case .workingTree(let path), .staged(let path), .commitFile(_, _, let path): return path
            case .commit, .session: return nil
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
        case .session(_, let title): return "\(title) · session"
        }
    }

    /// git R14, R27, R31: the command; `show` prints the subject on its first line (read by the
    /// model); a session diff compares its base with `currentTree`, rebuilt by the model.
    func arguments(currentTree: String? = nil) -> [String] {
        // git R27: `core.quotepath=false` keeps a non-ASCII path as its own bytes instead of octal
        // escapes. It says how git writes what it is asked to read, never what git does to the repo.
        let config = ["-c", "core.quotepath=false"]
        let options = ["--no-color", "--no-ext-diff", "-M"]
        // A merge commit has no diff of its own: `show` prints a combined `diff --cc`, which is not
        // a unified diff. `-m --first-parent` asks for what the merge brought to the branch it was
        // made on, in the ordinary format; on a commit with one parent it changes nothing.
        let show = ["show", "-m", "--first-parent", "--format=%s"]
        switch source {
        case .workingTree(let path): return config + ["diff"] + options + ["--", path]
        case .staged(let path): return config + ["diff", "--cached"] + options + ["--", path]
        case .commit(let sha, _): return config + show + options + [sha, "--"]
        case .commitFile(let sha, _, let path): return config + show + options + [sha, "--", path]
        case .session(let base, _): return config + ["diff"] + options + [base, currentTree ?? base, "--"]
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
