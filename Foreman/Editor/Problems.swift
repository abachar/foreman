import Foundation
import Observation

/// editor R50 (2026-10-16, M21 21.7): every diagnostic a language server published, per file.
///
/// Not only the open tabs' (R40). A publication replaces the file's list, an empty one clears it;
/// closing a tab leaves the file's list as the server last said it.
@Observable
@MainActor
final class DiagnosticsStore {
    typealias File = DiagnosticFile

    private(set) var files: [URL: File] = [:]

    func publish(_ diagnostics: [EditorDiagnostic], for url: URL, source: String?) {
        let key = url.standardizedFileURL
        guard !diagnostics.isEmpty else {
            files[key] = nil
            return
        }
        files[key] = File(url: key, diagnostics: diagnostics, source: source)
    }

    func diagnostics(for url: URL) -> [EditorDiagnostic] {
        files[url.standardizedFileURL]?.diagnostics ?? []
    }

    /// The ⊗ / ⚠ counters of one file (`layout` R39).
    func counts(for url: URL) -> ProblemCounts {
        Problems.counts(diagnostics(for: url))
    }

    /// The counters of the whole project, for a tab that is not a file.
    var projectCounts: ProblemCounts {
        Problems.counts(files.values.flatMap(\.diagnostics))
    }
}

/// One file's diagnostics as the store keeps them (editor R50).
nonisolated struct DiagnosticFile: Equatable, Sendable {
    let url: URL
    let diagnostics: [EditorDiagnostic]
    /// The server that said it (`jdtls`), shown on each row.
    let source: String?
}

/// editor R50–R52: the Problems panel's list, as values.
nonisolated enum Problems {
    enum Scope: Equatable, Sendable {
        case currentFile
        case project
    }

    /// One line of the list.
    struct Row: Equatable, Sendable, Identifiable {
        let id: String
        let isError: Bool
        let message: String
        let source: String?
        /// 1-based, `nil` for a problem without a place (a shortcut conflict).
        let line: Int?
        let column: Int?
        /// Where a click goes.
        let url: URL?
    }

    /// One group: a file, or the *Foreman config* group that comes first.
    struct Group: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        /// The file's folder, relative to the root.
        let detail: String?
        let isConfig: Bool
        let rows: [Row]
    }

    /// The filters of the panel.
    struct Filter: Equatable, Sendable {
        var scope = Scope.project
        var showsErrors = true
        var showsWarnings = true
        var query = ""
    }

    /// Errors and warnings only: information and hints are not problems (R50).
    static func counts(_ diagnostics: [EditorDiagnostic]) -> ProblemCounts {
        ProblemCounts(
            errors: diagnostics.count { $0.severity == .error }, warnings: diagnostics.count { $0.severity == .warning }
        )
    }

    /// The groups to show: the config group first, then the files with an error, then the others,
    /// each by path; rows by severity then line. `current` is the file of the active tab.
    static func groups(
        files: [DiagnosticFile], config: [Row], filter: Filter, current: URL?, root: URL
    ) -> [Group] {
        let needle = filter.query.trimmingCharacters(in: .whitespaces)
        func keeps(_ row: Row) -> Bool {
            (row.isError ? filter.showsErrors : filter.showsWarnings)
                && (needle.isEmpty || row.message.range(of: needle, options: [.caseInsensitive]) != nil)
        }
        var groups: [Group] = []
        let configRows = config.filter(keeps)
        if filter.scope == .project, !configRows.isEmpty {
            groups.append(
                Group(
                    id: "foreman.config", title: "Foreman config", detail: ".foreman/config.json", isConfig: true,
                    rows: configRows))
        }
        let shown = files.filter { file in
            filter.scope == .project || file.url.standardizedFileURL == current?.standardizedFileURL
        }
        let fileGroups = shown.compactMap { file -> (group: Group, hasError: Bool)? in
            let rows = rows(of: file).filter(keeps)
            guard !rows.isEmpty else { return nil }
            let relative = Workspace.persistedPath(for: file.url, root: root)
            let folder = (relative as NSString).deletingLastPathComponent
            return (
                Group(
                    id: file.url.path(percentEncoded: false), title: file.url.lastPathComponent,
                    detail: folder.isEmpty ? nil : folder, isConfig: false, rows: rows),
                rows.contains(where: \.isError)
            )
        }
        .sorted { first, second in
            first.hasError != second.hasError ? first.hasError : first.group.id < second.group.id
        }
        return groups + fileGroups.map(\.group)
    }

    /// The counts the filter buttons show: the scope's, before the severity filters.
    static func counts(files: [DiagnosticFile], config: [Row], scope: Scope, current: URL?) -> ProblemCounts {
        let diagnostics = files.filter { scope == .project || $0.url == current?.standardizedFileURL }
            .flatMap(\.diagnostics)
        var counts = Self.counts(diagnostics)
        if scope == .project {
            counts.errors += config.count(where: \.isError)
            counts.warnings += config.count { !$0.isError }
        }
        return counts
    }

    private static func rows(of file: DiagnosticFile) -> [Row] {
        file.diagnostics
            .filter { $0.severity == .error || $0.severity == .warning }
            .sorted {
                ($0.severity.rawValue, $0.startLine, $0.startCharacter) < (
                    $1.severity.rawValue, $1.startLine, $1.startCharacter
                )
            }
            .enumerated()
            .map { index, diagnostic in
                Row(
                    id: "\(file.url.path(percentEncoded: false))#\(index)", isError: diagnostic.severity == .error,
                    message: diagnostic.message, source: file.source, line: diagnostic.line,
                    column: diagnostic.startCharacter + 1, url: file.url)
            }
    }
}

extension Problems {
    /// config R7, layout R24 (amended 2026-10-16): the config's errors and the shortcut problems,
    /// as the rows of the *Foreman config* group; a click opens the file, at its line when known.
    static func configRows(errors: [WorkspaceError], shortcuts: [ShortcutProblem], configFile: URL) -> [Row] {
        let fromConfig = errors.enumerated().map { index, error -> Row in
            switch error {
            case .invalidJSON(let file, let line, let message):
                return Row(
                    id: "config.\(index)", isError: true, message: message, source: "Foreman", line: line, column: nil,
                    url: file)
            case .unreadable(let file, _):
                return Row(
                    id: "config.\(index)", isError: true, message: error.description, source: "Foreman", line: nil,
                    column: nil, url: file)
            case .invalidSection:
                return Row(
                    id: "config.\(index)", isError: true, message: error.description, source: "Foreman", line: nil,
                    column: nil, url: configFile)
            }
        }
        let fromShortcuts = shortcuts.enumerated().map { index, problem in
            Row(
                id: "shortcut.\(index)", isError: true, message: problem.description, source: "Shortcuts", line: nil,
                column: nil, url: configFile)
        }
        return fromConfig + fromShortcuts
    }
}

/// editor R51: the panel's filters, kept for the window; the status bar's counters set the scope.
@Observable
@MainActor
final class ProblemsPanelModel {
    var filter = Problems.Filter()
}
