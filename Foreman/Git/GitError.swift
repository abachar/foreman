import Foundation

/// What a `git` invocation can fail with (git R28).
nonisolated enum GitError: Error, Equatable, Sendable {
    /// No `git` binary in the login shell's `PATH` nor at `git.path`; the feature is inert.
    case gitNotFound
    case notARepo
    /// Any other non-zero exit: stderr, trimmed, is what the user sees.
    case commandFailed(String)
    /// git R22: git wanted a terminal (credentials, passphrase, host key) and had none.
    case needsInteraction
    /// git R26: the time bound was reached and the process killed.
    case timeout
    /// A merge, rebase, cherry-pick or stash apply stopped on conflicts (git R9).
    case conflict
    /// The task running the command was cancelled (a slow hook stopped by the user).
    case cancelled

    /// git R28: the class of an exit, read on stderr; `commandFailed` when nothing is recognised.
    static func classify(stderr: String) -> GitError {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("not a git repository") {
            return .notARepo
        }
        if interactionMarkers.contains(where: { text.contains($0) }) {
            return .needsInteraction
        }
        if conflictMarkers.contains(where: { text.contains($0) }) {
            return .conflict
        }
        return .commandFailed(text)
    }

    /// Edge cases: another git holds the index; retried once after 500 ms.
    static func isIndexLocked(stderr: String) -> Bool {
        stderr.contains("index.lock")
    }

    private static let interactionMarkers = [
        "could not read Username", "could not read Password", "Permission denied (publickey",
        "terminal prompts disabled", "Host key verification failed", "gpg failed to sign",
    ]

    private static let conflictMarkers = ["CONFLICT (", "Automatic merge failed", "could not apply"]
}

extension GitError: CustomStringConvertible {
    var description: String {
        switch self {
        case .gitNotFound:
            return "git not found in the login shell's PATH; set git.path in .foreman/config.json."
        case .notARepo:
            return "Not a git repository."
        case .commandFailed(let stderr):
            return stderr.isEmpty ? "git failed without a message." : stderr
        case .needsInteraction:
            return "Authentication required."
        case .timeout:
            return "git did not answer in time."
        case .conflict:
            return "Conflicts to resolve."
        case .cancelled:
            return "Cancelled."
        }
    }
}
