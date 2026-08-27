import Foundation
import Testing

@testable import Wraith

/// postgres R3, edge cases: `.pgpass` read like `libpq`.
struct PgPassTests {
    @Test func parsesFiveFieldsAndSkipsCommentsAndShortLines() {
        let entries = PgPass.parse(
            """
            # a comment
            localhost:5432:ccoe:postgres:secret
            short:line

            db.example.com:*:*:alice:pa:ss:word
            """)
        #expect(
            entries == [
                PgPass.Entry(host: "localhost", port: "5432", database: "ccoe", user: "postgres", password: "secret"),
                PgPass.Entry(host: "db.example.com", port: "*", database: "*", user: "alice", password: "pa:ss:word"),
            ])
    }

    @Test func unescapesColonsAndBackslashes() {
        let entries = PgPass.parse(#"host\:with\:colons:5432:db:user:p\\a\:ss"#)
        #expect(entries.first?.host == "host:with:colons")
        #expect(entries.first?.password == #"p\a:ss"#)
    }

    @Test func wildcardMatchesAnyValueAndFirstMatchWins() {
        let entries = PgPass.parse(
            """
            *:*:other:postgres:wrong
            *:5432:*:postgres:first
            localhost:5432:ccoe:postgres:second
            """)
        #expect(
            PgPass.password(in: entries, host: "localhost", port: 5432, database: "ccoe", user: "postgres") == "first")
        #expect(PgPass.password(in: entries, host: "localhost", port: 5433, database: "ccoe", user: "postgres") == nil)
        #expect(PgPass.password(in: entries, host: "x", port: 1, database: "other", user: "postgres") == "wrong")
    }

    @Test func refusesAFileReadableByOthers() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pgpass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: ".pgpass")
        try "localhost:5432:ccoe:postgres:secret\n".write(to: file, atomically: true, encoding: .utf8)
        var warnings: [String] = []

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
        let refused = PgPass.password(
            in: file, host: "localhost", port: 5432, database: "ccoe", user: "postgres", warnings: &warnings)
        #expect(refused == nil)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("0600"))
        #expect(!warnings[0].contains("secret"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
        let accepted = PgPass.password(
            in: file, host: "localhost", port: 5432, database: "ccoe", user: "postgres", warnings: &warnings)
        #expect(accepted == "secret")
        #expect(warnings.count == 1)
    }

    @Test func missingFileIsNotAWarning() {
        var warnings: [String] = []
        let missing = URL(filePath: "/nonexistent/\(UUID().uuidString)/.pgpass")
        #expect(PgPass.password(in: missing, host: "h", port: 1, database: "d", user: "u", warnings: &warnings) == nil)
        #expect(warnings.isEmpty)
    }

    @Test(arguments: [(0o600, true), (0o400, true), (0o644, false), (0o660, false), (0o700, true), (0o601, false)])
    func secureModeHasNoGroupOrOtherBits(mode: Int, isSecure: Bool) {
        #expect(PgPass.isSecure(mode: mode) == isSecure)
    }

    @Test func pgpassfileOverridesTheDefaultLocation() {
        #expect(PgPass.defaultFile(environment: ["PGPASSFILE": "/tmp/custom"]) == URL(filePath: "/tmp/custom"))
        #expect(PgPass.defaultFile(environment: [:]).lastPathComponent == ".pgpass")
    }
}
