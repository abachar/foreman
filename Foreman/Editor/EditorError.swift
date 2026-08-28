import Foundation

/// Why a file is not shown as text (editor R15, R16, edge cases).
nonisolated enum EditorError: Error, Equatable {
    /// editor R15: a null byte in the first 8 KB, or a known binary extension.
    case binary(bytes: Int)
    /// editor R16: over 50 MB.
    case tooLarge(bytes: Int)
    case unreadable(String)

    static func == (lhs: EditorError, rhs: EditorError) -> Bool {
        switch (lhs, rhs) {
        case (.binary(let a), .binary(let b)), (.tooLarge(let a), .tooLarge(let b)):
            return a == b
        case (.unreadable(let a), .unreadable(let b)):
            return a == b
        case (.binary, _), (.tooLarge, _), (.unreadable, _):
            return false
        }
    }
}

extension EditorError: CustomStringConvertible {
    var description: String {
        switch self {
        case .binary(let bytes):
            return "Binary file — \(bytes.formatted(.byteCount(style: .file)))"
        case .tooLarge(let bytes):
            return "File too large to open (\(bytes.formatted(.byteCount(style: .file))), limit 50 MB)"
        case .unreadable(let message):
            return message
        }
    }
}
