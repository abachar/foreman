import Foundation
import PostgresNIO
import os

/// The window's single connection (postgres R4, R5, R11, R12): lazy, bounded, reopened on demand.
///
/// Using `PostgresConnection` directly (decision 2026-08-27: not the library's pool); this
/// actor only adds the laziness, the session settings and the feature's error. A concrete type,
/// no protocol (decision 2026-08-26).
actor PostgresClient {
    /// R5: what the header's dot shows.
    enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    static let connectTimeout: Duration = .seconds(10)
    static let catalogTimeout: Duration = .seconds(10)

    let config: PostgresConfig
    /// Every state, for the feature's model (architecture: a stream, not a stored callback).
    let states: AsyncStream<State>
    private(set) var state = State.disconnected {
        didSet { stateContinuation.yield(state) }
    }
    /// R13: the server-side pid of this connection, for `pg_cancel_backend`.
    private(set) var backendPID: Int32?
    /// R11: per session, never persisted.
    private(set) var allowWrites = false
    /// R4: the last time a query started or ended.
    private(set) var lastActivity = ContinuousClock.now
    /// R4: how many queries are streaming right now; a busy connection is never closed by the
    /// inactivity timer, however long the statement runs (`statementTimeout` goes up to an hour).
    private(set) var activeQueries = 0

    var isBusy: Bool {
        activeQueries > 0
    }

    private let password: @Sendable () async throws(PostgresError) -> String
    private let stateContinuation: AsyncStream<State>.Continuation
    private var connection: PostgresConnection?
    private var connecting: Task<PostgresConnection, Error>?
    private var idleClose: Task<Void, Never>?
    private let nioLogger = Logging.Logger(label: "dev.crafters.foreman.postgres")
    private let logger = os.Logger(subsystem: "dev.crafters.foreman", category: "postgres")

    init(config: PostgresConfig, password: @escaping @Sendable () async throws(PostgresError) -> String) {
        self.config = config
        self.password = password
        (states, stateContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Connection (R3, R4)

    /// The open connection, established now if needed (R4: the first action only).
    @discardableResult
    func connect() async throws(PostgresError) -> PostgresConnection {
        if let connection, !connection.isClosed {
            return connection
        }
        if let connecting {
            do {
                return try await connecting.value
            } catch {
                throw PostgresError.classify(error)
            }
        }
        state = .connecting
        let task = Task { try await establish() }
        connecting = task
        defer { connecting = nil }
        do {
            let connection = try await task.value
            self.connection = connection
            state = .connected
            touch()
            return connection
        } catch {
            let classified = PostgresError.classify(error)
            backendPID = nil
            state = .error(classified.description)
            throw classified
        }
    }

    private func establish() async throws -> PostgresConnection {
        let secret = try await password()
        var configuration = try makeConfiguration(password: secret)
        // R1: the section's `options` are this session's startup parameters.
        configuration.options.additionalStartupParameters = config.options.sorted { $0.key < $1.key }.map { ($0, $1) }
        let connection = try await PostgresConnection.connect(
            configuration: configuration, id: Int.random(in: 1...Int.max), logger: nioLogger)
        do {
            try await applySession(on: connection)
            let rows = try await connection.query("SELECT pg_backend_pid()", logger: nioLogger).collect()
            backendPID = try rows.first?.makeRandomAccess()[0].decode(Int32.self)
        } catch {
            try? await connection.close()
            throw error
        }
        return connection
    }

    /// R1, R4: host, credentials, TLS and the connection timeout, as both the session's
    /// connection and the short-lived cancel connection need them.
    private func makeConfiguration(password secret: String) throws -> PostgresConnection.Configuration {
        var configuration = PostgresConnection.Configuration(
            host: config.host, port: config.port, username: config.user, password: secret, database: config.database,
            tls: try PostgresConfig.tls(for: config.sslMode) { try NIOSSLContext(configuration: .clientDefault) })
        configuration.options.connectTimeout = .seconds(Int64(Self.connectTimeout.components.seconds))
        return configuration
    }

    /// R11, R12: the session is read-only and bounded from its first statement; values go
    /// through `set_config` binds, never into the SQL text (R15).
    ///
    /// The read-only setting is a guard against an accidental write, not a permission: a
    /// statement is free to set `default_transaction_read_only` off itself. Only the server's
    /// own grants can stop a deliberate write, and the toggle's help text says as much.
    private func applySession(on connection: PostgresConnection) async throws {
        let readOnly = allowWrites ? "off" : "on"
        try await connection.query(
            "SELECT set_config('default_transaction_read_only', \(readOnly), false)", logger: nioLogger)
        let milliseconds = String(config.statementTimeout.components.seconds * 1000)
        try await connection.query(
            "SELECT set_config('statement_timeout', \(milliseconds), false)", logger: nioLogger)
    }

    /// R11: the *Allow writes* toggle, applied to the live session and to the next one.
    func setAllowWrites(_ allowed: Bool) async throws(PostgresError) {
        allowWrites = allowed
        guard let connection, !connection.isClosed else { return }
        do {
            try await applySession(on: connection)
        } catch {
            throw PostgresError.classify(error)
        }
    }

    /// R4: closes now; the next action reopens.
    func close() async {
        idleClose?.cancel()
        idleClose = nil
        connecting?.cancel()
        guard let connection else {
            state = .disconnected
            return
        }
        self.connection = nil
        backendPID = nil
        state = .disconnected
        do {
            try await connection.close()
        } catch {
            logger.debug("close failed: \(PostgresError.classify(error).description, privacy: .public)")
        }
    }

    // MARK: - Cancellation (R13)

    /// `SELECT pg_cancel_backend(pid)` over a second, short-lived connection: the only public
    /// way to stop the running statement on the server (decision 2026-08-27).
    func cancelRunning() async throws(PostgresError) {
        guard let pid = backendPID else { return }
        do {
            let secret = try await password()
            let helper = try await PostgresConnection.connect(
                configuration: try makeConfiguration(password: secret), id: Int.random(in: 1...Int.max),
                logger: nioLogger)
            defer { Task { try? await helper.close() } }
            try await helper.query("SELECT pg_cancel_backend(\(pid))", logger: nioLogger)
        } catch {
            throw PostgresError.classify(error)
        }
    }

    // MARK: - Queries (R7, R12, R15)

    /// Runs `query` on the connection, streaming its rows; the caller consumes the sequence and
    /// calls `finished()` when it is drained or has failed (R4: the connection stays busy until
    /// then).
    func execute(_ query: PostgresQuery) async throws(PostgresError) -> PostgresRowSequence {
        let connection = try await connect()
        touch()
        do {
            let sequence = try await connection.query(query, logger: nioLogger)
            activeQueries += 1
            return sequence
        } catch {
            let classified = PostgresError.classify(error)
            if connection.isClosed {
                state = .error(classified.description)
            }
            throw classified
        }
    }

    /// R4: the sequence of an `execute` is over, whatever its outcome; the inactivity timer
    /// counts from here, so the 10 minutes start when the query ends and not when it started.
    func finished() {
        activeQueries = max(0, activeQueries - 1)
        touch()
    }

    /// Every row of a Foreman-generated query, within `timeout` (R7: catalog queries are bounded).
    func rows(
        _ query: PostgresQuery, timeout: Duration = PostgresClient.catalogTimeout
    ) async throws(PostgresError) -> [PostgresRow] {
        try await PostgresDeadline.run(within: timeout) { try await self.collect(query) }
    }

    /// Collects the whole sequence, releasing the busy count whatever happens.
    private func collect(_ query: PostgresQuery) async throws(PostgresError) -> [PostgresRow] {
        let sequence = try await execute(query)
        defer { finished() }
        do {
            return try await sequence.collect()
        } catch {
            throw PostgresError.classify(error)
        }
    }

    /// R4: the inactivity timer, re-armed at the start and at the end of every query.
    private func touch() {
        lastActivity = .now
        idleClose?.cancel()
        idleClose = Task { [weak self] in
            guard (try? await Task.sleep(for: ConnectionLifecycle.idleLimit)) != nil else { return }
            await self?.closeIfIdle()
        }
    }

    /// R4, the idle timer fired.
    ///
    /// A query still streaming keeps the connection — `finished()` arms the timer again when the
    /// last one ends, so a long statement is never cut mid-stream.
    private func closeIfIdle() async {
        guard !isBusy else { return }
        await close()
    }
}
