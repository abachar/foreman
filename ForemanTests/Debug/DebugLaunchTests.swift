import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// debug R3 (amended 2026-10-18), R8, R9: a launch through the language server and a terminal.
///
/// No language server and no adapter is launched: the answers are values, the channel a mock.
nonisolated struct DebugLaunchTests {
    // MARK: - Quoting (R8)

    @Test(arguments: [
        (["/bin/echo", "a b"], "'/bin/echo' 'a b'"),
        (["it's"], #"'it'\''s'"#),
        (["a", ""], "'a' ''"),
        (["$HOME", "`id`", "*"], "'$HOME' '`id`' '*'"),
        (["/Users/me/My App (v2)/bin"], "'/Users/me/My App (v2)/bin'"),
        (["''"], #"''\'''\'''"#),
    ])
    func quotesEachArgument(arguments: [String], expected: String) {
        #expect(DebugLaunch.commandLine(arguments) == expected)
    }

    // MARK: - The two answers

    private func option(_ main: String, _ project: String?) -> LSPAny {
        var object: [String: LSPAny] = ["mainClass": .string(main), "filePath": .string("/w/\(main).java")]
        object["projectName"] = project.map { .string($0) }
        return .hash(object)
    }

    @Test func decodesOneMainClass() throws {
        let options = try DebugLaunch.mainClasses(from: .array([option("com.x.App", "api")]))
        #expect(options == [.init(mainClass: "com.x.App", projectName: "api", filePath: "/w/com.x.App.java")])
        #expect(DebugLaunch.choose(from: options, folderName: "other") == options[0])
    }

    @Test func severalMainClassesTakeTheProjectNamedLikeTheFolder() throws {
        let options = try DebugLaunch.mainClasses(
            from: .array([option("a.A", "lib"), option("b.B", "api"), option("c.C", "api")]))
        #expect(options.count == 3)
        #expect(DebugLaunch.choose(from: options, folderName: "api")?.mainClass == "b.B")
        #expect(DebugLaunch.choose(from: options, folderName: "none")?.mainClass == "a.A")
    }

    @Test func noMainClassIsAnEmptyChoice() throws {
        let options = try DebugLaunch.mainClasses(from: .array([]))
        #expect(options.isEmpty)
        #expect(DebugLaunch.choose(from: options, folderName: "api") == nil)
    }

    @Test(arguments: [
        LSPAny.hash(["mainClass": .string("a.A")]),
        .array([.string("a.A")]),
        .array([.hash(["projectName": .string("x")])]),
        .array([.hash(["mainClass": .number(1)])]),
        .string("a.A"),
        .null,
    ])
    func aWrongMainClassShapeQuotesTheAnswer(answer: LSPAny) {
        #expect(throws: DebugLaunch.Problem.self) { try DebugLaunch.mainClasses(from: answer) }
        #expect(throws: DebugLaunch.Problem.self) { try DebugLaunch.mainClasses(from: nil) }
        let text = DebugLaunch.unexpected(DebugLaunch.resolveMainClassCommand, answer).description
        #expect(text.hasPrefix("vscode.java.resolveMainClass answered "))
    }

    @Test func quotesTheRawAnswerOfAWrongShape() {
        let problem = DebugLaunch.unexpected("vscode.java.resolveClasspath", .hash(["error": .string("boom")]))
        #expect(problem.description == #"vscode.java.resolveClasspath answered an unexpected shape: {"error":"boom"}"#)
    }

    @Test func decodesTheClasspathPair() throws {
        let pair: LSPAny = .array([.array([.string("/m")]), .array([.string("/a.jar"), .string("/b")])])
        #expect(try DebugLaunch.classpath(from: pair) == .init(modulePaths: ["/m"], classPaths: ["/a.jar", "/b"]))
        let noModules: LSPAny = .array([.array([]), .array([.string("/b")])])
        #expect(try DebugLaunch.classpath(from: noModules) == .init(modulePaths: [], classPaths: ["/b"]))
    }

    @Test(arguments: [
        LSPAny.array([.array([.string("/m")])]),
        .array([.string("/m"), .string("/c")]),
        .array([.array([.number(1)]), .array([])]),
        .hash(["classPaths": .array([])]),
        .null,
    ])
    func aWrongClasspathShapeIsAProblem(answer: LSPAny) {
        #expect(throws: DebugLaunch.Problem.self) { try DebugLaunch.classpath(from: answer) }
    }

    // MARK: - The merge (R3)

    private let cwd = URL(filePath: "/w/api", directoryHint: .isDirectory)

    private func hash(_ value: LSPAny) throws -> [String: LSPAny] {
        guard case .hash(let object) = value else { throw Problem.notAHash }
        return object
    }

    private enum Problem: Error { case notAHash }

    @Test func theServersAnswerFillsWhatTheUserLeftOut() throws {
        let resolved: [String: LSPAny] = [
            "mainClass": .string("a.A"), "projectName": .string("api"), "classPaths": .array([.string("/c")]),
            "modulePaths": .array([]),
        ]
        let merged = try hash(
            DebugLaunch.merge(
                arguments: .hash(["vmArgs": .string("-Dx=1")]), resolved: resolved, cwd: cwd, env: ["A": "1"]))
        #expect(merged["mainClass"] == .string("a.A"))
        #expect(merged["projectName"] == .string("api"))
        #expect(merged["classPaths"] == .array([.string("/c")]))
        #expect(merged["vmArgs"] == .string("-Dx=1"))
        #expect(merged["cwd"] == .string("/w/api"))
        #expect(merged["env"] == .hash(["A": .string("1")]))
        #expect(merged["console"] == .string("integratedTerminal"))
    }

    @Test func theUsersKeysWinVerbatim() throws {
        let user: [String: LSPAny] = [
            "mainClass": .string("mine.Main"), "classPaths": .array([.string("/mine")]),
            "cwd": .string("/elsewhere"), "console": .string("internalConsole"),
            "env": .hash(["A": .string("user"), "B": .string("2")]),
        ]
        let resolved: [String: LSPAny] = [
            "mainClass": .string("a.A"), "classPaths": .array([.string("/c")]), "modulePaths": .array([]),
        ]
        let merged = try hash(
            DebugLaunch.merge(arguments: .hash(user), resolved: resolved, cwd: cwd, env: ["A": "repo", "C": "3"]))
        #expect(merged["mainClass"] == .string("mine.Main"))
        #expect(merged["classPaths"] == .array([.string("/mine")]))
        #expect(merged["modulePaths"] == .array([]))
        #expect(merged["cwd"] == .string("/elsewhere"))
        #expect(merged["console"] == .string("internalConsole"))
        #expect(merged["env"] == .hash(["A": .string("user"), "B": .string("2"), "C": .string("3")]))
    }

    @Test func noEnvAddsNoKey() throws {
        let merged = try hash(DebugLaunch.merge(arguments: .hash([:]), resolved: [:], cwd: cwd, env: [:]))
        #expect(merged["env"] == nil)
    }

    // MARK: - Reply and stop

    @Test func theRunInTerminalReplyCarriesTheProcessId() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "java", timeout: .seconds(5))
        let request = DAPMessage(seq: 7, type: .request, command: "runInTerminal")
        let body = try LSPAny(encoding: DAPRunInTerminalResponse(processId: 4242))
        await session.respond(to: request, success: true, body: body)
        var data = adapter.dataSequence.makeAsyncIterator()
        let sent = try JSONDecoder().decode(DAPMessage.self, from: try #require(await data.next()))
        #expect(sent.type == .response)
        #expect(sent.command == "runInTerminal")
        #expect(sent.requestSeq == 7)
        #expect(sent.success == true)
        #expect(sent.body == .hash(["processId": .number(4242)]))
    }

    @Test func aLaunchTerminatesTheProgramAnAttachLeavesIt() {
        #expect(DebugCommand.Request.launch.terminatesDebuggee)
        #expect(!DebugCommand.Request.attach.terminatesDebuggee)
    }
}
