import Foundation
import Testing

@testable import Foreman

/// The diagnostics store and the Problems list (editor R50–R52, M21 21.7).
@MainActor
struct ProblemsTests {
    private let root = URL(filePath: "/ws")

    private func diagnostic(
        _ line: Int, _ severity: EditorDiagnostic.Severity, _ message: String = "m"
    )
        -> EditorDiagnostic
    {
        EditorDiagnostic(
            startLine: line - 1, startCharacter: 4, endLine: line - 1, endCharacter: 8, message: message,
            severity: severity)
    }

    @Test func aPublicationReplacesAFileAndAnEmptyOneClearsIt() {
        let store = DiagnosticsStore()
        let file = root.appending(path: "src/Order.java")
        store.publish([diagnostic(3, .error), diagnostic(5, .warning)], for: file, source: "jdtls")
        store.publish([diagnostic(9, .warning)], for: root.appending(path: "src/Line.java"), source: "jdtls")
        #expect(store.counts(for: file) == ProblemCounts(errors: 1, warnings: 1))
        #expect(store.projectCounts == ProblemCounts(errors: 1, warnings: 2))

        store.publish([diagnostic(4, .warning)], for: file, source: "jdtls")
        #expect(store.counts(for: file) == ProblemCounts(errors: 0, warnings: 1))

        store.publish([], for: file, source: "jdtls")
        #expect(store.files[file] == nil)
        #expect(store.projectCounts == ProblemCounts(errors: 0, warnings: 1))
    }

    @Test func informationAndHintsAreNotProblems() {
        let counts = Problems.counts([diagnostic(1, .information), diagnostic(2, .hint), diagnostic(3, .warning)])
        #expect(counts == ProblemCounts(errors: 0, warnings: 1))
    }

    private var files: [DiagnosticFile] {
        [
            DiagnosticFile(
                url: root.appending(path: "src/b/Warn.java"), diagnostics: [diagnostic(2, .warning, "unused")],
                source: "jdtls"),
            DiagnosticFile(
                url: root.appending(path: "src/a/Order.java"),
                diagnostics: [diagnostic(9, .warning, "note"), diagnostic(43, .error, "getPrice undefined")],
                source: "jdtls"),
        ]
    }

    private var config: [Problems.Row] {
        Problems.configRows(
            errors: [.invalidJSON(file: root.appending(path: ".foreman/config.json"), line: 14, message: "bad")],
            shortcuts: [.unknownAction(id: "x.y")], configFile: root.appending(path: ".foreman/config.json"))
    }

    @Test func theConfigComesFirstThenFilesWithAnErrorThenTheOthers() {
        let groups = Problems.groups(files: files, config: config, filter: .init(), current: nil, root: root)
        #expect(groups.map(\.title) == ["Foreman config", "Order.java", "Warn.java"])
        #expect(groups[0].rows.map(\.line) == [14, nil])
        #expect(groups[1].detail == "src/a")
        // Errors first, then by line.
        #expect(groups[1].rows.map(\.message) == ["getPrice undefined", "note"])
        #expect(groups[1].rows.first?.column == 5)
        #expect(groups[1].rows.first?.source == "jdtls")
    }

    @Test func theScopeAndTheFiltersNarrowTheList() {
        let current = root.appending(path: "src/a/Order.java")
        var filter = Problems.Filter(scope: .currentFile)
        #expect(
            Problems.groups(files: files, config: config, filter: filter, current: current, root: root).map(\.title)
                == ["Order.java"])
        #expect(Problems.groups(files: files, config: config, filter: filter, current: nil, root: root).isEmpty)

        filter = Problems.Filter(showsErrors: false)
        #expect(
            Problems.groups(files: files, config: config, filter: filter, current: nil, root: root).map(\.title)
                == ["Order.java", "Warn.java"])

        filter = Problems.Filter(query: "UNUSED")
        #expect(
            Problems.groups(files: files, config: config, filter: filter, current: nil, root: root).map(\.title)
                == ["Warn.java"])

        #expect(
            Problems.counts(files: files, config: config, scope: .project, current: nil)
                == ProblemCounts(errors: 3, warnings: 2))
        #expect(
            Problems.counts(files: files, config: config, scope: .currentFile, current: current)
                == ProblemCounts(errors: 1, warnings: 1))
    }

    /// layout R39, editor R50: a server is named past its launcher.
    @Test func aServerIsNamedPastItsLauncher() {
        #expect(LSPServers.displayName(of: "xcrun sourcekit-lsp") == "sourcekit-lsp")
        #expect(LSPServers.displayName(of: "jdtls -data /x/.foreman/jdtls") == "jdtls")
        #expect(
            LSPServers.displayName(of: "/opt/bin/typescript-language-server --stdio") == "typescript-language-server")
        #expect(LSPServers.displayName(of: "npx ngserver --stdio") == "ngserver")
    }
}
