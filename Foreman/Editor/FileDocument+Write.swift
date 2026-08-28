import Foundation

/// editor R8: writing back with the encoding and line endings of the read.
nonisolated extension FileDocument {
    /// The bytes to write for `text` as this document was read: BOM kept, CR LF restored,
    /// Latin-1 rewritten as UTF-8 (edge cases).
    func encode(_ text: String) -> Data {
        var data = Data()
        if case .utf8(bom: true) = encoding {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        let content = lineEnding == .crlf ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
        data.append(contentsOf: content.utf8)
        return data
    }

    /// Writes atomically (coding rules): a temporary file next to the target, then `replaceItemAt`.
    ///
    /// Returns the document as it now is on disk (modification date included, for R10).
    @concurrent
    static func write(_ text: String, to url: URL, as document: FileDocument) async throws(EditorError) -> FileDocument
    {
        let data = document.encode(text)
        let folder = url.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(url.lastPathComponent).foreman-tmp")
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                // editor R9: the file was deleted on disk; saving recreates it.
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw .unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let modified = modificationDate(of: url)
        return FileDocument(
            text: text, encoding: document.encoding == .latin1 ? .utf8(bom: false) : document.encoding,
            lineEnding: document.lineEnding, bytes: data.count, isWritable: true, modificationDate: modified)
    }

    nonisolated static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate]
            as? Date
    }

    /// editor R10: the file changed on disk since this document was read.
    func isStale(at url: URL) -> Bool {
        guard let modificationDate else { return false }
        return Self.modificationDate(of: url) != modificationDate
    }
}
