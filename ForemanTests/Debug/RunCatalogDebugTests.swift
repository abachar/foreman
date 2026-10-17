import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// The `debug` key of a command of `config.commands` (debug R2), as `RunCatalog` reads it.
struct RunCatalogDebugTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RunCatalogDebugTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "backend"), withIntermediateDirectories: true)
    }

    private func parse(_ json: String, _ body: (RunCatalog.Parsed) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try body(
            RunCatalog.parse(try JSONDecoder().decode(RunCatalog.Section.self, from: Data(json.utf8)), root: root))
    }

    @Test func readsTheDebugObjectOfACommandThatRuns() throws {
        try parse(
            #"""
            { "backend": { "run": { "run": "mvn spring-boot:run",
                                    "debug": { "adapter": "java", "arguments": { "hostName": "localhost", "port": 5005 } } },
                           "plain": "mvn test" } }
            """#
        ) { parsed in
            #expect(parsed.warnings.isEmpty)
            let command = parsed.commands.first { $0.name == "run" }
            #expect(command?.command == "mvn spring-boot:run")
            #expect(command?.problem == nil)
            #expect(command?.debug?.adapter == "java")
            #expect(command?.debug?.request == .attach)
            #expect(
                command?.debug?.arguments == .hash(["hostName": .string("localhost"), "port": .number(5005)]))
            #expect(parsed.commands.first { $0.name == "plain" }?.debug == nil)
        }
    }

    @Test func aDebugOnlyCommandIsALaunchListedGreyed() throws {
        try parse(
            #"{ ".": { "app": { "debug": { "adapter": "swift", "arguments": { "program": "/x/Foreman" } } } } }"#
        ) { parsed in
            let command = parsed.commands.first
            #expect(command?.debug?.request == .launch)
            #expect(command?.command == "")
            #expect(command?.problem == "debug only")
        }
    }

    /// config R7 one level down: the key goes, the command stays.
    @Test func aDebugObjectWithoutAnAdapterIsDroppedAndTheCommandKept() throws {
        try parse(#"{ "backend": { "run": { "run": "mvn test", "debug": { "request": "attach" } } } }"#) { parsed in
            #expect(parsed.commands.map(\.id) == ["backend:run"])
            #expect(parsed.commands.first?.debug == nil)
            #expect(parsed.warnings.count == 1)
            #expect(parsed.warnings.first?.hasPrefix("commands.backend.run.debug ignored") == true)
        }
    }

    @Test func aCommandWithNeitherRunNorDebugIsStillRefused() throws {
        try parse(#"{ "backend": { "x": { "cwd": "." } } }"#) { parsed in
            #expect(parsed.commands.isEmpty)
            #expect(parsed.warnings.count == 1)
        }
    }

    /// A `$env` may hold a lowercase variable called `debug`.
    @Test func aLowercaseDebugVariableOfTheEnvIsNotACommand() throws {
        try parse(#"{ "backend": { "$env": { "debug": "1" }, "t": "mvn test" } }"#) { parsed in
            #expect(parsed.warnings.isEmpty)
            #expect(parsed.commands.first?.env["debug"] == "1")
        }
    }
}
