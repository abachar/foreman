import Foundation

/// One letter of the `XY` pair of `--porcelain=v2` (git R27).
nonisolated enum GitChange: Character, Equatable, Sendable {
    case unmodified = "."
    case modified = "M"
    case typeChanged = "T"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case unmerged = "U"
    case untracked = "?"
    case ignored = "!"
}

/// What leaves `Git/` (git R5): the status of one path, as the explorer colours it.
nonisolated enum GitFileStatus: Equatable, Sendable {
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case ignored
    case conflicted
}

/// One record of `status --porcelain=v2 -z` (git R6, R27).
nonisolated struct GitStatusEntry: Equatable, Sendable, Identifiable {
    /// Relative to the repo, `/`-separated; a name that is not UTF-8 is decoded with replacements.
    let path: String
    /// A rename or copy: where the entry comes from.
    let originalPath: String?
    let index: GitChange
    let worktree: GitChange
    let isConflict: Bool

    var id: String {
        path
    }

    init(path: String, originalPath: String? = nil, index: GitChange, worktree: GitChange, isConflict: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.index = index
        self.worktree = worktree
        self.isConflict = isConflict
    }

    var isUntracked: Bool {
        index == .untracked
    }

    /// git R5: the worktree side wins when both are modified (`MM` shows as modified).
    var fileStatus: GitFileStatus {
        if isConflict {
            return .conflicted
        }
        switch (index, worktree) {
        case (.untracked, _): return .untracked
        case (.ignored, _): return .ignored
        case (_, .unmodified): return Self.fileStatus(of: index)
        case (.renamed, _), (.copied, _): return .renamed
        case (.added, _): return .added
        default: return Self.fileStatus(of: worktree)
        }
    }

    private static func fileStatus(of change: GitChange) -> GitFileStatus {
        switch change {
        case .added: return .added
        case .deleted: return .deleted
        case .renamed, .copied: return .renamed
        case .untracked: return .untracked
        case .ignored: return .ignored
        case .unmerged: return .conflicted
        case .unmodified, .modified, .typeChanged: return .modified
        }
    }
}

/// git R9: what `.git/` says is in progress.
nonisolated enum GitOperation: Equatable, Sendable {
    case merging
    case rebasing
    case cherryPicking

    /// Read off the git directory's marker files; disk IO, never on the main actor.
    static func current(inGitDirectory directory: URL) -> GitOperation? {
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
        }
        if exists("MERGE_HEAD") {
            return .merging
        }
        if exists("rebase-merge") || exists("rebase-apply") {
            return .rebasing
        }
        if exists("CHERRY_PICK_HEAD") {
            return .cherryPicking
        }
        return nil
    }
}

/// The state of one repo (git R2, R6).
nonisolated struct GitStatus: Equatable, Sendable {
    enum Head: Equatable, Sendable {
        case branch(String)
        /// The short sha.
        case detached(String)
        /// Edge cases: no commit yet; committing is possible.
        case unborn(String?)
    }

    var head: Head
    var upstream: String?
    var ahead = 0
    var behind = 0
    var operation: GitOperation?
    var entries: [GitStatusEntry]

    static let empty = GitStatus(head: .unborn(nil), entries: [])

    /// git R5: the table the explorer and the quick open receive.
    var fileStatuses: [String: GitFileStatus] {
        Dictionary(entries.map { ($0.path, $0.fileStatus) }) { first, _ in first }
    }
}

/// `status --porcelain=v2 -z --branch` → `GitStatus` (git R27).
///
/// Records are NUL-terminated; the fields before the path are ASCII, the path is raw bytes. A
/// rename (`2`) carries its origin as the next record.
nonisolated enum StatusParser {
    static func parse(_ data: Data) -> GitStatus {
        var status = GitStatus.empty
        var oid: String?
        var isDetached = false
        var branch: String?
        var records = data.split(separator: 0, omittingEmptySubsequences: true).makeIterator()
        while let record = records.next() {
            guard let first = record.first else { continue }
            switch first {
            case UInt8(ascii: "#"):
                let line = String(decoding: record, as: UTF8.self)
                let parts = line.split(separator: " ", maxSplits: 2)
                guard parts.count == 3 else { continue }
                switch parts[1] {
                case "branch.oid": oid = parts[2] == "(initial)" ? nil : String(parts[2])
                case "branch.head":
                    isDetached = parts[2] == "(detached)"
                    branch = isDetached ? nil : String(parts[2])
                case "branch.upstream": status.upstream = String(parts[2])
                case "branch.ab":
                    let counts = parts[2].split(separator: " ")
                    status.ahead = counts.first.flatMap { Int($0.dropFirst()) } ?? 0
                    status.behind = counts.dropFirst().first.flatMap { Int($0.dropFirst()) } ?? 0
                default: break
                }
            case UInt8(ascii: "1"):
                guard let (xy, path) = fields(record, pathAfterSpaces: 8) else { continue }
                status.entries.append(GitStatusEntry(path: path, index: xy.0, worktree: xy.1))
            case UInt8(ascii: "2"):
                guard let (xy, path) = fields(record, pathAfterSpaces: 9) else { continue }
                let origin = records.next().map { decode($0) }
                status.entries.append(GitStatusEntry(path: path, originalPath: origin, index: xy.0, worktree: xy.1))
            case UInt8(ascii: "u"):
                guard let (xy, path) = fields(record, pathAfterSpaces: 10) else { continue }
                status.entries.append(GitStatusEntry(path: path, index: xy.0, worktree: xy.1, isConflict: true))
            case UInt8(ascii: "?"):
                guard let (_, path) = fields(record, pathAfterSpaces: 1) else { continue }
                status.entries.append(GitStatusEntry(path: path, index: .untracked, worktree: .untracked))
            case UInt8(ascii: "!"):
                guard let (_, path) = fields(record, pathAfterSpaces: 1) else { continue }
                status.entries.append(GitStatusEntry(path: path, index: .ignored, worktree: .ignored))
            default:
                continue
            }
        }
        if oid == nil {
            status.head = .unborn(branch)
        } else if isDetached {
            status.head = .detached(String((oid ?? "").prefix(7)))
        } else {
            status.head = .branch(branch ?? "")
        }
        return status
    }

    /// The `XY` pair and the path that starts after the n-th space.
    private static func fields(_ record: Data, pathAfterSpaces count: Int) -> ((GitChange, GitChange), String)? {
        var spaces = 0
        var pathStart: Data.Index?
        for index in record.indices where record[index] == UInt8(ascii: " ") {
            spaces += 1
            if spaces == count {
                pathStart = record.index(after: index)
                break
            }
        }
        guard let pathStart, pathStart < record.endIndex else { return nil }
        let path = decode(record[pathStart...])
        guard count > 1 else { return ((.untracked, .untracked), path) }
        let xyStart = record.index(record.startIndex, offsetBy: 2)
        guard record.count > 4, let x = GitChange(rawValue: Character(UnicodeScalar(record[xyStart]))),
            let y = GitChange(rawValue: Character(UnicodeScalar(record[record.index(after: xyStart)])))
        else { return nil }
        return ((x, y), path)
    }

    /// Edge cases: a name that is not UTF-8 keeps its length with replacement characters.
    private static func decode(_ bytes: Data) -> String {
        String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }
}
