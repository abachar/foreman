import Foundation

/// A text file as read from disk (editor R3, R15, R16): its text, and what must be preserved or
/// shown when it is displayed and written back.
nonisolated struct FileDocument: Equatable, Sendable {
    enum Encoding: Equatable, Sendable {
        case utf8(bom: Bool)
        /// editor, edge cases: read as Latin-1 with a banner; written back as UTF-8.
        case latin1
    }

    enum LineEnding: String, Equatable, Sendable {
        case lf = "\n"
        case crlf = "\r\n"
    }

    /// editor R16: read-only without highlighting above this size.
    static let readOnlyThreshold = 2 * 1024 * 1024
    /// editor R16: refused above this size.
    static let maximumSize = 50 * 1024 * 1024
    /// editor R16: highlighting off when a line is longer than this.
    static let maximumHighlightedLine = 10_000
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "bmp", "tiff", "pdf", "zip", "gz", "tar", "bz2", "xz",
        "7z", "jar", "war", "class", "o", "a", "dylib", "so", "exe", "dll", "bin", "dmg", "pkg", "mp3", "mp4", "mov",
        "wav", "ttf", "otf", "woff", "woff2", "sqlite", "db", "xcuserstate",
    ]

    let text: String
    let encoding: Encoding
    let lineEnding: LineEnding
    let bytes: Int
    /// editor, edge cases: no write permission, or R16 size.
    let isWritable: Bool

    var isReadOnly: Bool {
        !isWritable || bytes > Self.readOnlyThreshold
    }

    /// editor R13, R16: a big file or a pathological line is shown as plain text.
    var isHighlightable: Bool {
        bytes <= Self.readOnlyThreshold && !hasVeryLongLine
    }

    private var hasVeryLongLine: Bool {
        var count = 0
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                count = 0
            } else {
                count += 1
                if count > Self.maximumHighlightedLine {
                    return true
                }
            }
        }
        return false
    }

    /// editor R15: decided on the name and the first 8 KB, before the whole file is read.
    static func isBinary(name: String, head: Data) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return binaryExtensions.contains(ext) || head.contains(0)
    }

    /// Decodes what was read: UTF-8 (BOM tolerated), otherwise Latin-1; line endings detected on
    /// the first CR LF found; the text is normalized to LF for display.
    static func decode(_ data: Data, bytes: Int? = nil, isWritable: Bool = true) -> FileDocument {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let hasBOM = data.starts(with: bom)
        let payload = hasBOM ? data.dropFirst(bom.count) : data[...]
        let encoding: Encoding
        let raw: String
        if let utf8 = String(data: payload, encoding: .utf8) {
            raw = utf8
            encoding = .utf8(bom: hasBOM)
        } else {
            // Every byte is a Latin-1 code point, so this never fails.
            raw = String(data: payload, encoding: .isoLatin1) ?? ""
            encoding = .latin1
        }
        let lineEnding: LineEnding = raw.contains("\r\n") ? .crlf : .lf
        let text = lineEnding == .crlf ? raw.replacingOccurrences(of: "\r\n", with: "\n") : raw
        return FileDocument(
            text: text, encoding: encoding, lineEnding: lineEnding, bytes: bytes ?? data.count, isWritable: isWritable)
    }

    /// Reads `url` off the main actor (editor R3).
    @concurrent
    static func read(_ url: URL) async throws(EditorError) -> FileDocument {
        let path = url.path(percentEncoded: false)
        let fileManager = FileManager.default
        guard let size = (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int else {
            throw .unreadable("\(url.lastPathComponent): not found")
        }
        guard size <= maximumSize else { throw .tooLarge(bytes: size) }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw .unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8192)) ?? Data()
        if isBinary(name: url.lastPathComponent, head: head) {
            throw .binary(bytes: size)
        }
        let rest = (try? handle.readToEnd()) ?? Data()
        return decode(head + rest, bytes: size, isWritable: fileManager.isWritableFile(atPath: path))
    }
}
