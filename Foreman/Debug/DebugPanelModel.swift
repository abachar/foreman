import Foundation
import JSONRPC
import LanguageServerProtocol
import Observation

/// One frame of a thread's stack (debug R6); greyed and not selectable without a source to open.
nonisolated struct DebugFrame: Equatable, Identifiable, Sendable {
    let frame: DAPStackFrame

    var id: Int { frame.id }
    var name: String { frame.name }

    var isSelectable: Bool {
        !(frame.source?.path ?? "").isEmpty
    }

    /// `Foo.swift:42` — the source's name, else its path's last component.
    var location: String? {
        guard let source = frame.source else { return nil }
        let file = source.name ?? source.path.map { ($0 as NSString).lastPathComponent }
        return file.map { "\($0):\(frame.line)" }
    }
}

/// A thread of the program and its frames, asked when it is first opened (debug R6).
nonisolated struct DebugThread: Equatable, Identifiable, Sendable {
    /// debug R6: `levels` of a `stackTrace`, and the page of the *more…* row.
    static let page = 100

    let id: Int
    let name: String
    /// `nil` until asked.
    private(set) var frames: [DebugFrame]?
    private(set) var hasMore = false

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// The next page of an answer; there is more when `totalFrames` says so, else when a page came back full.
    mutating func append(_ response: DAPStackTraceResponse) {
        let all = (frames ?? []) + response.stackFrames.map(DebugFrame.init)
        frames = all
        if let total = response.totalFrames {
            hasMore = !response.stackFrames.isEmpty && all.count < total
        } else {
            hasMore = response.stackFrames.count >= Self.page
        }
    }
}

/// A scope or a variable of the selected frame: children fetched on the first expansion only
/// (debug R6, R10), `indexedVariables` past a page fetched by pages.
@Observable
@MainActor
final class DebugVariable: Identifiable {
    /// debug R6: `indexedVariables` beyond this are fetched by this many.
    static let page = 100

    let id = UUID()
    let name: String
    let value: String
    let type: String?
    let reference: Int
    /// Items still to ask for an array-like value; `0` for a plain one.
    let indexed: Int
    var children: [DebugVariable] = []
    var isExpanded = false
    private(set) var isLoaded = false
    fileprivate(set) var isLoading = false
    private var fetched = 0

    init(name: String, value: String = "", type: String? = nil, reference: Int, indexed: Int = 0) {
        self.name = name
        self.value = value
        self.type = type
        self.reference = reference
        self.indexed = indexed
    }

    convenience init(_ variable: DAPVariable) {
        self.init(
            name: variable.name, value: variable.value, type: variable.type, reference: variable.variablesReference,
            indexed: variable.indexedVariables ?? 0)
    }

    var isExpandable: Bool {
        reference > 0
    }

    private var isPaged: Bool {
        indexed > Self.page
    }

    /// The *more…* row: a paged value with items left.
    var hasMore: Bool {
        isPaged && isLoaded && fetched < indexed
    }

    /// The next request of this node, or `nil` when nothing is left to ask.
    fileprivate var nextRequest: DAPVariablesArguments? {
        guard !isLoading, isExpandable, !isLoaded || hasMore else { return nil }
        return DAPVariablesArguments(
            variablesReference: reference, start: isPaged ? fetched : nil, count: isPaged ? Self.page : nil)
    }

    fileprivate func received(_ response: DAPVariablesResponse) {
        children += response.variables.map(DebugVariable.init)
        fetched += response.variables.count
        isLoaded = true
        if response.variables.isEmpty {
            // An adapter that answers nothing ends the paging.
            fetched = max(fetched, indexed)
        }
    }
}

/// What the Debug panel shows (debug R6), fed by the session's events through `DebugFeature` and
/// asking the adapter through `send`, the only thing it knows of it.
///
/// An empty value until a session starts (R10): nothing is requested before `begin`. Nothing is
/// kept across stops — each `stopped` rebuilds the threads, the frames and the scopes.
@Observable
@MainActor
final class DebugPanelModel {
    /// `session.send`: a request by name and the adapter's answer.
    typealias Send = (_ command: String, _ arguments: LSPAny) async throws -> LSPAny

    var state = DebugState.none {
        didSet {
            if state != oldValue { onStateChange?() }
        }
    }
    /// debug R11: why a stop marks nothing, beside the state.
    var notice: String?
    private(set) var threads: [DebugThread] = []
    private(set) var stoppedThread: Int?
    private(set) var selectedFrame: Int?
    private(set) var scopes: [DebugVariable] = []
    private(set) var console = DebugConsole()
    var expandedThreads: Set<Int> = []
    @ObservationIgnored var send: Send?
    @ObservationIgnored var onStateChange: (() -> Void)?
    /// A stop, a resume or a new session makes the answers still in flight stale.
    @ObservationIgnored private var generation = 0

    // MARK: - Session

    /// A session starts: the previous one's console and stack are gone.
    func begin(_ state: DebugState, send: @escaping Send) {
        clearStop()
        console = DebugConsole()
        self.send = send
        self.state = state
    }

    /// The `attach` or `launch` answered, and no stop beat it.
    func started() {
        if case .starting = state { state = .running }
    }

