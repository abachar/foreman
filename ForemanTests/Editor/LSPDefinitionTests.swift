import Foundation
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R39, R43, R44: the capability gate, and what a server's answer becomes.
///
/// No server is launched (coding rules: hermetic): the whole rule is a pure function over the
/// response, which is exactly why it was written as one.
struct LSPDefinitionTests {
    private let root = URL(filePath: "/w")

    private func location(_ path: String, line: Int) -> Location {
        Location(
            uri: URL(filePath: path).absoluteString,
            range: LSPRange(start: Position(line: line, character: 0), end: Position(line: line, character: 4)))
    }

    // MARK: - The capability gate (R39)

    @Test func offersNothingWhenTheServerAnnouncedNothing() {
        #expect(LSPServer.providesDefinition(nil) == false)
    }

    @Test(arguments: [true, false])
    func followsTheAnnouncedBoolean(announced: Bool) {
        var capabilities = ServerCapabilities()
        capabilities.definitionProvider = .optionA(announced)
        #expect(LSPServer.providesDefinition(capabilities) == announced)
    }

    /// An options object is itself the announcement: only the boolean form can say no.
    @Test func treatsAnOptionsObjectAsAYes() {
        var capabilities = ServerCapabilities()
        capabilities.definitionProvider = .optionB(DefinitionOptions())
        #expect(LSPServer.providesDefinition(capabilities) == true)
    }

    // MARK: - Resolving the answer (R43, R44)

    @Test func opensASingleLocationOnTheLineAfterIt() {
        let resolved = LSPServers.resolve(.optionA(location("/w/src/a.swift", line: 41)), root: root)
        // LSP counts lines from zero, `Editor.open(…, line:)` from one.
        #expect(resolved == .found(url: URL(filePath: "/w/src/a.swift"), line: 42))
    }

    /// editor R43: several results, the first the server gave — no picker in v1.
    @Test func takesTheFirstOfSeveralLocations() {
        let resolved = LSPServers.resolve(
            .optionB([location("/w/a.swift", line: 0), location("/w/b.swift", line: 7)]), root: root)
        #expect(resolved == .found(url: URL(filePath: "/w/a.swift"), line: 1))
    }

    /// A link answers with the selection range: that is where the name is, not where the block
    /// starts, so it is the one to jump to.
    @Test func jumpsToTheSelectionRangeOfALink() {
        let link = LocationLink(
            targetUri: URL(filePath: "/w/a.swift").absoluteString,
            targetRange: LSPRange(start: Position(line: 3, character: 0), end: Position(line: 9, character: 0)),
            targetSelectionRange: LSPRange(
                start: Position(line: 5, character: 4), end: Position(line: 5, character: 8)))
        #expect(LSPServers.resolve(.optionC([link]), root: root) == .found(url: URL(filePath: "/w/a.swift"), line: 6))
    }

    @Test func doesNothingWhenTheServerFoundNothing() {
        #expect(LSPServers.resolve(nil, root: root) == .none)
        #expect(LSPServers.resolve(.optionB([]), root: root) == .none)
        #expect(LSPServers.resolve(.optionC([]), root: root) == .none)
    }

    /// editor R46: a URI comes from a process and is not trusted — anything but a file is dropped,
    /// in silence, before anything is opened.
    @Test(arguments: ["https://example.com/a.swift", "untitled:Untitled-1", "not a url at all"])
    func ignoresAUriThatIsNotAFile(uri: String) {
        let target = Location(
            uri: uri, range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)))
        #expect(LSPServers.resolve(.optionA(target), root: root) == .none)
    }

    /// editor R44: the SDK header, the `.swiftinterface`, the file in `node_modules` — named, not
    /// opened, and the banner says where it is.
    @Test func refusesATargetOutsideTheWorkspace() {
        let resolved = LSPServers.resolve(
            .optionA(location("/usr/lib/swift/String.swiftinterface", line: 0)), root: root)
        #expect(resolved == .refused("Defined outside the workspace: /usr/lib/swift/String.swiftinterface"))
    }

    /// The prefix check must not take a sibling folder for a child (`/w` and `/workspace`).
    @Test func doesNotTakeASiblingFolderForTheWorkspace() {
        let resolved = LSPServers.resolve(.optionA(location("/workspace/a.swift", line: 0)), root: root)
        #expect(resolved == .refused("Defined outside the workspace: /workspace/a.swift"))
    }
}
