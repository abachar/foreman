import Foundation

/// The pure rules of running a buffer (postgres R10, R13, R14, R19): what is sent, where an
/// error points, what a refusal means.
nonisolated enum QueryExecution {
    /// R10: the selection if there is one, otherwise the whole buffer, and its range in the text.
    struct Statement: Equatable, Sendable {
        let sql: String
        let range: NSRange
    }

    static func statement(in text: String, selection: NSRange) -> Statement? {
        let whole = text as NSString
        let range =
            selection.length > 0 && NSMaxRange(selection) <= whole.length
            ? selection : NSRange(location: 0, length: whole.length)
        let sql = whole.substring(with: range)
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Statement(sql: sql, range: range)
    }

    /// R19: the server's 1-based character position in the sent SQL, back into the buffer;
    /// out of range → the start of what was sent.
    static func cursorLocation(position: Int?, sent: NSRange, textLength: Int) -> Int {
        guard let position, position >= 1 else { return min(sent.location, textLength) }
        let sql = (position - 1)
        guard sql <= sent.length else { return min(sent.location, textLength) }
        return min(sent.location + sql, textLength)
    }

    /// R17: whether the statement comes back with a result set at all, so an empty one is shown
    /// as `0 rows` and not as the `OK` of a command tag.
    ///
    /// PostgresNIO exposes neither the row description nor the command tag (decision
    /// 2026-08-27), so the leading keyword is all there is to go on. Nothing else of the
    /// statement is read and it is never rewritten (R15): a statement whose keyword is hidden
    /// behind an unterminated comment, and an `INSERT … RETURNING`, still read as commands.
    static func returnsRows(_ sql: String) -> Bool {
        rowReturningKeywords.contains(leadingKeyword(of: sql))
    }

    /// The first word of `sql`, past leading whitespace, opening parentheses and comments.
    private static func leadingKeyword(of sql: String) -> String {
        var rest = Substring(sql)
        while true {
            rest = rest.drop { $0.isWhitespace || $0 == "(" }
            if rest.hasPrefix("--") {
                rest = rest.drop { !$0.isNewline }
            } else if rest.hasPrefix("/*") {
                guard let end = rest.range(of: "*/") else { return "" }
                rest = rest[end.upperBound...]
            } else {
                return rest.prefix { $0.isLetter }.lowercased()
            }
        }
    }

    private static let rowReturningKeywords: Set<String> = [
        "explain", "fetch", "select", "show", "table", "values", "with",
    ]

    /// R10, R11: what the banner adds under a server error the user can act on.
    static func hint(sqlState: String?) -> String? {
        switch sqlState {
        case "42601":
            return "One statement per run: select the statement to run."
        case "25006":
            return "Read-only session: enable Allow writes (the pencil) to run it."
        default:
            return nil
        }
    }

    /// R14: one execution at a time per window; a second `cmd+enter` is refused, not queued.
    enum State: Equatable, Sendable {
        case idle
        case running(tab: TabID)

        func starting(_ tab: TabID) -> State? {
            if case .idle = self {
                return .running(tab: tab)
            }
            return nil
        }

        /// R4: a running execution makes the window's connection busy, so hiding the last panel
        /// of the feature must not close it under the statement.
        var isBusy: Bool {
            self != .idle
        }
    }

    /// R13: after `pg_cancel_backend`, the connection is dropped if the server did not answer
    /// within `limit`.
    static let cancelLimit: Duration = .seconds(5)

    static func shouldDropConnection(answered: Bool, elapsed: Duration, limit: Duration = cancelLimit) -> Bool {
        !answered && elapsed >= limit
    }
}
