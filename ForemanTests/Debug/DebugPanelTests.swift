import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// The adapter's side of the panel's model: answers scripted by request name, requests recorded.
///
/// No adapter is launched here, and nothing is rendered.
@MainActor
private final class Script {
    var answers: [String: [LSPAny]] = [:]
    var errors: [String: String] = [:]
    private(set) var requests: [(command: String, arguments: LSPAny)] = []

    func answer(_ command: String, _ body: some Encodable) throws {
        answers[command, default: []].append(try LSPAny(encoding: body))
    }

    func arguments<T: Decodable>(of command: String, _ index: Int = 0, as type: T.Type) throws -> T {
        try requests.filter { $0.command == command }[index].arguments.decoded(type)
    }

    func count(_ command: String) -> Int {
        requests.filter { $0.command == command }.count
    }

    var send: DebugPanelModel.Send {
        { [self] command, arguments in
            requests.append((command, arguments))
            if let message = errors[command] {
                throw DAPSession.Failure.rejected(command: command, message: message)
            }
            guard var queue = answers[command], !queue.isEmpty else { return .hash([:]) }
            let next = queue.removeFirst()
            answers[command] = queue
            return next
        }
    }
}

private func frame(_ id: Int, _ name: String, path: String? = "/p/File.swift", line: Int = 10) -> DAPStackFrame {
    DAPStackFrame(
        id: id, name: name, source: path.map { DAPSource(name: nil, path: $0, sourceReference: nil) }, line: line,
        column: 1)
}

private func frames(_ range: Range<Int>) -> [DAPStackFrame] {
    range.map { frame($0, "f\($0)") }
}

@MainActor
struct DebugPanelTests {
    private let script = Script()
    private let model = DebugPanelModel()

    private func started() {
        model.begin(.running, send: script.send)
    }

    // MARK: - Frames

