import Foundation

/// What `Highlight/` can fail on (editor R13: every case degrades to plain text).
nonisolated enum HighlightError: Error {
    /// A grammar's SPM resource bundle is missing from the app.
    case bundleNotFound(String)
}