    func end() {
        send = nil
        clearStop()
        state.handle(event: "terminated")
    }

    func fail(_ message: String) {
        send = nil
        clearStop()
        state = .failed(message)
    }

    /// `continued` and the requests that run the program again: nothing of the stop is kept.
    func resumed() {
        clearStop()
        if state.isPaused { state = .running }
    }

    func handle(event name: String) {
        if name == "continued" { clearStop() }
        state.handle(event: name)
    }

    private func clearStop() {
        generation += 1
        threads = []
        selectedFrame = nil
        scopes = []
        expandedThreads = []
        notice = nil
    }

    // MARK: - Stops (debug R5, R6)

    /// `threads`, then the stopping thread's first 100 frames; the top frame is selected and returned.
    ///
    /// Without a `threadId` (`allThreadsStopped`) the first thread is the one.
    func stopped(threadID: Int?) async throws -> DAPStackFrame? {
        clearStop()
        let current = generation
        var list = try await ask("threads", DAPEmpty(), as: DAPThreadsResponse.self).threads.map {
            DebugThread(id: $0.id, name: $0.name)
        }
        guard current == generation, let id = threadID ?? list.first?.id else { return nil }
        if !list.contains(where: { $0.id == id }) {
            list.append(DebugThread(id: id, name: "Thread \(id)"))
        }
        let trace = try await ask(
            "stackTrace", DAPStackTraceArguments(threadId: id, levels: DebugThread.page), as: DAPStackTraceResponse.self
        )
        guard current == generation, let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        list[index].append(trace)
        threads = list
        stoppedThread = id
        expandedThreads = [id]
        guard let top = trace.stackFrames.first else { return nil }
        selectedFrame = top.id
        state = .paused(frame: top.name, line: top.line)
        return top
    }

    /// The first page of a thread's frames, or the next one (*more…*).
    func loadFrames(of thread: Int) async {
        guard let index = threads.firstIndex(where: { $0.id == thread }),
            threads[index].frames == nil || threads[index].hasMore
        else { return }
        let current = generation
        let start = threads[index].frames?.count ?? 0
        let arguments = DAPStackTraceArguments(threadId: thread, startFrame: start, levels: DebugThread.page)
        do {
            let trace = try await ask("stackTrace", arguments, as: DAPStackTraceResponse.self)
            guard current == generation, let index = threads.firstIndex(where: { $0.id == thread }),
                (threads[index].frames?.count ?? 0) == start
            else { return }
            threads[index].append(trace)
        } catch {
            log("stackTrace: \(Self.describe(error))")
        }
    }

    func select(frame id: Int) {
        selectedFrame = id
        notice = nil
    }

    // MARK: - Variables (debug R6)

    /// The scopes of a frame; the first one, when cheap, is opened (the locals).
    func loadScopes(of frame: Int) async {
        let current = generation
        do {
            let answer = try await ask("scopes", DAPScopesArguments(frameId: frame), as: DAPScopesResponse.self)
            guard current == generation, selectedFrame == frame else { return }
            scopes = answer.scopes.map { DebugVariable(name: $0.name, reference: $0.variablesReference) }
            if let first = scopes.first, let scope = answer.scopes.first, !scope.expensive {
                first.isExpanded = true
                await load(first)
            }
        } catch {
            log("scopes: \(Self.describe(error))")
        }
    }

    /// The children of a node (its next page, for a paged one): once, and only when asked for.
    func load(_ node: DebugVariable) async {
        guard let request = node.nextRequest else { return }
        node.isLoading = true
        defer { node.isLoading = false }
        do {
            node.received(try await ask("variables", request, as: DAPVariablesResponse.self))
        } catch {
            log("variables: \(Self.describe(error))")
        }
    }

    // MARK: - Console (debug R6)

    func output(_ event: DAPOutputEvent) {
        console.append(event.output, category: event.category)
    }

    /// `evaluate { context: "repl" }` in the selected frame; the answer, or the adapter's error, is appended.
    func evaluate(_ expression: String) async {
        let text = expression.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        console.append("> \(text)", kind: .secondary)
        do {
            let answer = try await ask(
                "evaluate", DAPEvaluateArguments(expression: text, frameId: selectedFrame, context: "repl"),
                as: DAPEvaluateResponse.self)
            console.append(answer.result, kind: .plain)
        } catch {
            console.append(Self.describe(error), kind: .error)
        }
    }

    // MARK: - Requests

    private func ask<A: Encodable, B: Decodable>(_ command: String, _ arguments: A, as type: B.Type) async throws -> B {
        guard let send else { throw DAPSession.Failure.closed }
        return try await send(command, LSPAny(encoding: arguments)).decoded(type)
    }

    /// The adapter's own sentence for a refusal, else what happened.
    nonisolated static func describe(_ error: any Error) -> String {
        if case DAPSession.Failure.rejected(_, let message) = error { return message }
        return String(describing: error)
    }

    /// A refusal of the adapter, in the console.
    func report(_ message: String) {
        console.append(message, kind: .error)
    }

    private func log(_ text: String) {
        console.append(text, kind: .secondary)
    }
}
