import Foundation
import PostgresNIO
import Testing

@testable import Foreman

/// postgres R1, R12, config R5: the `postgres` section, its defaults and its bounds.
struct PostgresConfigTests {
    private func load(_ json: String?) async throws -> WorkspaceConfig {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PostgresConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        if let json {
            let file = root.appending(components: ".foreman", "config.json")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try json.write(to: file, atomically: true, encoding: .utf8)
        }
        return try await WorkspaceConfig.load(root: root)
    }

    @Test func missingSectionGivesTheExample() async throws {
        let outcome = PostgresConfig.decode(from: try await load(#"{ "repos": [] }"#))
        guard case .missing(let message) = outcome else {
            Issue.record("expected missing")
            return
        }
        #expect(message.contains(PostgresConfig.example))
    }

    @Test func partialSectionFallsBackOnDefaults() async throws {
        let outcome = PostgresConfig.decode(
            from: try await load(#"{ "postgres": { "database": "ccoe", "user": "me" } }"#))
        #expect(
            outcome
                == .configured(
                    PostgresConfig(
                        host: "localhost", port: 5432, database: "ccoe", user: "me", sslMode: .prefer, password: nil,
                        options: [:], statementTimeout: .seconds(30)), warnings: []))
    }

    @Test func databaseAndUserAreRequired() async throws {
        let outcome = PostgresConfig.decode(from: try await load(#"{ "postgres": { "host": "db" } }"#))
        guard case .missing(let message) = outcome else {
            Issue.record("expected missing")
            return
        }
        #expect(message.contains("\"database\""))
    }

    @Test func invalidFieldsWarnAndKeepTheirDefault() async throws {
        let outcome = PostgresConfig.decode(
            from: try await load(
                #"{ "postgres": { "database": "d", "user": "u", "port": 70000, "sslmode": "verify-full", "statementTimeout": 0 } }"#
            ))
        guard case .configured(let config, let warnings) = outcome else {
            Issue.record("expected configured")
            return
        }
        #expect(config.port == 5432)
        #expect(config.sslMode == .prefer)
        #expect(config.statementTimeout == .seconds(30))
        #expect(warnings.count == 3)
        #expect(warnings.contains { $0.contains("70000") })
        #expect(warnings.contains { $0.contains("verify-full") })
    }

    @Test func readsEveryField() async throws {
        let outcome = PostgresConfig.decode(
            from: try await load(
                #"{ "postgres": { "host": "db.local", "port": 6543, "database": "d", "user": "u", "sslmode": "require", "options": { "application_name": "foreman" }, "statementTimeout": 5 } }"#
            ))
        guard case .configured(let config, let warnings) = outcome else {
            Issue.record("expected configured")
            return
        }
        #expect(warnings.isEmpty)
        #expect(config.host == "db.local")
        #expect(config.port == 6543)
        #expect(config.sslMode == .require)
        #expect(config.options == ["application_name": "foreman"])
        #expect(config.statementTimeout == .seconds(5))
        #expect(config.label == "u@db.local/d")
        #expect(config.keychainAccount == "foreman.postgres.db.local:6543/d/u")
    }

    @Test func passwordIsReadFromTheSection() async throws {
        let config = try await load(#"{ "postgres": { "database": "d", "user": "u", "password": "nope" } }"#)
        #expect(config.warnings.isEmpty)
        guard case .configured(let decoded, _) = PostgresConfig.decode(from: config) else {
            Issue.record("expected configured")
            return
        }
        #expect(decoded.password == "nope")
        #expect(!decoded.label.contains("nope"))
    }

    @Test func sslModeMapsOntoTLS() throws {
        let context = { try NIOSSLContext(configuration: .clientDefault) }
        let disabled = try PostgresConfig.tls(for: .disable, context: context)
        #expect(!disabled.isAllowed)
        let preferred = try PostgresConfig.tls(for: .prefer, context: context)
        #expect(preferred.isAllowed && !preferred.isEnforced)
        let required = try PostgresConfig.tls(for: .require, context: context)
        #expect(required.isEnforced)
    }

    @Test func disableNeverBuildsAContext() throws {
        var built = false
        _ = try PostgresConfig.tls(for: .disable) {
            built = true
            return try NIOSSLContext(configuration: .clientDefault)
        }
        #expect(!built)
    }
}
