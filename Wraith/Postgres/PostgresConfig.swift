import Foundation
import PostgresNIO

/// The `postgres` section of `.wraith/config.json` (postgres R1, R12; config R3, R5).
///
/// One object = one connection per workspace; `password` is optional (decision 2026-08-27: a
/// local dev convenience) and short-circuits the Keychain chain of R3.
nonisolated struct PostgresConfig: Equatable, Sendable {
    /// postgres R1: the three modes of `libpq` that PostgresNIO can honour.
    enum SSLMode: String, Sendable, CaseIterable {
        case disable
        case prefer
        case require
    }

    /// What decoding the section gives: a connection, or the reason there is none.
    enum Outcome: Equatable, Sendable {
        case configured(PostgresConfig, warnings: [String])
        /// R2: the panel shows this message and the example.
        case missing(String)
    }

    static let defaultPort = 5432
    static let defaultStatementTimeout: Duration = .seconds(30)
    static let statementTimeoutRange: ClosedRange<Int> = 1...3600
    static let example = #""postgres": { "host": "localhost", "database": "ccoe", "user": "postgres" }"#

    var host = "localhost"
    var port = PostgresConfig.defaultPort
    let database: String
    let user: String
    var sslMode = SSLMode.prefer
    /// R3: when set, used as is; never logged, never written back anywhere.
    var password: String?
    /// R1: startup parameters such as `application_name`, passed as they are.
    var options: [String: String] = [:]
    /// R12: `statement_timeout`, in seconds in the file.
    var statementTimeout = PostgresConfig.defaultStatementTimeout

    /// R2: what both panel headers show.
    var label: String {
        "\(user)@\(host)/\(database)"
    }

    /// postgres, technical options: the Keychain account.
    var keychainAccount: String {
        "wraith.postgres.\(host):\(port)/\(database)/\(user)"
    }

    private struct Section: Decodable {
        var host: String?
        var port: Int?
        var database: String?
        var user: String?
        var sslmode: String?
        var password: String?
        var options: [String: String]?
        var statementTimeout: Int?
    }

    /// Decodes the section; each invalid field falls back on its default with a warning (config
    /// R5, R7: nothing here breaks the workspace).
    static func decode(from config: WorkspaceConfig) -> Outcome {
        let section: Section?
        do {
            section = try config.section("postgres", as: Section.self)
        } catch {
            return .missing("The \"postgres\" section of config.json is invalid: \(error). Example: \(example)")
        }
        guard let section else {
            return .missing("No \"postgres\" section in .wraith/config.json. Example: \(example)")
        }
        guard let database = section.database, !database.isEmpty, let user = section.user, !user.isEmpty else {
            return .missing("The \"postgres\" section needs \"database\" and \"user\". Example: \(example)")
        }
        var warnings: [String] = []
        var result = PostgresConfig(database: database, user: user)
        if let host = section.host, !host.isEmpty {
            result.host = host
        }
        if let port = section.port {
            if (1...65535).contains(port) {
                result.port = port
            } else {
                warnings.append("postgres.port \(port) is out of range, using \(defaultPort).")
            }
        }
        if let mode = section.sslmode {
            if let parsed = SSLMode(rawValue: mode) {
                result.sslMode = parsed
            } else {
                warnings.append("postgres.sslmode \"\(mode)\" unknown (disable, prefer, require), using prefer.")
            }
        }
        result.options = section.options ?? [:]
        result.password = section.password.flatMap { $0.isEmpty ? nil : $0 }
        if let seconds = section.statementTimeout {
            if statementTimeoutRange.contains(seconds) {
                result.statementTimeout = .seconds(seconds)
            } else {
                warnings.append("postgres.statementTimeout \(seconds) is out of 1...3600 s, using 30.")
            }
        }
        return .configured(result, warnings: warnings)
    }

    /// R1: `sslmode` onto PostgresNIO's `TLS`; the context is only built when TLS is allowed.
    static func tls(
        for mode: SSLMode, context: () throws -> NIOSSLContext
    ) throws -> PostgresConnection.Configuration.TLS {
        switch mode {
        case .disable:
            return .disable
        case .prefer:
            return .prefer(try context())
        case .require:
            return .require(try context())
        }
    }
}
