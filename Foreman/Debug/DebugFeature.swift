import Foundation
import LanguageServerProtocol
import os

/// The owner of a debug session (debug R9–R11).
///
/// M27 27.1 shows nothing: no panel, no shortcut, no toolbar item — `start(commandID:)` runs a
/// session and the `debug` log tells what happened.
///
/// Nothing runs before `start` (R10): no adapter, no port, no work while the window only sits there.
@MainActor
final class DebugFeature {
    private let workspace: Workspace
    private let run: RunFeature
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "debug")
    private(set) var catalog = DebugCatalog.empty
    private var configWatch: Task<Void, Never>?
    private var session: DAPSession?
    private var request: DebugCommand.Request?
    private var listening: Task<Void, Never>?

    init(workspace: Workspace, run: RunFeature) {
        self.workspace = workspace
        self.run = run
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges() {
                guard let self else { return }
                apply(config)
            }
        }
    }

    isolated deinit {
        configWatch?.cancel()
        listening?.cancel()
    }

    // MARK: - Config (debug R1)

    private func apply(_ config: WorkspaceConfig) {
        do {
            catalog = try config.section("debug", as: DebugCatalog.self) ?? .empty
        } catch {
            logger.error("debug section ignored: \(error.localizedDescription, privacy: .public)")
            catalog = .empty
        }
        for warning in catalog.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
    }

    // MARK: - Session (debug R2, R9, R11)

    /// Starts the command's `debug` session, ending the one that runs.
    ///
    /// Every failure is logged with the adapter's own words and ends the session; the adapter is
    /// never left running (R11).
    func start(commandID: String) async {
        await stop()
        guard let debug = run.command(commandID)?.debug else {
            logger.error("debug \(commandID, privacy: .public): unknown command, or no `debug` object")
            return
        }
        guard let adapter = catalog.adapters[debug.adapter] else {
            logger.error(
                "debug \(commandID, privacy: .public): `debug.\(debug.adapter, privacy: .public)` is not declared")
            return
        }
        let command: String
        switch adapter {
        case .command(let text):
            command = text
        case .server(let name):
            logger.error(
                "debug \(debug.adapter, privacy: .public): server `\(name, privacy: .public)` not supported yet (27.4)")
            return
        }
        let environment = await workspace.loginEnvironment()
        guard FormatterCatalog.isBinaryAvailable(command, inPath: environment["PATH"]) else {
            logger.error(
                "debug \(debug.adapter, privacy: .public): `\(FormatterCatalog.binary(of: command), privacy: .public)` not found in PATH"
            )
            return
        }
        let session: DAPSession
        do {
            session = try DAPSession.stdio(
                command: command, cwd: workspace.root, environment: environment, adapterID: debug.adapter,
                timeout: catalog.timeout)
        } catch {
            logger.error("debug \(debug.adapter, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        self.session = session
        request = debug.request
        listen(to: session)
        do {
            try await session.start(debug.request, arguments: debug.arguments)
            logger.debug("debug \(commandID, privacy: .public) started")
        } catch {
            let reason = await session.lastError.map { " (\($0))" } ?? ""
            logger.error(
                "debug \(commandID, privacy: .public): \(String(describing: error), privacy: .public)\(reason, privacy: .private)"
            )
            await stop()
        }
    }

    /// R9: `disconnect` — the program is terminated for a launch, left running for an attach.
    func stop() async {
        guard let session else { return }
        let terminate = request == .launch
        self.session = nil
        request = nil
        await session.stop(terminateDebuggee: terminate)
    }

    /// R9: the events, logged; `terminated` and `exited` end the session.
    ///
    /// A stream that finishes is the adapter's process dying.
    private func listen(to session: DAPSession) {
        listening = Task { [weak self, logger] in
            for await message in session.messages {
                switch (message.type, message.event ?? message.command) {
                case (.event, "stopped"?):
                    let stopped = try? message.decodedBody(DAPStoppedEvent.self)
                    logger.debug(
                        "stopped thread \(stopped?.threadId ?? -1): \(stopped?.reason ?? "?", privacy: .public)")
                case (.event, "output"?):
                    let output = try? message.decodedBody(DAPOutputEvent.self)
                    logger.debug("output: \(output?.output.prefix(200) ?? "", privacy: .private)")
                case (.event, "terminated"?), (.event, "exited"?):
                    logger.debug("\(message.event ?? "", privacy: .public)")
                    await self?.ended(session)
                case (.request, let command?):
                    logger.debug("reverse request \(command, privacy: .public) refused (27.5)")
                    await session.respond(to: message, success: false, message: "not supported yet")
                default:
                    break
                }
            }
            await self?.ended(session)
        }
    }

    /// The session is over for good: only the current one resets the owner.
    private func ended(_ finished: DAPSession) async {
        guard session === finished else { return }
        logger.debug("debug session ended")
        await stop()
    }
}
