import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// debug R1 (the `server` form), R11.
///
/// The port a language server answers, the request that asks, and the words of a failure. No server and no adapter is launched.
nonisolated struct DebugServerAdapterTests {
    @Test func theParamsCarryTheCommandIdAndNoArguments() throws {
        let params = LSPServer.executeParams(for: "vscode.java.startDebugSession")
        #expect(params.command == "vscode.java.startDebugSession")
        #expect(params.arguments == nil)
        let json = try String(data: JSONEncoder().encode(params), encoding: .utf8) ?? ""
        #expect(json.contains("\"command\":\"vscode.java.startDebugSession\""))
        #expect(!json.contains("arguments"))
    }

    @Test(arguments: [
        (LSPAny.number(5005), 5005 as Int?),
        (.string("5005"), 5005),
        (.string(" 61234\n"), 61234),
        (.number(0), nil),
        (.number(70000), nil),
        (.number(1.5), nil),
        (.string("localhost"), nil),
        (.string(""), nil),
        (.null, nil),
        (.bool(true), nil),
        (.hash(["port": .number(5005)]), nil),
        (.array([.number(5005)]), nil),
    ])
    func readsAPortOffAnAnswer(answer: LSPAny, expected: Int?) {
        #expect(DebugFeature.port(of: answer) == expected)
    }

    @Test func noAnswerIsNoPort() {
        #expect(DebugFeature.port(of: nil) == nil)
    }

    @Test func theBannerQuotesTheAnswerOrTheMissingServer() {
        let id = "vscode.java.startDebugSession"
        #expect(
            DebugFeature.noPort(
                command: id, extensionKey: "java", answer: .hash(["a": .number(1)]), declared: true, failure: nil)
                == "\(id) answered no port: {\"a\":1}")
        #expect(
            DebugFeature.noPort(command: id, extensionKey: "java", answer: nil, declared: true, failure: nil)
                .hasPrefix("\(id) answered no port: no answer"))
        #expect(
            DebugFeature.noPort(command: id, extensionKey: "java", answer: nil, declared: false, failure: nil)
                .contains("`lsp.java` is not declared"))
        #expect(
            DebugFeature.noPort(command: id, extensionKey: "java", answer: nil, declared: true, failure: "jdtls died")
                == "jdtls died")
    }

    @Test func theServersDeathNamesTheExtension() {
        #expect(DebugFeature.serverEnded(extensionKey: "java").contains("`java` language server stopped"))
    }

    @Test func theServerFormIsToldFromTheCommandForm() {
        #expect(DebugCatalog.Adapter.server("x").isServer)
        #expect(!DebugCatalog.Adapter.command("x").isServer)
    }
}
