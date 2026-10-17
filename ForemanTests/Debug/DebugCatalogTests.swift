import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// The `debug` section (debug R1) and the `debug` key of a command (debug R2); config R7.
struct DebugCatalogTests {
    private func decode(_ json: String) throws -> DebugCatalog {
        try JSONDecoder().decode(DebugCatalog.self, from: Data(json.utf8))
    }

    @Test func aMissingSectionIsAnEmptyCatalog() throws {
        let catalog = try WorkspaceConfig.empty.section("debug", as: DebugCatalog.self) ?? .empty
        #expect(catalog == .empty)
        #expect(catalog.timeout == .seconds(10))
    }

    @Test func decodesBothFormsAndTheStringShortForm() throws {
        let catalog = try decode(
            #"{ "swift": { "command": "xcrun lldb-dap" }, "Java": { "server": "vscode.java.startDebugSession" }, "py": "debugpy-adapter" }"#
        )
        #expect(
            catalog.adapters == [
                "swift": .command("xcrun lldb-dap"), "java": .server("vscode.java.startDebugSession"),
                "py": .command("debugpy-adapter"),
            ])
        #expect(catalog.warnings.isEmpty)
    }

    @Test(arguments: [(0.5, 1.0), (120.0, 60.0), (12.0, 12.0)])
    func clampsTheTimeout(declared: Double, expected: Double) throws {
        #expect(try decode(#"{ "timeout": \#(declared) }"#).timeout == .seconds(expected))
    }

    @Test func theReservedKeyIsNeverAnAdapter() throws {
        let catalog = try decode(#"{ "timeout": 20, "swift": "xcrun lldb-dap" }"#)
        #expect(catalog.timeout == .seconds(20))
        #expect(catalog.adapters.keys.sorted() == ["swift"])
    }

    /// config R7: the entry goes, the section stays.
    @Test func dropsAnInvalidEntryWithAWarningAndKeepsTheRest() throws {
        let catalog = try decode(
            #"""
            { "swift": "xcrun lldb-dap",
              "both": { "command": "a", "server": "b" },
              "neither": { },
              "typed": { "command": 12 },
              "number": 4,
              "blank": "  ",
              "timeout": "soon" }
            """#)
        #expect(catalog.adapters == ["swift": .command("xcrun lldb-dap")])
        #expect(catalog.timeout == .seconds(10))
        #expect(catalog.warnings.count == 6)
        #expect(catalog.warnings.contains { $0.hasPrefix("debug.both ignored") })
        #expect(catalog.warnings.contains { $0.hasPrefix("debug.timeout ignored") })
    }

    // MARK: - A command's `debug` key

    private func parse(_ json: String) throws -> (command: DebugCommand?, warning: String?) {
        DebugCommand.parse(try JSONDecoder().decode(LSPAny.self, from: Data(json.utf8)))
    }

    @Test func infersAttachFromAPortOrAPidAndLaunchOtherwise() throws {
        #expect(try parse(#"{ "adapter": "java", "arguments": { "port": 5005 } }"#).command?.request == .attach)
        #expect(try parse(#"{ "adapter": "swift", "arguments": { "pid": 42 } }"#).command?.request == .attach)
        #expect(try parse(#"{ "adapter": "swift", "arguments": { "program": "/x" } }"#).command?.request == .launch)
        #expect(try parse(#"{ "adapter": "swift" }"#).command?.request == .launch)
        #expect(
            try parse(#"{ "adapter": "java", "request": "launch", "arguments": { "port": 1 } }"#).command?.request
                == .launch)
    }

    @Test func keepsTheArgumentsVerbatim() throws {
        let json = #"{ "hostName": "localhost", "port": 5005, "nested": { "list": [1, "x", null, true] } }"#
        let command = try #require(try parse(#"{ "adapter": "Java", "arguments": \#(json) }"#).command)
        #expect(command.adapter == "java")
        #expect(command.arguments == (try JSONDecoder().decode(LSPAny.self, from: Data(json.utf8))))
        #expect(
            command.arguments.hashValue == (try JSONDecoder().decode(LSPAny.self, from: Data(json.utf8))).hashValue)
    }

    @Test func aMissingAdapterOrABadShapeIsAWarning() throws {
        #expect(try parse(#"{ "request": "attach" }"#).command == nil)
        #expect(try parse(#"{ "request": "attach" }"#).warning?.contains("adapter") == true)
        #expect(try parse(#"{ "adapter": "java", "request": "fly" }"#).warning != nil)
        #expect(try parse(#"{ "adapter": "java", "arguments": [1] }"#).warning != nil)
        #expect(try parse(#""java""#).warning != nil)
    }
}
