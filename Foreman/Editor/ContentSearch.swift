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
        let shown = window(trimmed, ranges: ranges)
        return Match(path: relative(path), line: number, text: shown.text, ranges: shown.ranges)
    }

    /// editor R21 (amended 2026-10-17): the longest line a result shows; `rg --json` ignores
    /// `--max-columns`, and a minified bundle's line is megabytes the list would lay out.
    static let maximumLine = 300

    /// editor R21: a long line cut around its first match, with `…` where text was dropped, and
    /// its ranges moved with it (those left outside are dropped).
    static func window(
        _ text: String, ranges: [NSRange], maximum: Int = maximumLine
    ) -> (
        text: String, ranges: [NSRange]
    ) {
        let utf16 = text as NSString
        guard utf16.length > maximum else { return (text, ranges) }
        let first = ranges.first?.location ?? 0
        let start = max(0, min(first - maximum / 3, utf16.length - maximum))
        let end = min(utf16.length, start + maximum)
        let range = utf16.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        let head = range.location > 0 ? "\u{2026}" : ""
        let tail = NSMaxRange(range) < utf16.length ? "\u{2026}" : ""
        let shift = (head as NSString).length - range.location
        let kept = ranges.compactMap { candidate -> NSRange? in
            guard candidate.location >= range.location, NSMaxRange(candidate) <= NSMaxRange(range) else { return nil }
            return NSRange(location: candidate.location + shift, length: candidate.length)
        }
        return (head + utf16.substring(with: range) + tail, kept)
    }

    /// One line of `grep -rn --null`: `path\0line:text`; the ranges are found again in `text`.
    static func parseGrep(_ line: String, options: Options) -> Match? {
        guard let separator = line.firstIndex(of: "\0") else { return nil }
        let path = String(line[..<separator])
        let rest = line[line.index(after: separator)...]
        guard let colon = rest.firstIndex(of: ":"), let number = Int(rest[..<colon]) else { return nil }
        let text = String(rest[rest.index(after: colon)...])
        let shown = window(text, ranges: ranges(of: options, in: text))
        return Match(path: relative(path), line: number, text: shown.text, ranges: shown.ranges)
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
                // Both through `PipeIO`, never `FileHandle.bytes`: its iterations share one serial
                // queue, so the stderr read held it while rg filled stdout's pipe and waited —
                // every search with more than a pipe's worth of output hung (2026-10-17).
                async let stderr = drainStderr(errors)
                var count = 0
                var buffer = LineBuffer()
                func take(_ line: String) -> Bool {
                    let match: Match?
                    switch tool {
                    case .ripgrep:
                        match = parseRipgrep(line)
                    case .grep:
                        match = parseGrep(line, options: options)
                    }
                    guard let match else { return true }
                    continuation.yield(match)
                    count += 1
                    guard count < limit else {
                        process.terminate()
                        return false
                    }
                    return true
                }
                reading: for await chunk in PipeIO.chunks(pipe.fileHandleForReading) {
                    for line in buffer.append(chunk) where !take(line) {
                        break reading
                    }
                }
                if count < limit, let last = buffer.finish() {
                    _ = take(last)
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
        let text = String(decoding: await PipeIO.readToEnd(pipe.fileHandleForReading), as: UTF8.self)
        return text.split(separator: "\n").prefix(20).joined(separator: "\n")
    }

    /// Lines out of the chunks a pipe delivers: a chunk ends anywhere, a line at `\n` only.
    struct LineBuffer {
        private var pending = Data()

        /// The lines `chunk` completes; what follows the last `\n` waits for the next chunk.
        mutating func append(_ chunk: Data) -> [String] {
            pending.append(chunk)
            guard let last = pending.lastIndex(of: 0x0A) else { return [] }
            let complete = pending[pending.startIndex..<last]
            pending = Data(pending[(last + 1)...])
            return complete.split(separator: 0x0A, omittingEmptySubsequences: false).map {
                String(decoding: $0, as: UTF8.self)
            }
        }

        /// The last line when the output did not end with a newline.
        mutating func finish() -> String? {
            defer { pending = Data() }
            return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
        }
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
