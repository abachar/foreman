import Foundation
import JSONRPC
import LanguageServerProtocol

/// What a launch through a language server needs.
///
/// Debug R3 (amended 2026-10-18), R8, R9: the two answers of `jdtls`' debug bundle decoded, the
/// arguments merged, the command line quoted.
///
/// Pure values and functions: the server is asked by `DebugFeature+Launch`, and `java-debug`'s names
/// (`mainClass`, `projectName`, `classPaths`, `modulePaths`) are its own, as in `vscode-java-debug`.
nonisolated enum DebugLaunch {
    static let resolveMainClassCommand = "vscode.java.resolveMainClass"
    static let resolveClasspathCommand = "vscode.java.resolveClasspath"

    /// debug R11: the sentence of the banner.
    struct Problem: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    /// One element of the answer of `vscode.java.resolveMainClass` (`IMainClassOption`).
    ///
    struct MainClass: Equatable {
        let mainClass: String
        let projectName: String?
        let filePath: String?
    }

    /// The answer of `vscode.java.resolveClasspath`, a pair `[modulePaths, classPaths]`.
    ///
    struct Classpath: Equatable {
        let modulePaths: [String]
        let classPaths: [String]
    }

    // MARK: - The two answers

    /// An array of `{ mainClass, projectName?, filePath? }`; any other shape is a problem quoting the answer.
    static func mainClasses(from answer: LSPAny?) throws -> [MainClass] {
        guard case .array(let elements)? = answer else { throw unexpected(resolveMainClassCommand, answer) }
        return try elements.map { element in
            guard case .hash(let object) = element, case .string(let name)? = object["mainClass"] else {
                throw unexpected(resolveMainClassCommand, answer)
            }
            return MainClass(
                mainClass: name, projectName: object["projectName"]?.text, filePath: object["filePath"]?.text)
        }
    }

    /// The class of the project named like the command's folder, else the first.
    static func choose(from options: [MainClass], folderName: String) -> MainClass? {
        options.first { $0.projectName == folderName } ?? options.first
    }

    /// A two-element array of string arrays (`null` standing for none); any other shape is a problem.
    static func classpath(from answer: LSPAny?) throws -> Classpath {
        guard case .array(let pair)? = answer, pair.count >= 2,
            let modules = strings(pair[0]), let classes = strings(pair[1])
        else { throw unexpected(resolveClasspathCommand, answer) }
        return Classpath(modulePaths: modules, classPaths: classes)
    }

    private static func strings(_ value: LSPAny) -> [String]? {
        switch value {
        case .null: return []
        case .array(let elements):
            let texts = elements.compactMap(\.text)
            return texts.count == elements.count ? texts : nil
        default: return nil
        }
    }

    static func unexpected(_ command: String, _ answer: LSPAny?) -> Problem {
        guard let answer, answer != .null else { return Problem(description: "\(command) answered nothing") }
        let text = (try? String(data: JSONEncoder().encode(answer), encoding: .utf8)) ?? String(describing: answer)
        return Problem(description: "\(command) answered an unexpected shape: \(text)")
    }

    // MARK: - The arguments

    /// debug R3 (amended 2026-10-18): the user's keys win, verbatim (R2); `resolved` fills the keys
    /// the user left out; `cwd` defaults to the command's, `env` is the command's (the repo's `$env`
    /// in) under the user's, `console` to the Run sub-tab's terminal.
    static func merge(arguments: LSPAny, resolved: [String: LSPAny], cwd: URL, env: [String: String]) -> LSPAny {
        guard case .hash(var merged) = arguments else { return arguments }
        func isAbsent(_ key: String) -> Bool {
            merged[key] == nil || merged[key] == .null
        }
        for (key, value) in resolved where isAbsent(key) {
            merged[key] = value
        }
        if isAbsent("cwd") {
            var path = cwd.path(percentEncoded: false)
            if path.count > 1, path.hasSuffix("/") {
                path.removeLast()
            }
            merged["cwd"] = .string(path)
        }
        if isAbsent("env") {
            if !env.isEmpty {
                merged["env"] = .hash(env.mapValues { .string($0) })
            }
        } else if case .hash(let user)? = merged["env"] {
            merged["env"] = .hash(env.mapValues { .string($0) }.merging(user) { _, user in user })
        }
        if isAbsent("console") {
            merged["console"] = .string("integratedTerminal")
        }
        return .hash(merged)
    }

    // MARK: - runInTerminal (debug R8)

    /// One argument for `$SHELL -l -c`: single-quoted, a `'` inside becoming `'\''`, so `$VAR` stays literal.
    static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func commandLine(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}

extension DebugCommand.Request {
    /// debug R9: the program is terminated for a launch, left running for an attach.
    nonisolated var terminatesDebuggee: Bool {
        self == .launch
    }
}

extension LSPAny {
    nonisolated var text: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}
