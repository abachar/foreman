import Foundation
import LanguageServerProtocol
import os

/// The workspace's language servers and the documents they know about (editor R35–R39, R43).
///
/// One `LSPServer` per **command**, so two extensions naming the same one (`ts` and `tsx`, both
/// `typescript-language-server --stdio`) share a process, and a document is opened once per URI
/// however many groups show it (R37, the reference count).
///
/// It is not a `…Service`: it is owned by `EditorFeature`, created with the workspace and stopped
/// with it, not an injected capability (coding rules, naming).
@MainActor
final class LSPServers {
    /// editor R37: the pause after the last keystroke before the whole text is sent again.
    static let syncDelay = Duration.milliseconds(150)

    private let root: URL
    private let config: () -> LSPCatalog
    private let environment: () async -> [String: String]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "lsp")

    private var servers: [String: LSPServer] = [:]
    private var documents: [DocumentUri: Document] = [:]
    private var pending: [DocumentUri: Task<Void, Never>] = [:]

    /// What Foreman knows about one open file, independent of how many tabs show it.
    private struct Document {
        let url: URL
        let command: String
        let languageId: String
        var version: Int
        /// editor R37: how many tabs have it open; the last one to go sends `didClose`.
        var tabs: Int
    }

    init(root: URL, config: @escaping () -> LSPCatalog, environment: @escaping () async -> [String: String]) {
        self.root = root
        self.config = config
        self.environment = environment
    }

    /// Test seam: how many tabs hold each open document (editor R37).
    var openDocuments: [DocumentUri: Int] {
        documents.mapValues(\.tabs)
    }

    // MARK: - Documents (editor R37)

    /// editor R36, R37: the first tab on this file starts the server if needed and opens the
    /// document; the next ones only take a reference.
    func opened(_ url: URL, text: String) {
        guard let command = config().command(for: url), let languageId = Self.languageId(for: url) else { return }
        let uri = url.absoluteString
        if documents[uri] != nil {
            documents[uri]?.tabs += 1
            return
        }
        documents[uri] = Document(url: url, command: command, languageId: languageId, version: 1, tabs: 1)
        Task { [weak self] in
            guard let self, let server = await server(for: command), let document = documents[uri] else { return }
            await server.didOpen(
                uri: uri, languageId: document.languageId, version: document.version, text: text)
        }
    }

    /// editor R37, R45: debounced at the producer, so typing sends nothing synchronously.
    func changed(_ url: URL, text: @escaping () -> String) {
        let uri = url.absoluteString
        guard documents[uri] != nil else { return }
        pending[uri]?.cancel()
        pending[uri] = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.syncDelay)) != nil, let self else { return }
            pending[uri] = nil
            guard var document = documents[uri], let server = servers[document.command], server.isRunning else {
                return
            }
            document.version += 1
            documents[uri] = document
            await server.didChange(uri: uri, version: document.version, text: text())
        }
    }

    func saved(_ url: URL, text: String) {
        let uri = url.absoluteString
        guard let document = documents[uri], let server = servers[document.command] else { return }
        Task { await server.didSave(uri: uri, text: text) }
    }

    /// editor R37: the last tab on the file closes the document; the server stays for the others.
    func closed(_ url: URL) {
        let uri = url.absoluteString
        guard var document = documents[uri] else { return }
        document.tabs -= 1
        guard document.tabs <= 0 else {
            documents[uri] = document
            return
        }
        documents[uri] = nil
        pending[uri]?.cancel()
        pending[uri] = nil
        let command = document.command
        Task { [weak self] in
            await self?.servers[command]?.didClose(uri: uri)
            // editor R36: the last document of a server takes the process with it (P4).
            await self?.stopIfUnused(command)
        }
    }

    // MARK: - Go to definition (editor R43, R44)

    /// The definition of the symbol at `location`, or why nothing happens.
    ///
    /// Returns `nil` in silence when there is simply no answer — no server for the extension, the
    /// server does not provide definitions, or it found nothing. A `refused` message is for the
    /// one case the user must be told about: a definition Foreman will not open (R44).
    func definition(in url: URL, text: NSString, location: Int) async -> Definition {
        let uri = url.absoluteString
        guard let command = config().command(for: url) else { return .none }
        guard let server = await server(for: command) else {
            return servers[command]?.failure.map { Definition.refused($0) } ?? .none
        }
        let response = await server.definition(
            uri: uri, position: TextEditing.lspPosition(at: location, in: text))
        return Self.resolve(response, root: root)
    }

    /// editor R43, R44: what a server's answer becomes — the whole rule, and no server needed.
    ///
    /// Several results resolve to the first the server gave (no picker in v1); a target that is
    /// not a `file:` URL is dropped in silence (R46: a URI from a process is not trusted); a
    /// target outside the workspace is named rather than opened (R44).
    nonisolated static func resolve(_ response: DefinitionResponse, root: URL) -> Definition {
        guard let target = firstTarget(of: response) else { return .none }
        guard let url = URL(string: target.uri), url.isFileURL else { return .none }
        guard Workspace.contains(url, under: root) else {
            return .refused("Defined outside the workspace: \(url.path(percentEncoded: false))")
        }
        // LSP counts lines from zero, `Editor.open(…, line:)` from one (editor R38).
        return .found(url: url, line: target.line + 1)
    }

    /// What a `cmd+click` produced (editor R43, R44).
    nonisolated enum Definition: Equatable {
        case none
        case found(url: URL, line: Int)
        case refused(String)
    }

    /// editor R43: the first result of an answer that may hold one, many, or links.
    nonisolated static func firstTarget(of response: DefinitionResponse) -> (uri: DocumentUri, line: Int)? {
        switch response {
        case .optionA(let location):
            return (location.uri, location.range.start.line)
        case .optionB(let locations):
            return locations.first.map { ($0.uri, $0.range.start.line) }
        case .optionC(let links):
            return links.first.map { ($0.targetUri, $0.targetSelectionRange.start.line) }
        case nil:
            return nil
        }
    }

    // MARK: - Servers (editor R36, R39)

    /// editor R39: why this file has no LSP, once, or `nil` when it has one or wants none.
    func failure(for url: URL) -> String? {
        guard let command = config().command(for: url) else { return nil }
        return servers[command]?.failure
    }

    /// editor R36: the server of `command`, started on this first use; `nil` when it will not run.
    private func server(for command: String) async -> LSPServer? {
        let catalog = config()
        for warning in catalog.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        let environment = await environment()
        let server = servers[command] ?? make(command, catalog: catalog, environment: environment)
        // editor R39: the PATH is checked before anything is launched, so the banner can name the
        // binary instead of repeating the shell's complaint (the formatter's rule, R25).
        guard FormatterCatalog.isBinaryAvailable(command, inPath: environment["PATH"]) else {
            server.markBinaryMissing()
            return nil
        }
        return await server.ready() ? server : nil
    }

    private func make(_ command: String, catalog: LSPCatalog, environment: [String: String]) -> LSPServer {
        let server = LSPServer(command: command, root: root, timeout: catalog.timeout, environment: environment)
        servers[command] = server
        return server
    }

    private func stopIfUnused(_ command: String) async {
        guard !documents.values.contains(where: { $0.command == command }), let server = servers[command] else {
            return
        }
        servers[command] = nil
        await server.stop()
    }

    /// The window is closing: every process goes with it (editor R36).
    func stopAll() async {
        for task in pending.values {
            task.cancel()
        }
        pending.removeAll()
        documents.removeAll()
        let running = servers.values
        servers.removeAll()
        for server in running {
            await server.stop()
        }
    }

    /// editor R35: the LSP language id of a file, for the grammars Foreman ships (R11).
    ///
    /// Three of them are not spelled the way the grammar is: LSP calls `tsx` *typescriptreact*,
    /// `bash` *shellscript*, and has no id at all for `toml`.
    nonisolated static func languageId(for url: URL) -> String? {
        guard let language = Language.forFile(url) else { return nil }
        switch language {
        case .tsx: return "typescriptreact"
        case .bash: return "shellscript"
        case .java, .kotlin, .typescript, .javascript, .json, .yaml, .toml, .markdown, .swift, .html, .css,
            .dockerfile, .sql:
            return language.rawValue
        }
    }
}
