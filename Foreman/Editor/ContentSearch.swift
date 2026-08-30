import Foundation

/// editor R20, R21: workspace-wide text search through `rg` (or `grep`), one match per line.
nonisolated enum ContentSearch {
    struct Options: Equatable, Sendable {
        var query: String
        var isCaseSensitive = false
        var isWholeWord = false
        var isRegex = false
        /// editor R20: an inclusion glob (`src/**/*.ts`); empty for everything.
        var include = ""
    }

    struct Match: Equatable, Sendable, Identifiable {
        /// Relative to the root.
        let path: String
        /// 1-based.
        let line: Int
        let text: String
        /// UTF-16 ranges of the matches inside `text`.
        let ranges: [NSRange]

        var id: String { "\(path):\(line)" }
    }

    enum Tool: Equatable, Sendable {
        case ripgrep(URL)
        case grep(URL)

        var url: URL {
            switch self {
            case .ripgrep(let url), .grep(let url):
                return url
            }
        }
    }

    /// editor R21: matches beyond this are dropped and the panel says so.
    static let limit = 2000

    /// `rg` from `PATH` and the usual Homebrew locations, otherwise `grep` (editor R20).
    static func locateTool(environment: [String: String] = ProcessInfo.processInfo.environment) -> Tool {
        var folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        folders += ["/opt/homebrew/bin", "/usr/local/bin"]
        for folder in folders {
            let candidate = URL(filePath: folder).appending(path: "rg")
            if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
                return .ripgrep(candidate)
            }
        }
        return .grep(URL(filePath: "/usr/bin/grep"))
    }

    /// The command line for `options`, run with the workspace root as working directory.
    ///
    /// The query is always an argument, never interpolated (architecture, security).
    static func arguments(for options: Options, tool: Tool) -> [String] {
        switch tool {
        case .ripgrep:
            var arguments = ["--json", "--no-messages", "--no-config", options.isCaseSensitive ? "-s" : "-i"]
            if options.isWholeWord { arguments.append("-w") }
            if !options.isRegex { arguments.append("-F") }
            if !options.include.isEmpty { arguments += ["-g", options.include] }
            for excluded in ["node_modules", "target", ".build", ".git", ".foreman"] {
                arguments += ["-g", "!\(excluded)"]
            }
            return arguments + ["-e", options.query, "--", "."]
        case .grep:
            var arguments = ["-rnI", "--null", options.isRegex ? "-E" : "-F"]
            if !options.isCaseSensitive { arguments.append("-i") }
            if options.isWholeWord { arguments.append("-w") }
            if !options.include.isEmpty {
                // grep matches its --include on the file name only: keep the last path component.
                arguments.append(
                    "--include=\(options.include.split(separator: "/").last.map(String.init) ?? options.include)")
            }
            for excluded in ["node_modules", "target", ".build", ".git", ".foreman"] {
                arguments.append("--exclude-dir=\(excluded)")
            }
            return arguments + ["-e", options.query, "--", "."]
        }
    }

    /// One line of `rg --json`; only `match` events become a `Match`.
    static func parseRipgrep(_ line: String) -> Match? {
        guard let data = line.data(using: .utf8), let event = try? JSONDecoder().decode(RipgrepEvent.self, from: data),
            event.type == "match", let match = event.data, let path = match.path.text, let text = match.lines.text,
            let number = match.lineNumber
        else { return nil }
        let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
        let utf8 = Array(trimmed.utf8)
        let ranges = match.submatches.compactMap { sub -> NSRange? in
            guard sub.start <= utf8.count, sub.end <= utf8.count, sub.start <= sub.end else { return nil }
            let head = String(decoding: utf8[0..<sub.start], as: UTF8.self).utf16.count
            let length = String(decoding: utf8[sub.start..<sub.end], as: UTF8.self).utf16.count
            return NSRange(location: head, length: length)
        }
        return Match(path: relative(path), line: number, text: trimmed, ranges: ranges)
    }

    /// One line of `grep -rn --null`: `path\0line:text`; the ranges are found again in `text`.
    static func parseGrep(_ line: String, options: Options) -> Match? {
        guard let separator = line.firstIndex(of: "\0") else { return nil }
        let path = String(line[..<separator])
        let rest = line[line.index(after: separator)...]
        guard let colon = rest.firstIndex(of: ":"), let number = Int(rest[..<colon]) else { return nil }
        let text = String(rest[rest.index(after: colon)...])
        return Match(path: relative(path), line: number, text: text, ranges: ranges(of: options, in: text))
    }

    /// Where `options` match inside one line (grep does not say).
    static func ranges(of options: Options, in text: String) -> [NSRange] {
        let pattern = options.isRegex ? options.query : NSRegularExpression.escapedPattern(for: options.query)
        let wrapped = options.isWholeWord ? "\\b(?:\(pattern))\\b" : pattern
        guard
            let regex = try? NSRegularExpression(
                pattern: wrapped, options: options.isCaseSensitive ? [] : [.caseInsensitive])
        else { return [] }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: whole).map(\.range)
    }

    /// editor R21: the typed error for a run that produced nothing, `nil` when the exit only
    /// means "no matches" (`rg` and `grep` both exit 1 for that) or success.
    static func failure(status: Int32, tool: Tool, stderr: String) -> EditorError? {
        switch tool {
        case .ripgrep:
            guard status >= 2 else { return nil }
        case .grep:
            guard status > 1 else { return nil }
        }
        let summary = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return .searchFailed(summary.isEmpty ? "Search tool exited with status \(status)" : String(summary.prefix(200)))
    }

    /// Runs the tool in `root` and streams the matches.
    ///
    /// Cancelling the consumer kills the process; the stream ends after `limit` matches (R21).
    /// A run that yields nothing and exits with an error throws it as an `EditorError`.
    static func run(_ options: Options, tool: Tool, root: URL) -> AsyncThrowingStream<Match, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = tool.url
            process.arguments = arguments(for: options, tool: tool)
            process.currentDirectoryURL = root
            let pipe = Pipe()
            let errors = Pipe()
            process.standardOutput = pipe
            process.standardError = errors
            // `nil` when the run was cut short (the cap, a cancel): the status means nothing then.
            let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32?.self)
            process.terminationHandler = { process in
                exitContinuation.yield(process.terminationReason == .exit ? process.terminationStatus : nil)
                exitContinuation.finish()
            }
            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
            }
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            Task.detached {
                // Drained alongside stdout: a tool blocked on a full stderr pipe never exits.
                async let stderr = drainStderr(errors)
                var count = 0
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        let match: Match?
                        switch tool {
                        case .ripgrep:
                            match = parseRipgrep(line)
                        case .grep:
                            match = parseGrep(line, options: options)
                        }
                        guard let match else { continue }
                        continuation.yield(match)
                        count += 1
                        if count >= limit {
                            process.terminate()
                            break
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                guard count == 0 else {
                    continuation.finish()
                    return
                }
                let diagnostics = await stderr
                var exitIterator = exits.makeAsyncIterator()
                if let status = await exitIterator.next() ?? nil,
                    let searchFailure = failure(status: status, tool: tool, stderr: diagnostics)
                {
                    continuation.finish(throwing: searchFailure)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// The first lines of stderr, enough for a summary; the rest is read and dropped.
    private static func drainStderr(_ pipe: Pipe) async -> String {
        var lines: [String] = []
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines where lines.count < 20 {
                lines.append(line)
            }
        } catch {
            // A read error on the diagnostics channel: whatever was collected is the summary.
        }
        return lines.joined(separator: "\n")
    }

    private static func relative(_ path: String) -> String {
        path.hasPrefix("./") ? String(path.dropFirst(2)) : path
    }

    private struct RipgrepEvent: Decodable {
        struct Text: Decodable {
            let text: String?
        }
        struct Submatch: Decodable {
            let start: Int
            let end: Int
        }
        struct Payload: Decodable {
            let path: Text
            let lines: Text
            let lineNumber: Int?
            let submatches: [Submatch]

            enum CodingKeys: String, CodingKey {
                case path
                case lines
                case lineNumber = "line_number"
                case submatches
            }
        }
        let type: String
        let data: Payload?
    }
}
