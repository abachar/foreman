import Foundation
import Testing

@testable import Foreman

/// Binary, encoding, line endings and size classes (editor R3, R15, R16).
struct FileDocumentTests {
    @Test func detectsBinariesByNullByteOrExtension() {
        #expect(FileDocument.isBinary(name: "a.bin", head: Data("text".utf8)))
        #expect(FileDocument.isBinary(name: "logo.PNG", head: Data("text".utf8)))
        #expect(FileDocument.isBinary(name: "a.txt", head: Data([0x41, 0x00, 0x42])))
        #expect(!FileDocument.isBinary(name: "a.txt", head: Data("plain\n".utf8)))
    }

    @Test func decodesUTF8WithOrWithoutBOM() {
        let plain = FileDocument.decode(Data("héllo\n".utf8))
        #expect(plain.text == "héllo\n")
        #expect(plain.encoding == .utf8(bom: false))
        let bom = FileDocument.decode(Data([0xEF, 0xBB, 0xBF]) + Data("x".utf8))
        #expect(bom.text == "x")
        #expect(bom.encoding == .utf8(bom: true))
    }

    @Test func fallsBackToLatin1() {
        let document = FileDocument.decode(Data([0x63, 0x61, 0x66, 0xE9]))
        #expect(document.text == "café")
        #expect(document.encoding == .latin1)
    }

    @Test func detectsAndNormalizesLineEndings() {
        let crlf = FileDocument.decode(Data("a\r\nb\r\n".utf8))
        #expect(crlf.lineEnding == .crlf)
        #expect(crlf.text == "a\nb\n")
        #expect(FileDocument.decode(Data("a\nb".utf8)).lineEnding == .lf)
    }

    @Test func classifiesBySize() {
        let small = FileDocument.decode(Data("x".utf8), bytes: 10)
        #expect(!small.isReadOnly && small.isHighlightable)
        let large = FileDocument.decode(Data("x".utf8), bytes: FileDocument.readOnlyThreshold + 1)
        #expect(large.isReadOnly && !large.isHighlightable)
        let locked = FileDocument.decode(Data("x".utf8), bytes: 10, isWritable: false)
        #expect(locked.isReadOnly && locked.isHighlightable)
        let longLine = FileDocument.decode(Data(String(repeating: "a", count: 10_001).utf8))
        #expect(!longLine.isHighlightable)
    }

    @Test func readsFromDiskAndRefusesWhatItMust() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileDocumentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("let x = 1\r\n".utf8).write(to: root.appending(path: "a.swift"))
        try Data([0x00, 0x01]).write(to: root.appending(path: "blob.dat"))

        let document = try await FileDocument.read(root.appending(path: "a.swift"))
        #expect(document.text == "let x = 1\n")
        #expect(document.lineEnding == .crlf)
        #expect(document.bytes == 11)
        await #expect(throws: EditorError.binary(bytes: 2)) {
            try await FileDocument.read(root.appending(path: "blob.dat"))
        }
        await #expect(throws: EditorError.self) {
            try await FileDocument.read(root.appending(path: "missing"))
        }
    }
}

/// editor R8, R10: writing back what was read, and noticing a change on disk.
struct FileDocumentWriteTests {
    @Test func keepsBOMAndCRLFAndRewritesLatin1AsUTF8() {
        let crlf = FileDocument.decode(Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb".utf8))
        #expect(crlf.encode("a\nb\n") == Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb\r\n".utf8))
        let latin = FileDocument.decode(Data([0x63, 0x61, 0x66, 0xE9]))
        #expect(latin.encode(latin.text) == Data("café".utf8))
    }

    @Test func writesAtomicallyAndDetectsAStaleFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileDocumentWriteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "a.txt")
        try Data("one\n".utf8).write(to: url)
        let document = try await FileDocument.read(url)
        #expect(!document.isStale(at: url))

        let written = try await FileDocument.write("two\n", to: url, as: document)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two\n")
        #expect(!written.isStale(at: url))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["a.txt"])

        try await Task.sleep(for: .milliseconds(20))
        try Data("three\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
        #expect(written.isStale(at: url))
    }
}
