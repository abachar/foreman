import Foundation
import JSONRPC
import LanguageServerProtocol
import os

/// One language server process, and the connection to it (editor R36, R39).
///
/// The process is the user's command, launched exactly like a formatter (`FormatterLaunch`'s
/// invocation, editor R26 and R46) — the difference is that this one lives: it is spoken to and
/// listened to until the last tab of its language closes.
///
/// What it does **not** do is as deliberate as what it does: no completion (editor R35–R46 leave
/// it out), no reopening of documents after a crash (`LSPServers` re-sends `didOpen` on the next
/// use, which needs no state kept here), and no restart beyond the single one of R39.
@MainActor
final class LSPServer {
    /// editor R36: after `exit`, the grace before `SIGKILL` — the formatter's ladder.
    static let killDelay = FormatterLaunch.killDelay
    /// editor R39: a server that dies is started again once, and then not again.
    static let restartLimit = 1

    let command: String
    private let root: URL
    private let timeout: Duration
    private let environment: [String: String]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "lsp")

    private var process: Process?
    private var connection: JSONRPCServerConnection?
    private var input: PipeIO.Writer?
    private var events: Task<Void, Never>?
    private var starting: Task<Bool, Never>?
    private var restarts = 0
    private var isStopping = false
    /// editor R39: the last thing the server said on `stderr`, for the banner when it dies.
    ///
    /// A server that cannot start almost always says why in one line — a missing flag, a bad
    /// node version, a project it cannot read — and that line is worth more than anything
    /// Foreman can infer from the outside.
    private var lastError: String?

    /// What the server said it can do; `nil` until it is running (editor R39).
    private(set) var capabilities: ServerCapabilities?
    /// editor R39: why the three features are absent, shown once in the tab's banner.
    private(set) var failure: String?
    private(set) var isRunning = false

    init(command: String, root: URL, timeout: Duration, environment: [String: String]) {
        self.command = command
        self.root = root
        self.timeout = timeout
        self.environment = environment
    }

    /// editor R36: started at the first use, never before; concurrent callers share one attempt.
    func ready() async -> Bool {
        if isRunning {
            return true
        }
        if let starting {
            return await starting.value
        }
        guard restarts <= Self.restartLimit else { return false }
        let attempt = Task { await start() }
        starting = attempt
        let started = await attempt.value
        starting = nil
        return started
    }

    /// editor R40: the server pushed diagnostics for a URI; set by `LSPServers`.
    var onDiagnostics: ((DocumentUri, Int?, [Diagnostic]) -> Void)?

    /// editor R39: the server announced this feature.
    var hasDefinitionProvider: Bool {
        Self.providesDefinition(capabilities)
    }

    /// editor R39: the server announced hover.
    var hasHoverProvider: Bool {
        Self.providesHover(capabilities)
    }

    /// editor R39: hover, announced as a plain boolean or as an options object.
    nonisolated static func providesHover(_ capabilities: ServerCapabilities?) -> Bool {
        switch capabilities?.hoverProvider {
        case .optionA(let flag): return flag
        case .optionB: return true
        case nil: return false
        }
    }

    /// editor R39: nothing is offered that the server did not announce.
    ///
    /// A capability comes either as a plain `true`/`false` or as an options object; an options
    /// object is itself the announcement, so only the boolean can say no.
    nonisolated static func providesDefinition(_ capabilities: ServerCapabilities?) -> Bool {
        switch capabilities?.definitionProvider {
        case .optionA(let flag): return flag
        case .optionB: return true
        case nil: return false
        }
    }

    // MARK: - Documents (editor R37)

    func didOpen(uri: DocumentUri, languageId: String, version: Int, text: String) async {
        try? await connection?.textDocumentDidOpen(
            DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(uri: uri, languageId: languageId, version: version, text: text)))
    }

    /// editor R37: the whole text, never a delta.
    func didChange(uri: DocumentUri, version: Int, text: String) async {
        try? await connection?.textDocumentDidChange(
            DidChangeTextDocumentParams(
                uri: uri, version: version,
                contentChanges: [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: text)]))
    }

    func didClose(uri: DocumentUri) async {
        try? await connection?.textDocumentDidClose(DidCloseTextDocumentParams(uri: uri))
    }

    /// editor R37: sent only when the server asked for it in its sync options.
    func didSave(uri: DocumentUri, text: String) async {
        // A server that answered with a bare sync kind asked for no save notification at all.
        guard case .optionA(let options) = capabilities?.textDocumentSync, let save = options.effectiveSave else {
            return
        }
        try? await connection?.textDocumentDidSave(
            DidSaveTextDocumentParams(uri: uri, text: save.includeText == true ? text : nil))
    }

    // MARK: - Requests (editor R43)

    /// editor R43, R45: bounded by `lsp.timeout` like the handshake — a server that never answers
    /// makes `cmd+click` do nothing, it does not leave a request pending for the session.
    func definition(uri: DocumentUri, position: Position) async -> DefinitionResponse {
        guard let connection, hasDefinitionProvider else { return nil }
        let response: DefinitionResponse? = await withTimeout(timeout) {
            try? await connection.definition(TextDocumentPositionParams(uri: uri, position: position))
        }
        return response ?? nil
    }

    /// editor R42, R45: bounded like the rest; a slow server makes the popover late, never stuck.
    func hover(uri: DocumentUri, position: Position) async -> HoverResponse {
        guard let connection, hasHoverProvider else { return nil }
        let response: HoverResponse? = await withTimeout(timeout) {
            try? await connection.hover(TextDocumentPositionParams(uri: uri, position: position))
        }
        return response ?? nil
    }

    // MARK: - Lifecycle

    /// editor R36: `shutdown`, `exit`, then `SIGTERM` and `SIGKILL` a second later.
    func stop() async {
        isStopping = true
        defer { isStopping = false }
        if isRunning, let connection {
            // A server that is already wedged must not hold the window's close: one second, then
            // the signals do the talking.
            await withTimeout(.seconds(1)) {
                try? await connection.shutdown()
                try? await connection.exit()
            }
        }
        events?.cancel()
        input?.close()
        if let process, process.isRunning {
            process.terminate()
            try? await Task.sleep(for: Self.killDelay)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        clear()
    }

    private func start() async -> Bool {
        let invocation = FormatterLaunch.invocation(command: command, cwd: root, environment: environment)
        let process = Process()
        process.executableURL = URL(filePath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.cwd
        process.environment = invocation.environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            failed("`\(FormatterCatalog.binary(of: command))` could not be started")
            return false
        }
        self.process = process
        let writer = PipeIO.Writer(stdin.fileHandleForWriting)
        input = writer
        let connection = JSONRPCServerConnection(
            dataChannel: DataChannel(
                writeHandler: { await writer.write($0) },
                dataSequence: PipeIO.chunks(stdout.fileHandleForReading)))
        self.connection = connection
        drainDiagnostics(stderr)
        listen(connection)
        guard let response = await handshake(connection) else {
            failed(
                Self.startupFailure(
                    binary: FormatterCatalog.binary(of: command), stderr: lastError, timeout: timeout))
            await stop()
            return false
        }
        capabilities = response.capabilities
        failure = nil
        isRunning = true
        try? await connection.initialized(InitializedParams())
        logger.debug("\(response.serverInfo?.name ?? self.command, privacy: .private) ready")
        return true
    }

    /// editor R39: `initialize` bounded by `lsp.timeout`; `nil` when it did not answer in time.
    private func handshake(_ connection: JSONRPCServerConnection) async -> InitializationResponse? {
        let params = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            clientInfo: InitializeParams.ClientInfo(name: "Foreman"),
            locale: nil, rootPath: nil, rootUri: root.absoluteString, initializationOptions: nil,
            // editor R38: nothing is announced about position encoding, and that is the point —
            // a client silent on `general.positionEncodings` is UTF-16 by the specification, which
            // is what `NSString` already counts. The library models no such capability anyway.
            capabilities: ClientCapabilities(
                workspace: nil, textDocument: nil, window: nil, general: nil, experimental: nil),
            trace: nil, workspaceFolders: nil)
        return await withTimeout(timeout) { try? await connection.initialize(params) }
    }

    /// The event loop, and the death notice: the sequence ends when the child's `stdout` reaches
    /// EOF, so falling out of the loop *is* the crash detection — no `terminationHandler` needed.
    private func listen(_ connection: JSONRPCServerConnection) {
        events = Task { [weak self] in
            for await event in await connection.eventSequence {
                self?.handle(event)
            }
            self?.serverEnded()
        }
    }

    /// editor R40: diagnostics arrive here unasked; everything else is a log.
    private func handle(_ event: ServerEvent) {
        switch event {
        case .notification(.textDocumentPublishDiagnostics(let params)):
            onDiagnostics?(params.uri, params.version, params.diagnostics)
        case .error(let error):
            logger.debug("\(self.command, privacy: .private): \(error.localizedDescription, privacy: .private)")
        case .notification, .request:
            break
        }
    }

    /// editor R39: a crash costs the language its LSP after the second one.
    private func serverEnded() {
        guard !isStopping else { return }
        let reason = lastError
        clear()
        restarts += 1
        if restarts > Self.restartLimit {
            failure = Self.deathFailure(binary: FormatterCatalog.binary(of: command), stderr: reason)
        }
        logger.debug("\(self.command, privacy: .private) ended (\(self.restarts) restarts)")
    }

    /// editor R39: what the banner says when the server never answered `initialize`.
    ///
    /// Its own words when it left any, the timeout otherwise — "did not answer in 10 s" is true
    /// and useless when the server printed the reason on the way out.
    nonisolated static func startupFailure(binary: String, stderr: String?, timeout: Duration) -> String {
        if let stderr, !stderr.isEmpty {
            return "`\(binary)`: \(stderr)"
        }
        let seconds = Double(timeout.components.seconds)
        return "`\(binary)` did not answer in \(seconds.formatted()) s"
    }

    /// editor R39: what the banner says when the server died twice.
    nonisolated static func deathFailure(binary: String, stderr: String?) -> String {
        guard let stderr, !stderr.isEmpty else {
            return "`\(binary)` stopped twice — no LSP for this language"
        }
        return "`\(binary)` stopped twice — \(stderr)"
    }

    /// editor R39: the line of `stderr` worth showing — the last one that says something.
    ///
    /// Servers are chatty and the useful line is the last, not the first: `node` prefixes its own
    /// noise, and a usage message ends with what was actually wrong.
    nonisolated static func meaningfulLine(of output: String) -> String? {
        let line =
            output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let line, line.count > 1 else { return nil }
        return line.count > 200 ? String(line.prefix(200)) + "…" : line
    }

    /// editor R39: a server's `stderr` is a log, never a banner — it is noisy by design and it can
    /// quote the file, which never reaches a log (coding rules).
    private func drainDiagnostics(_ pipe: Pipe) {
        Task { [weak self, logger, command] in
            for await chunk in PipeIO.chunks(pipe.fileHandleForReading) {
                guard let text = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                else { continue }
                logger.debug("\(command, privacy: .private): \(text.prefix(200), privacy: .private)")
                // editor R39: kept for the banner, not shown yet — a running server writes here
                // constantly and only its last word matters, and only if it dies.
                self?.lastError = Self.meaningfulLine(of: text)
            }
        }
    }

    /// editor R39: the command's binary is not in the `PATH` — nothing was launched.
    func markBinaryMissing() {
        failed("`\(FormatterCatalog.binary(of: command))` not found in PATH")
    }

    private func failed(_ reason: String) {
        failure = reason
        clear()
    }

    private func clear() {
        capabilities = nil
        isRunning = false
        connection = nil
        input = nil
        process = nil
    }

    /// The value `body` returned, or `nil` when `limit` ran out first.
    private func withTimeout<T: Sendable>(
        _ limit: Duration, _ body: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func withTimeout(_ limit: Duration, _ body: @escaping @Sendable () async -> Void) async {
        let _: Bool? = await withTimeout(limit) {
            await body()
            return true
        }
    }
}
