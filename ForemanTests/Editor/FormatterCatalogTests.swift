import Foundation
import Testing

@testable import Foreman

/// The `formatter` section decoded (editor R25, R30; config R7).
struct FormatterCatalogTests {
    private func decode(_ json: String) throws -> FormatterCatalog {
        try JSONDecoder().decode(FormatterCatalog.self, from: Data(json.utf8))
    }

    @Test func aMissingSectionIsAnEmptyCatalog() throws {
        let catalog = try WorkspaceConfig.empty.section("formatter", as: FormatterCatalog.self) ?? .empty
        #expect(catalog == .empty)
        #expect(catalog.timeout == .seconds(5))
        #expect(catalog.command(forKey: "ts") == nil)
    }

    @Test func theReservedKeyIsNeverAnExtension() throws {
        let catalog = try decode(#"{ "timeout": 12, "ts": "prettier --stdin-filepath file.ts" }"#)
        #expect(catalog.timeout == .seconds(12))
        #expect(catalog.commands == ["ts": "prettier --stdin-filepath file.ts"])
        #expect(catalog.command(forKey: "timeout") == nil)
        #expect(catalog.warnings.isEmpty)
    }

    @Test(arguments: [(0.2, 1.0), (90, 60), (7.5, 7.5)])
    func clampsTheTimeout(declared: Double, expected: Double) throws {
        #expect(try decode(#"{ "timeout": \#(declared) }"#).timeout == .seconds(expected))
    }

    @Test func matchesExtensionsCaseInsensitively() throws {
        let catalog = try decode(#"{ "TS": "prettier", "dockerfile": "dockfmt fmt" }"#)
        #expect(catalog.command(forKey: "ts") == "prettier")
        #expect(catalog.command(forKey: "Ts") == "prettier")
        #expect(catalog.command(forKey: FormatterCatalog.key(for: URL(filePath: "/a/Dockerfile"))) == "dockfmt fmt")
        #expect(FormatterCatalog.key(for: URL(filePath: "/a/b.TS")) == "TS")
    }

    @Test func dropsBadEntriesWithAWarningAndKeepsTheRest() throws {
        let catalog = try decode(#"{ "py": "black -q -", "rs": 3, "go": "  ", "timeout": "5" }"#)
        #expect(catalog.commands == ["py": "black -q -"])
        #expect(catalog.timeout == .seconds(5))
        #expect(catalog.warnings.count == 3)
        #expect(catalog.warnings.contains { $0.hasPrefix("formatter.rs ignored") })
        #expect(catalog.warnings.contains { $0.hasPrefix("formatter.go ignored") })
    }

    @Test(arguments: [
        ("npx --no-install prettier --stdin-filepath file.ts", "npx"),
        ("taplo fmt -", "taplo"),
        ("  swiftformat --quiet", "swiftformat"),
        ("", ""),
    ])
    func binaryIsTheFirstWord(command: String, binary: String) {
        #expect(FormatterCatalog.binary(of: command) == binary)
    }

    @Test func detectsTheBinaryInThePathWithoutRunningIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FormatterCatalogTests-\(UUID().uuidString)")
        let bin = root.appending(path: "bin")
        let other = root.appending(path: "other")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/sh\n".utf8).write(to: bin.appending(path: "prettier"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: "prettier").path(percentEncoded: false))
        try Data().write(to: other.appending(path: "black"))
        let path = "\(other.path(percentEncoded: false)):\(bin.path(percentEncoded: false))"
        #expect(FormatterCatalog.isBinaryAvailable("prettier --stdin-filepath file.ts", inPath: path))
        #expect(!FormatterCatalog.isBinaryAvailable("black -q -", inPath: path))
        #expect(!FormatterCatalog.isBinaryAvailable("rustfmt", inPath: path))
        #expect(!FormatterCatalog.isBinaryAvailable("prettier", inPath: nil))
        #expect(
            FormatterCatalog.isBinaryAvailable(
                "\(bin.appending(path: "prettier").path(percentEncoded: false)) --check", inPath: nil))
    }
}

/// editor R25: the binary lookup, on a temporary PATH (moved from the agents on 2026-08-28).
struct FormatterBinaryTests {
    @Test func findsAnExecutableInThePathOrByAbsolutePath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FormatterBinaryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "empty"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: bin.appending(path: "prettier"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: "prettier").path())
        try Data().write(to: bin.appending(path: "notexec"))
        let path = "\(root.appending(path: "empty").path()):\(bin.path())"
        #expect(FormatterCatalog.isBinaryAvailable("prettier --write", inPath: path))
        #expect(!FormatterCatalog.isBinaryAvailable("notexec", inPath: path))
        #expect(!FormatterCatalog.isBinaryAvailable("prettier", inPath: nil))
        #expect(FormatterCatalog.isBinaryAvailable(bin.appending(path: "prettier").path() + " -w", inPath: nil))
    }
}