    /// debug R5, R6: the stopping thread's frames, its top frame selected, the others asked when opened.
    @Test func aStopListsThreadsAndTheStoppingThreadsFrames() async throws {
        started()
        try script.answer(
            "threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main"), DAPThread(id: 2, name: "worker")]))
        try script.answer(
            "stackTrace",
            DAPStackTraceResponse(stackFrames: [frame(7, "run()", line: 42), frame(8, "main()")], totalFrames: 2))

        let top = try await model.stopped(threadID: 2)

        #expect(top?.id == 7)
        #expect(model.threads.map(\.name) == ["main", "worker"])
        #expect(model.threads[0].frames == nil)
        #expect(model.threads[1].frames?.map(\.name) == ["run()", "main()"])
        #expect(model.expandedThreads == [2])
        #expect(model.selectedFrame == 7)
        #expect(model.state == .paused(frame: "run()", line: 42))
        let arguments = try script.arguments(of: "stackTrace", as: DAPStackTraceArguments.self)
        #expect(arguments.threadId == 2)
        #expect(arguments.levels == 100)
    }

    @Test func withoutAThreadIdTheFirstThreadIsTheOne() async throws {
        started()
        try script.answer("threads", DAPThreadsResponse(threads: [DAPThread(id: 5, name: "main")]))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: [frame(1, "a")]))

        _ = try await model.stopped(threadID: nil)

        #expect(model.stoppedThread == 5)
    }

    /// debug R6: a frame shows its source's name, else its path's last component, and the line; one
    /// without a source is greyed and cannot be selected.
    @Test func aFrameWithoutASourceIsGreyedAndNotSelectable() {
        let named = DebugFrame(
            frame: DAPStackFrame(
                id: 1, name: "a", source: DAPSource(name: "Foo.java", path: "jdt://x/Foo.class", sourceReference: nil),
                line: 3, column: 1))
        let pathOnly = DebugFrame(frame: frame(2, "b", path: "/p/dir/Bar.swift", line: 9))
        let none = DebugFrame(frame: frame(3, "c", path: nil))

        #expect(named.location == "Foo.java:3")
        #expect(pathOnly.location == "Bar.swift:9")
        #expect(none.location == nil)
        #expect([named, pathOnly, none].map(\.isSelectable) == [true, true, false])
    }

    /// debug R6: 100 frames out of 250 leave a *more…* row; it asks the next hundred and goes at the end.
    @Test func aStackPastOneHundredFramesOffersMoreAndAsksTheNextPage() async throws {
        started()
        try script.answer("threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main")]))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(0..<100), totalFrames: 250))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(100..<200), totalFrames: 250))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(200..<250), totalFrames: 250))
        _ = try await model.stopped(threadID: 1)
        #expect(model.threads[0].hasMore)

        await model.loadFrames(of: 1)
        #expect(model.threads[0].hasMore)
        await model.loadFrames(of: 1)

        #expect(model.threads[0].frames?.count == 250)
        #expect(!model.threads[0].hasMore)
        let second = try script.arguments(of: "stackTrace", 1, as: DAPStackTraceArguments.self)
        #expect(second.startFrame == 100)
        #expect(second.levels == 100)
        await model.loadFrames(of: 1)
        #expect(script.count("stackTrace") == 3)
    }

    @Test func withoutATotalAFullPageMeansThereIsMore() {
        var full = DebugThread(id: 1, name: "t")
        full.append(DAPStackTraceResponse(stackFrames: frames(0..<100)))
        var short = DebugThread(id: 2, name: "t")
        short.append(DAPStackTraceResponse(stackFrames: frames(0..<30)))

        #expect(full.hasMore)
        #expect(!short.hasMore)
    }

    /// debug R6: another thread's frames are asked when it is opened, once.
    @Test func anotherThreadsFramesAreAskedOnceWhenOpened() async throws {
        started()
        try script.answer(
            "threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main"), DAPThread(id: 2, name: "w")]))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(0..<2), totalFrames: 2))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(10..<13), totalFrames: 3))
        _ = try await model.stopped(threadID: 1)

        await model.loadFrames(of: 2)
        await model.loadFrames(of: 2)

        #expect(model.threads[1].frames?.count == 3)
        #expect(script.count("stackTrace") == 2)
        #expect(try script.arguments(of: "stackTrace", 1, as: DAPStackTraceArguments.self).threadId == 2)
    }

    @Test func aNewStopRebuildsWhatTheLastOneShowed() async throws {
        started()
        try script.answer("threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main")]))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: frames(0..<2)))
        _ = try await model.stopped(threadID: 1)
        model.select(frame: 1)

        model.resumed()

        #expect(model.threads.isEmpty)
        #expect(model.selectedFrame == nil)
        #expect(model.scopes.isEmpty)
        #expect(model.state == .running)
    }

    // MARK: - Variables

    private func scopes() async throws -> DebugVariable {
        started()
        try script.answer(
            "scopes",
            DAPScopesResponse(scopes: [
                DAPScope(name: "Locals", variablesReference: 100, expensive: false),
                DAPScope(name: "Globals", variablesReference: 200, expensive: true),
            ]))
        try script.answer(
            "variables",
            DAPVariablesResponse(variables: [
                DAPVariable(name: "tab", value: "EditorTab", type: "EditorTab", variablesReference: 300),
                DAPVariable(name: "n", value: "3", type: "Int", variablesReference: 0),
            ]))
        model.select(frame: 4)
        await model.loadScopes(of: 4)
        return model.scopes[0]
    }

    /// debug R6, R10: the first cheap scope is opened; nothing below it, and no other scope, is asked ahead.
    @Test func onlyTheOpenedScopeIsAskedAndItsChildrenWait() async throws {
        let locals = try await scopes()

        #expect(model.scopes.map(\.name) == ["Locals", "Globals"])
        #expect(locals.children.map(\.name) == ["tab", "n"])
        #expect(locals.children[0].type == "EditorTab")
        #expect(script.count("variables") == 1)
        #expect(try script.arguments(of: "variables", as: DAPVariablesArguments.self).variablesReference == 100)
        #expect(try script.arguments(of: "scopes", as: DAPScopesArguments.self).frameId == 4)
        #expect(!locals.children[0].isLoaded)
        #expect(!model.scopes[1].isLoaded)
    }

    @Test func aNodeIsAskedOnceHoweverOftenItOpens() async throws {
        let locals = try await scopes()
        try script.answer(
            "variables", DAPVariablesResponse(variables: [DAPVariable(name: "url", value: "x", variablesReference: 0)]))
        let tab = locals.children[0]

        await model.load(tab)
        await model.load(tab)

        #expect(tab.children.map(\.name) == ["url"])
        #expect(script.count("variables") == 2)
        let request = try script.arguments(of: "variables", 1, as: DAPVariablesArguments.self)
        #expect(request.variablesReference == 300)
        #expect(request.start == nil)
        #expect(request.count == nil)
        await model.load(locals.children[1])
        #expect(script.count("variables") == 2)
    }

    /// debug R6: `indexedVariables` past 100 are fetched by 100, `start` and `count` of each page.
    @Test func anArrayPastOneHundredItemsIsPagedByOneHundred() async throws {
        started()
        let array = DebugVariable(name: "items", reference: 9, indexed: 250)
        func page(_ range: Range<Int>) -> DAPVariablesResponse {
            DAPVariablesResponse(
                variables: range.map { DAPVariable(name: "[\($0)]", value: "\($0)", variablesReference: 0) })
        }
        try script.answer("variables", page(0..<100))
        try script.answer("variables", page(100..<200))
        try script.answer("variables", page(200..<250))

        await model.load(array)
        #expect(array.hasMore)
        await model.load(array)
        #expect(array.hasMore)
        await model.load(array)

        #expect(array.children.count == 250)
        #expect(!array.hasMore)
        let starts = try (0..<3).map { try script.arguments(of: "variables", $0, as: DAPVariablesArguments.self) }
        #expect(starts.map(\.start) == [0, 100, 200])
        #expect(starts.map(\.count) == [100, 100, 100])
        await model.load(array)
        #expect(script.count("variables") == 3)
    }

    @Test func aScopeAnswerForAFrameNoLongerSelectedIsDropped() async throws {
        started()
        try script.answer(
            "scopes", DAPScopesResponse(scopes: [DAPScope(name: "Locals", variablesReference: 1, expensive: true)]))
        model.select(frame: 1)

        let pending = Task { await model.loadScopes(of: 1) }
        model.select(frame: 2)
        await pending.value

        #expect(model.scopes.isEmpty)
    }

    // MARK: - Console

    @Test func theConsoleDistinguishesCategories() {
        var console = DebugConsole()
        console.append("out\n", category: "stdout")
        console.append("err\r\nmore\n", category: "stderr")
        console.append("adapter says", category: "console")
        console.append("plain", category: nil)
        console.append("secret", category: "telemetry")

        #expect(console.lines.map(\.text) == ["out", "err", "more", "adapter says", "plain"])
        #expect(console.lines.map(\.kind) == [.plain, .error, .error, .secondary, .plain])
    }

    @Test func theConsoleKeepsTheLast2000Lines() {
        var console = DebugConsole()
        for number in 0..<2500 {
            console.append("line \(number)", category: "stdout")
        }

        #expect(console.lines.count == 2000)
        #expect(console.lines.first?.text == "line 500")
        #expect(console.lines.last?.text == "line 2499")
        #expect(Set(console.lines.map(\.id)).count == 2000)
    }

    /// debug R6: `evaluate { expression, frameId, context: "repl" }`; the answer, or the adapter's refusal, is appended.
    @Test func evaluateSendsTheExpressionInTheSelectedFrame() async throws {
        started()
        model.select(frame: 12)
        try script.answer("evaluate", DAPEvaluateResponse(result: "42", type: "Int", variablesReference: 0))

        await model.evaluate("  a + b ")

        let request = try script.arguments(of: "evaluate", as: DAPEvaluateArguments.self)
        #expect(request.expression == "a + b")
        #expect(request.frameId == 12)
        #expect(request.context == "repl")
        #expect(model.console.lines.map(\.text) == ["> a + b", "42"])
    }

    @Test func anEvaluateErrorIsAppendedInRed() async {
        started()
        script.errors["evaluate"] = "cannot find 'x' in scope"

        await model.evaluate("x")

        #expect(model.console.lines.last?.text == "cannot find 'x' in scope")
        #expect(model.console.lines.last?.kind == .error)
    }

    @Test func theOutputEventsFeedTheConsole() {
        model.output(DAPOutputEvent(category: "stderr", output: "boom\n"))

        #expect(model.console.lines.map(\.text) == ["boom"])
    }

    // MARK: - State and shortcuts

    @Test func theStateInWords() {
        let attach = LSPAny.hash(["hostName": .string("db"), "port": .number(5005)])

        #expect(DebugState.connecting(.attach, arguments: attach).text == "attaching to db:5005")
        #expect(
            DebugState.connecting(.attach, arguments: .hash(["port": .number(5005)])).text
                == "attaching to localhost:5005")
        #expect(DebugState.connecting(.attach, arguments: .hash(["pid": .number(77)])).text == "attaching to pid 77")
        #expect(DebugState.connecting(.launch, arguments: .hash(["program": .string("/a/b")])).text == "launching /a/b")
        #expect(DebugState.paused(frame: "Foo.bar()", line: 42).text == "paused in Foo.bar() line 42")
        #expect(DebugState.running.text == "running")
        #expect(DebugState.ended.text == "ended")
    }

    @Test func theControlsFollowTheState() {
        #expect(DebugState.paused(frame: "f", line: 1).isPaused)
        #expect(!DebugState.running.isPaused)
        #expect(DebugState.running.canPause)
        #expect(!DebugState.paused(frame: "f", line: 1).canPause)
        #expect([DebugState.starting("x"), .running, .paused(frame: "f", line: 1)].allSatisfy { $0.canStop })
        #expect([DebugState.none, .ended, .failed("no")].allSatisfy { !$0.canStop })
    }

    @Test func eachEndingEventMovesTheState() {
        var state = DebugState.paused(frame: "f", line: 1)
        state.handle(event: "continued")
        #expect(state == .running)
        state.handle(event: "terminated")
        #expect(state == .ended)
        var exited = DebugState.running
        exited.handle(event: "exited")
        #expect(exited == .ended)
        var failed = DebugState.failed("no adapter")
        failed.handle(event: "terminated")
        #expect(failed == .failed("no adapter"))
    }

    /// debug R7: bound while paused, withdrawn on `continued` and `terminated`.
    ///
    /// A bare registry needs no window; the key monitor is not started here.
    @Test func theSteppingShortcutsLiveWhileTheSessionIsPaused() async throws {
        let registry = ShortcutRegistry()
        model.onStateChange = {
            DebugStep.sync(isPaused: self.model.state.isPaused, in: registry) { _ in }
        }
        func bound() -> [String] { registry.actions.map(\.id).sorted() }
        started()
        #expect(bound().isEmpty)
        try script.answer("threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main")]))
        try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: [frame(1, "a")]))

        _ = try await model.stopped(threadID: 1)
        #expect(bound() == ["debug.continue", "debug.stepInto", "debug.stepOut", "debug.stepOver"])
        #expect(registry.actions.compactMap(\.defaultShortcut).sorted() == ["ctrl+cmd+y", "f6", "f7", "f8"])

        model.handle(event: "continued")
        #expect(bound().isEmpty)

        _ = try await { () async throws -> DAPStackFrame? in
            try script.answer("threads", DAPThreadsResponse(threads: [DAPThread(id: 1, name: "main")]))
            try script.answer("stackTrace", DAPStackTraceResponse(stackFrames: [frame(1, "a")]))
            return try await model.stopped(threadID: 1)
        }()
        #expect(bound().count == 4)
        model.handle(event: "terminated")
        #expect(bound().isEmpty)
    }

    // MARK: - The panel's existence

    private func command(debug adapter: String?) -> RunCommand {
        RunCommand(
            id: "root:run", repo: ".", name: "run", command: "x", cwd: URL(filePath: "/p"), env: [:], problem: nil,
            debug: adapter.map { DebugCommand(adapter: $0, request: .attach, arguments: .hash([:])) })
    }

    @Test func thePanelExistsOnlyWithAnAdapterAndACommandNamingIt() throws {
        let declared = try JSONDecoder().decode(DebugCatalog.self, from: Data(#"{"swift": "lldb-dap"}"#.utf8))

        #expect(DebugFeature.wantsPanel(catalog: declared, commands: [command(debug: "swift")]))
        #expect(!DebugFeature.wantsPanel(catalog: .empty, commands: [command(debug: "swift")]))
        #expect(!DebugFeature.wantsPanel(catalog: declared, commands: [command(debug: nil)]))
        #expect(!DebugFeature.wantsPanel(catalog: declared, commands: [command(debug: "java")]))
        #expect(!DebugFeature.wantsPanel(catalog: declared, commands: []))
    }
}
