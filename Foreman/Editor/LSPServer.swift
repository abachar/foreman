import Foundation
import JSONRPC
import LanguageServerProtocol
import Observation
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
@Observable
@MainActor
final class LSPServer {
    /// editor R36: after `exit`, the grace before `SIGKILL` — the formatter's ladder.
    static let killDelay = FormatterLaunch.killDelay
    /// editor R39: a server that dies is started again once, and then not again.
    static let restartLimit = 1

    let command: String
    private let root: URL
    private let timeout: Duration
    /// editor R57: what the server is told, verbatim, by the three channels the protocol has —
    /// `initializationOptions`, `workspace/didChangeConfiguration`, and its own
    /// `workspace/configuration` requests. `nil` when the entry declares none.
    private(set) var settings: LSPAny?
    /// Resolved inside `start()` rather than handed in.
    ///
    /// It was the only `await` on the creation path, and having it before the registry's lookup is
    /// what let two callers create two processes for one key (2026-08-31). Nothing suspends
    /// between `servers[key]` and its insertion now.
    private let environment: @Sendable () async -> [String: String]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "lsp")

    private var process: Process?
    private var connection: JSONRPCServerConnection?
    private var input: PipeIO.Writer?
    private var events: Task<Void, Never>?
    private var starting: Task<Bool, Never>?
    private var restarts = 0
    private var isStopping = false
    /// editor R39: what the server answered `initialize` with, when it answered an error.
    ///
    /// A server that refuses to start on purpose says so **in the protocol**, not on `stderr` —
    /// `typescript-language-server` answers "Could not find a valid TypeScript installation" and
    /// exits. Swallowing that with `try?` cost two rounds of guessing (2026-08-31).
    ///
    /// `stderr` wins when there is any: a process dying under the connection throws a transport
    /// error that says nothing useful, while a server refusing on purpose answers in the protocol
    /// and writes nothing.
    private var refusal: String?
    /// editor R39: the last thing the server said on `stderr`, for the banner when it dies.
    ///
    /// A server that cannot start almost always says why in one line — a missing flag, a bad
    /// node version, a project it cannot read — and that line is worth more than anything
    /// Foreman can infer from the outside.
    private var lastError: String?

    /// What the server said it can do; `nil` until it is running (editor R39).
    private(set) var capabilities: ServerCapabilities?
    /// editor R62: the URI schemes the server provides content for (`workspace.textDocumentContent`
    /// of LSP 3.18, which the library's typed capabilities predate); empty for most servers.
    private(set) var contentSchemes: [String] = []
    /// editor R39: why the three features are absent, shown once in the tab's banner.
    ///
    /// Computed, not stored, and that is the whole point: the server's `stderr` and its `stdout`
    /// are two streams, and a process that dies on launch usually reaches EOF on the second
    /// before the first has been read. Storing the sentence at the moment of death produced "no
    /// LSP for this language" with the reason arriving milliseconds later (2026-08-31).
    var failure: String? {
        switch failureKind {
        case nil:
            return nil
        case .binaryMissing:
            return "`\(FormatterCatalog.binary(of: command))` not found in PATH"
        case .directoryMissing(let path):
            return "lsp cwd `\(path)` is not a folder in this workspace"
        case .startup:
            return Self.startupFailure(
                binary: FormatterCatalog.binary(of: command), reason: lastError ?? refusal, timeout: timeout)
        case .diedTwice:
            return Self.deathFailure(binary: FormatterCatalog.binary(of: command), reason: lastError ?? refusal)
        }
    }

    /// editor R39: which of the three ways it failed; the sentence is built when it is read.
    private enum FailureKind {
        case binaryMissing
        case directoryMissing(String)
        case startup
        case diedTwice
    }

    private var failureKind: FailureKind?
    private(set) var isRunning = false

    init(
        command: String, root: URL, timeout: Duration, settings: LSPAny? = nil,
        environment: @escaping @Sendable () async -> [String: String]
    ) {
        self.command = command
        self.root = root
        self.timeout = timeout
        self.settings = settings
        self.environment = environment
    }

    /// editor R57: the entry's `settings` changed without its command or `cwd` — the same process
    /// is told again, instead of being restarted (R36 restarts only on a change of its key).
    func update(settings new: LSPAny?) {
        guard new != settings else { return }
        settings = new
        guard isRunning, let connection else { return }
        Task { try? await Self.sendSettings(new, to: connection) }
    }

    /// editor R57, channel 2: `workspace/didChangeConfiguration` with the whole object; settings
    /// taken away are an empty object, so a server that applies them live sees the change.
    private static func sendSettings(_ settings: LSPAny?, to connection: JSONRPCServerConnection) async throws {
        try await connection.sendNotification(
            .workspaceDidChangeConfiguration(DidChangeConfigurationParams(settings: settings ?? .hash([:]))))
    }

    /// editor R57, channel 3: the answer to `workspace/configuration` — one value per item, the
    /// sub-object at the item's dotted `section` (`"java.import"` → `settings.java.import`),
    /// `null` when the path leads nowhere or there are no settings; no section is the whole object.
    nonisolated static func configuration(for items: [ConfigurationItem], in settings: LSPAny?) -> [LSPAny] {
        items.map { item in
            guard let section = item.section, !section.isEmpty else { return settings ?? .null }
            var value = settings
            for part in section.split(separator: ".", omittingEmptySubsequences: false) {
                guard case .hash(let object)? = value else { return .null }
                value = object[String(part)]
            }
            return value ?? .null
        }
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

    /// editor R62, R45: the text of a document the server provides (`jdt://…`), bounded by
    /// `lsp.timeout`; `nil` on an error, a timeout or an answer without `text`.
    func textDocumentContent(uri: DocumentUri) async -> String? {
        guard let connection, !contentSchemes.isEmpty else { return nil }
        let answer: LSPAny? = await withTimeout(timeout) {
            try? await connection.sendRequest(
                .custom("workspace/textDocumentContent", ["uri": .string(uri)], ClientRequest.NullHandler))
        }
        return Self.content(of: answer)
    }

    /// debug R1: `workspace/executeCommand`, bounded by `lsp.timeout`.
    ///
    /// `nil` on an error (logged), a timeout, or an answer of `null`. The caller reads the answer.
    func executeCommand(_ command: String, arguments: [LSPAny]? = nil) async -> LSPAny? {
        guard let connection, isRunning else { return nil }
        let params = Self.executeParams(for: command, arguments: arguments)
        let logger = logger
        let answer: LSPAny? = await withTimeout(timeout) {
            do {
                return try await connection.sendRequest(
                    .workspaceExecuteCommand(params, ClientRequest.NullHandler))
            } catch {
                logger.debug("\(command, privacy: .public): \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
        return answer ?? nil
    }

    /// debug R1: the request's params for a command id.
    nonisolated static func executeParams(for command: String, arguments: [LSPAny]? = nil) -> ExecuteCommandParams {
        ExecuteCommandParams(command: command, arguments: arguments)
    }

    /// editor R62: `{ text }` out of the answer.
    nonisolated static func content(of answer: LSPAny?) -> String? {
        guard case .hash(let object)? = answer, case .string(let text)? = object["text"] else { return nil }
        return text
    }

    // MARK: - Semantic tokens (editor R58)

    /// editor R58: the legend of a server that announced the provider; `nil` means no tokens.
    var semanticLegend: SemanticTokensLegend? {
        switch capabilities?.semanticTokensProvider {
        case .optionA(let options): return options.legend
        case .optionB(let options): return options.legend
        case nil: return nil
        }
    }

    /// editor R58: whether the server offers `full/delta`.
    var supportsSemanticDelta: Bool {
        let full: SemanticTokensClientCapabilities.Requests.FullOption?
        switch capabilities?.semanticTokensProvider {
        case .optionA(let options): full = options.full
        case .optionB(let options): full = options.full
        case nil: full = nil
        }
        switch full {
        case .optionB(let option): return option.delta == true
        case .optionA, nil: return false
        }
    }

    /// What a semantic tokens request came back with (editor R58).
    enum SemanticAnswer {
        case full(SemanticTokens)
        case delta(SemanticTokensDelta)
    }

    /// editor R58, R45: the file's tokens — a delta against `previousResultId` when the server
    /// offers it and one is known, the whole array otherwise; bounded by `lsp.timeout` like the
    /// other requests, `nil` for no answer or no provider.
    func semanticTokens(uri: DocumentUri, previousResultId: String?) async -> SemanticAnswer? {
        guard let connection, semanticLegend != nil else { return nil }
        let document = TextDocumentIdentifier(uri: uri)
        if let previousResultId, supportsSemanticDelta {
            let response: SemanticTokensDeltaResponse? = await withTimeout(timeout) {
                try? await connection.semanticTokensFullDelta(
                    SemanticTokensDeltaParams(textDocument: document, previousResultId: previousResultId))
            }
            switch response ?? nil {
            case .optionA(let tokens)?: return .full(tokens)
            case .optionB(let delta)?: return .delta(delta)
            case nil: return nil
            }
        }
        let response: SemanticTokensResponse? = await withTimeout(timeout) {
            try? await connection.semanticTokensFull(SemanticTokensParams(textDocument: document))
        }
        return (response ?? nil).map(SemanticAnswer.full)
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
        let environment = await environment()
        // editor R39: the PATH is checked before anything is launched, so the banner can name the
        // binary instead of repeating the shell's complaint (the formatter's rule, R25).
        guard FormatterCatalog.isBinaryAvailable(command, inPath: environment["PATH"]) else {
            failed(.binaryMissing)
            return false
        }
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
            failed(.startup)
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
            failed(.startup)
            await stop()
            return false
        }
        capabilities = response.response.capabilities
        contentSchemes = response.contentSchemes
        failureKind = nil
        isRunning = true
        try? await connection.initialized(InitializedParams())
        // editor R57: a server that reads its settings after `initialized` (jdtls does) hears
        // them now; one that read `initializationOptions` hears the same object twice, harmlessly.
        if let settings {
            try? await Self.sendSettings(settings, to: connection)
        }
        logger.debug("\(response.response.serverInfo?.name ?? self.command, privacy: .private) ready")
        return true
    }

    /// editor R39: `initialize` bounded by `lsp.timeout`; `nil` when it refused or never answered.
    private func handshake(_ connection: JSONRPCServerConnection) async -> Handshake? {
        let params = Self.initializeParams(root: root, settings: settings)
        return await withTimeout(timeout) { [weak self] in
            do {
                return try await connection.sendRequest(.initialize(params, ClientRequest.NullHandler))
            } catch {
                // editor R39: an error answer is the server telling us why, in its own words.
                await self?.refused(by: error)
                return nil
            }
        }
    }

    /// editor R62: the answer to `initialize`, read once as the library's typed response and once
    /// for the one 3.18 field it does not model.
    nonisolated struct Handshake: Decodable, Sendable {
        let response: InitializationResponse
        let contentSchemes: [String]

        private enum Keys: String, CodingKey { case capabilities, workspace, textDocumentContent, schemes }

        init(from decoder: any Decoder) throws {
            response = try InitializationResponse(from: decoder)
            let root = try decoder.container(keyedBy: Keys.self)
            let capabilities = try? root.nestedContainer(keyedBy: Keys.self, forKey: .capabilities)
            let workspace = try? capabilities?.nestedContainer(keyedBy: Keys.self, forKey: .workspace)
            let content = try? workspace?.nestedContainer(keyedBy: Keys.self, forKey: .textDocumentContent)
            contentSchemes = (try? content?.decode([String].self, forKey: .schemes)) ?? []
        }
    }

    /// editor R61: the `initializationOptions` — the user's settings plus Foreman's capability key.
    ///
    /// `extendedClientCapabilities.classFileContentsSupport` is merged one level under
    /// `extendedClientCapabilities`, the key `jdtls` reads before it answers a `jdt://` location.
    /// The user's own keys there are kept; Foreman's wins.
    nonisolated static func initializationOptions(settings: LSPAny?) -> LSPAny {
        var options: [String: LSPAny] = [:]
        if case .hash(let object)? = settings { options = object }
        var extended: [String: LSPAny] = [:]
        if case .hash(let object)? = options["extendedClientCapabilities"] { extended = object }
        extended["classFileContentsSupport"] = .bool(true)
        options["extendedClientCapabilities"] = .hash(extended)
        return .hash(options)
    }

    /// editor R38, R57: what `initialize` announces — the root, the settings as
    /// `initializationOptions` (channel 1), and `workspace.configuration` so a server that pulls
    /// its settings asks for them (channel 3) instead of assuming it has none.
    nonisolated static func initializeParams(root: URL, settings: LSPAny?) -> InitializeParams {
        InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            clientInfo: InitializeParams.ClientInfo(name: "Foreman"),
            locale: nil, rootPath: nil, rootUri: root.absoluteString,
            initializationOptions: initializationOptions(settings: settings),
            // editor R38: nothing is announced about position encoding, and that is the point —
            // a client silent on `general.positionEncodings` is UTF-16 by the specification, which
            // is what `NSString` already counts. The library models no such capability anyway.
            capabilities: ClientCapabilities(
                workspace: ClientCapabilities.Workspace(
                    applyEdit: false, workspaceEdit: nil, didChangeConfiguration: nil, didChangeWatchedFiles: nil,
                    symbol: nil, executeCommand: nil, workspaceFolders: nil, configuration: true, semanticTokens: nil),
                // editor R58: full and delta, relative, one line per token, no overlap; the
                // standard type and modifier lists — the server's legend names the rest.
                textDocument: TextDocumentClientCapabilities(
                    semanticTokens: SemanticTokensClientCapabilities(
                        requests: .init(range: false, delta: true), overlappingTokenSupport: false,
                        multilineTokenSupport: false)),
                window: nil, general: nil, experimental: nil),
            trace: nil, workspaceFolders: nil)
    }

    private func refused(by error: any Error) {
        refusal = Self.refusalMessage(of: error)
    }

    /// editor R39: the sentence out of a failed `initialize`.
    ///
    /// The protocol wraps it in its own boilerplate ("Request initialize failed with message: "),
    /// which says nothing the banner does not already say — the server's own sentence follows it.
    nonisolated static func refusalMessage(of error: any Error) -> String? {
        let text = String(describing: error)
        guard let range = text.range(of: "message: ", options: .backwards) else {
            return meaningfulLine(of: text)
        }
        var message = String(text[range.upperBound...])
        if let quote = message.range(of: "\", data:", options: .backwards) {
            message = String(message[..<quote.lowerBound])
        }
        message = message.trimmingCharacters(in: CharacterSet(charactersIn: "\"() "))
        return message.isEmpty ? meaningfulLine(of: text) : String(message.prefix(200))
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

    /// editor R40: diagnostics arrive here unasked; editor R57: a server asking for its settings
    /// is answered, with `null`s when it has none; everything else is a log.
    private func handle(_ event: ServerEvent) {
        switch event {
        case .notification(.textDocumentPublishDiagnostics(let params)):
            onDiagnostics?(params.uri, params.version, params.diagnostics)
        case .request(_, .workspaceConfiguration(let params, let handler)):
            // Answered **always**, settings or not: a request left pending is a server waiting
            // for a reply that never comes, which is what every server got before 2026-10-17.
            let answer = Self.configuration(for: params.items, in: settings)
            Task { await handler(.success(answer)) }
        case .error(let error):
            logger.debug("\(self.command, privacy: .private): \(error.localizedDescription, privacy: .private)")
        case .notification, .request:
            break
        }
    }

    /// editor R39: a crash costs the language its LSP after the second one.
    private func serverEnded() {
        guard !isStopping else { return }
        clear()
        restarts += 1
        if restarts > Self.restartLimit {
            failureKind = .diedTwice
        }
        logger.debug("\(self.command, privacy: .private) ended (\(self.restarts) restarts)")
    }

    /// editor R39: what the banner says when the server never answered `initialize`.
    ///
    /// Its own words when it left any, the timeout otherwise — "did not answer in 10 s" is true
    /// and useless when the server printed the reason on the way out.
    nonisolated static func startupFailure(binary: String, reason: String?, timeout: Duration) -> String {
        if let reason, !reason.isEmpty {
            return "`\(binary)`: \(reason)"
        }
        let seconds = Double(timeout.components.seconds)
        return "`\(binary)` did not answer in \(seconds.formatted()) s"
    }

    /// editor R39: what the banner says when the server died twice.
    ///
    /// It ends with what to do, because there is exactly one thing to do and no way to guess it:
    /// R39 gives up on the language for the life of the window, and the login environment is
    /// resolved once per window too (`terminal` R3) — so a user who has just fixed their `PATH`
    /// sees no change until they reopen it. Met on 2026-08-31, twice in a row.
    nonisolated static func deathFailure(binary: String, reason: String?) -> String {
        let advice = "reopen the window to try again"
        guard let reason, !reason.isEmpty else {
            return "`\(binary)` stopped twice — \(advice)"
        }
        return "`\(binary)` stopped twice (\(reason)) — \(advice)"
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

    /// editor R36, R39: the `cwd` the entry names is not a folder under the workspace.
    func markDirectoryMissing(_ path: String) {
        failed(.directoryMissing(path))
    }

    private func failed(_ kind: FailureKind) {
        failureKind = kind
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
