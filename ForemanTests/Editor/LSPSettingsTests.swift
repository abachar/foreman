import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R57: a server's settings reach it by the three channels of the protocol, verbatim.
///
/// Nothing is launched: the params of `initialize` and the answer to `workspace/configuration`
/// are pure functions, and that is where the whole rule lives (coding rules: hermetic).
struct LSPSettingsTests {
    private let settings: LSPAny = [
        "java": [
            "import": ["generatesMetadataFilesAtProjectRoot": false, "exclusions": ["**/target/**"]],
            "configuration": ["runtimes": [["name": "JavaSE-21", "default": true]]],
        ]
    ]

    /// Channel 1: the object goes into `initializationOptions` as written.
    @Test func initializeCarriesTheSettingsAsInitializationOptions() {
        let params = LSPServer.initializeParams(root: URL(filePath: "/w/server"), settings: settings)
        #expect(params.initializationOptions == settings)
        #expect(params.rootUri == URL(filePath: "/w/server").absoluteString)
        // Channel 3 needs the server to know it may ask.
        #expect(params.capabilities.workspace?.configuration == true)
    }

    /// An entry without settings announces none, and still lets the server ask (it gets `null`s).
    @Test func initializeWithoutSettingsAnnouncesNone() {
        let params = LSPServer.initializeParams(root: URL(filePath: "/w"), settings: nil)
        #expect(params.initializationOptions == nil)
        #expect(params.capabilities.workspace?.configuration == true)
    }

    /// Channel 3: one value per item, at the item's dotted section.
    @Test func answersEachItemAtItsDottedSection() {
        let items = [
            ConfigurationItem(scopeUri: nil, section: "java.import"),
            ConfigurationItem(scopeUri: nil, section: "java.configuration.runtimes"),
            ConfigurationItem(scopeUri: "file:///w/a.java", section: "java.import.exclusions"),
        ]
        let answer = LSPServer.configuration(for: items, in: settings)
        #expect(
            answer == [
                ["generatesMetadataFilesAtProjectRoot": false, "exclusions": ["**/target/**"]],
                [["name": "JavaSE-21", "default": true]],
                ["**/target/**"],
            ])
    }

    /// A section that leads nowhere — a missing key, or a key under a value that is not an
    /// object — is `null`, never an error: the server treats `null` as "use your default".
    @Test func answersNullForAMissingSection() {
        let items = [
            ConfigurationItem(scopeUri: nil, section: "java.format"),
            ConfigurationItem(scopeUri: nil, section: "java.import.exclusions.deeper"),
            ConfigurationItem(scopeUri: nil, section: "typescript"),
        ]
        #expect(LSPServer.configuration(for: items, in: settings) == [.null, .null, .null])
    }

    /// No section asks for everything; no settings at all answers `null` to anything.
    @Test func answersTheWholeObjectWithoutASectionAndNullWithoutSettings() {
        let whole = [ConfigurationItem(scopeUri: nil, section: nil), ConfigurationItem(scopeUri: nil, section: "")]
        #expect(LSPServer.configuration(for: whole, in: settings) == [settings, settings])
        let items = [ConfigurationItem(scopeUri: nil, section: "java"), ConfigurationItem(scopeUri: nil, section: nil)]
        #expect(LSPServer.configuration(for: items, in: nil) == [.null, .null])
        #expect(LSPServer.configuration(for: [], in: settings).isEmpty)
    }

    /// Channel 2 is sent on a change of the settings only; the same object again sends nothing,
    /// and a server that is not running is simply told at its start.
    @MainActor
    @Test func anUpdateKeepsTheNewSettingsForTheNextStart() {
        let server = LSPServer(
            command: "no-such-language-server", root: URL(filePath: "/w"), timeout: .seconds(1),
            settings: settings, environment: { ["PATH": "/nowhere"] })
        #expect(server.settings == settings)
        server.update(settings: ["java": ["import": ["exclusions": []]]])
        #expect(server.settings == ["java": ["import": ["exclusions": []]]])
        server.update(settings: nil)
        #expect(server.settings == nil)
    }
}
