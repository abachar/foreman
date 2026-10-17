import Foundation
import JSONRPC
import LanguageServerProtocol
import os

/// A launch (debug R3 amended 2026-10-18, R8): the arguments `jdtls` completes, and the program the
/// adapter asks a terminal for.
extension DebugFeature {
    /// The arguments of the adapter's `launch`.
    ///
    /// Debug R3: for a `launch` of a `server` adapter, the user's `arguments` with the main class and
    /// the classpath the language server knows, then the merge of `DebugLaunch`. Anything else is the
    /// user's object, verbatim (R2). Throws R11's sentence.
    func launchArguments(
        for command: RunCommand, debug: DebugCommand, adapter: DebugCatalog.Adapter
    ) async throws
        -> LSPAny
    {
        guard debug.request == .launch, adapter.isServer, case .hash(let user) = debug.arguments else {
            return debug.arguments
        }
        let key = debug.adapter
        var mainClass = user["mainClass"]?.text
        var resolved: [String: LSPAny] = [:]
        if user["mainClass"] == nil || user["mainClass"] == .null {
            let answer = try await ask(DebugLaunch.resolveMainClassCommand, [], extensionKey: key)
            let options = try DebugLaunch.mainClasses(from: answer)
            guard let chosen = DebugLaunch.choose(from: options, folderName: command.cwd.lastPathComponent) else {
                throw DebugLaunch.Problem(description: "no main class found")
            }
            if options.count > 1 {
                let names = options.map { "\($0.projectName ?? "?"): \($0.mainClass)" }.joined(separator: ", ")
                logger.info(
                    "debug \(command.id, privacy: .public): \(options.count) main classes (\(names, privacy: .private)), taking \(chosen.mainClass, privacy: .private)"
                )
            }
            mainClass = chosen.mainClass
            resolved["mainClass"] = .string(chosen.mainClass)
            resolved["projectName"] = chosen.projectName.map { .string($0) }
        }
        if user["classPaths"] == nil || user["classPaths"] == .null, let mainClass {
            let projectName = user["projectName"]?.text ?? resolved["projectName"]?.text
            let answer = try await ask(
                DebugLaunch.resolveClasspathCommand, [.string(mainClass), projectName.map { .string($0) } ?? .null],
                extensionKey: key)
            let classpath = try DebugLaunch.classpath(from: answer)
            resolved["classPaths"] = .array(classpath.classPaths.map { .string($0) })
            resolved["modulePaths"] = .array(classpath.modulePaths.map { .string($0) })
        }
        return DebugLaunch.merge(arguments: debug.arguments, resolved: resolved, cwd: command.cwd, env: command.env)
    }

    /// One command of the language server; its silence is said in R11's words.
    private func ask(_ command: String, _ arguments: [LSPAny], extensionKey key: String) async throws -> LSPAny? {
        let answer = await editor.lsp.executeCommand(command, arguments: arguments, extensionKey: key)
        if answer == nil {
            let declaration = editor.lsp.declaration(forExtension: key)
            if !declaration.declared {
                throw DebugLaunch.Problem(
                    description: "`debug.\(key)` needs a language server: `lsp.\(key)` is not declared")
            }
            if let failure = declaration.failure {
                throw DebugLaunch.Problem(description: failure)
            }
        }
        return answer
    }

    /// debug R8: the program runs in the command's Run sub-tab; the reply carries the shell's process id.
    ///
    /// `kind: "external"` is served the same way (Foreman has one terminal). An `env` value of `null`
    /// means "unset" in the protocol: only the others are passed.
    func runInTerminal(_ message: DAPMessage, in session: DAPSession) async {
        guard self.session === session, let commandID, let command = run.command(commandID),
            let request = try? message.decodedArguments(DAPRunInTerminalArguments.self), !request.args.isEmpty
        else {
            await session.respond(to: message, success: false, message: "Foreman cannot run this program")
            return
        }
        let cwd = request.cwd.isEmpty ? command.cwd : URL(filePath: request.cwd, directoryHint: .isDirectory)
        let pid = run.runDebuggee(
            commandID: commandID, commandLine: DebugLaunch.commandLine(request.args), cwd: cwd,
            env: (request.env ?? [:]).compactMapValues { $0 })
        let body = try? LSPAny(encoding: DAPRunInTerminalResponse(processId: pid.map(Int.init)))
        await session.respond(to: message, success: true, body: body)
    }
}
