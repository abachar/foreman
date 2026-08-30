import Foundation
import Testing

@testable import Foreman

/// Which folder a window opens on (product R1, R8) and, above all, the single URL that two paths to
/// the same folder must produce: `WindowGroup(for: URL.self)` activates an existing window only when
/// the presented value is equal.
struct WorkspaceFolderTests {
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    private let currentDirectory = URL(filePath: "/Users/tester/code/foreman", directoryHint: .isDirectory)

    @Test func opensHomeWhenNoFolderIsGiven() {
        #expect(resolve(nil) == home)
        #expect(resolve("") == home)
    }

    @Test func expandsTildeAgainstHome() {
        #expect(resolve("~") == home)
        #expect(resolve("~/code") == folder("/Users/tester/code"))
    }

    @Test func resolvesRelativePathAgainstCurrentDirectory() {
        #expect(resolve("docs") == folder("/Users/tester/code/foreman/docs"))
        #expect(resolve("../other") == folder("/Users/tester/code/other"))
    }

    @Test func keepsAbsolutePath() {
        #expect(resolve("/Users/tester/code/other") == folder("/Users/tester/code/other"))
    }

    @Test func writesTheSameFolderTheSameWay() {
        let variants = [
            "/Users/tester/code",
            "/Users/tester/code/",
            "/Users/tester/./code",
            "/Users/tester/code/../code",
        ]

        #expect(Set(variants.map { resolve($0) }) == [folder("/Users/tester/code")])
    }

    @Test func keepsAFolderThatDoesNotExist() {
        #expect(resolve("/Users/tester/gone") == folder("/Users/tester/gone"))
    }

    @Test func resolvesSymlinksSoBothPathsShareOneWindow() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "WorkspaceFolderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        let link = root.appending(path: "link", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        let linkPath = link.path(percentEncoded: false)
        let viaLink = WorkspaceFolder.resolve(path: linkPath, currentDirectory: root, home: home)
        let viaTarget = WorkspaceFolder.resolve(path: "target", currentDirectory: root, home: home)

        #expect(viaLink == viaTarget)
    }

    @Test func readsTheFolderArgumentAndIgnoresFlags() {
        #expect(WorkspaceFolder.argument(in: ["/Applications/Foreman.app/Contents/MacOS/Foreman"]) == nil)
        #expect(WorkspaceFolder.argument(in: ["Foreman", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        #expect(WorkspaceFolder.argument(in: ["Foreman", "/Users/tester/code"]) == "/Users/tester/code")
        #expect(WorkspaceFolder.argument(in: ["Foreman", "-psn_0_1", "~/code"]) == "~/code")
        #expect(WorkspaceFolder.argument(in: ["Foreman", "."]) == ".")
    }

    private func resolve(_ path: String?) -> URL {
        WorkspaceFolder.resolve(path: path, currentDirectory: currentDirectory, home: home)
    }

    private func folder(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }
}

/// product R8 (amended 2026-08-30): the folder a window opens on at launch.
struct LaunchFolderTests {
    private let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
    private let cwd = URL(filePath: "/Users/x/code", directoryHint: .isDirectory)
    private let existing: Set<String> = ["Users/x/foreman", "Users/x/other"]

    private func launch(argument: String? = nil, pending: URL? = nil, recents: [String] = []) -> String {
        WorkspaceFolder.launchFolder(
            argument: argument, pending: pending,
            recents: recents.map { URL(filePath: $0, directoryHint: .isDirectory) },
            home: home, currentDirectory: cwd,
            // A folder URL's path ends with a slash; the set is written without one.
            exists: { existing.contains($0.path(percentEncoded: false).trimmingCharacters(in: ["/"])) }
        ).path(percentEncoded: false)
    }

    @Test func theCommandLineArgumentComesFirst() {
        #expect(
            launch(
                argument: "/Users/x/asked-for", pending: URL(filePath: "/Users/x/other"),
                recents: ["/Users/x/foreman"]) == "/Users/x/asked-for/")
        #expect(launch(argument: ".") == "/Users/x/code/")
    }

    @Test func thenTheFolderTheSystemHandedOver() {
        #expect(
            launch(pending: URL(filePath: "/Users/x/dropped"), recents: ["/Users/x/foreman"])
                == "/Users/x/dropped/")
    }

    @Test func thenTheMostRecentWorkspace() {
        #expect(launch(recents: ["/Users/x/foreman", "/Users/x/other"]) == "/Users/x/foreman/")
    }

    @Test func aRecentFolderThatIsGoneIsSkipped() {
        #expect(launch(recents: ["/Users/x/moved-away", "/Users/x/other"]) == "/Users/x/other/")
    }

    @Test func andTheHomeWhenNothingIsLeft() {
        #expect(launch() == "/Users/x/")
        #expect(launch(recents: ["/Users/x/moved-away", "/Users/x/deleted"]) == "/Users/x/")
    }
}
