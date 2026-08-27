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
    /// R4: the last time a query started.
    private(set) var lastActivity = ContinuousClock.now

    private let password: @Sendable () async throws(PostgresError) -> String
    private let stateContinuation: AsyncStream<State>.Continuation
    private var connection: PostgresConnection?
    private var connecting: Task<PostgresConnection, Error>?
    private var idleClose: Task<Void, Never>?
    private let nioLogger = Logging.Logger(label: "dev.crafters.wraith.postgres")
    private let logger = os.Logger(subsystem: "dev.crafters.wraith", category: "postgres")

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
        var configuration = PostgresConnection.Configuration(
            host: config.host, port: config.port, username: config.user, password: secret, database: config.database,
            tls: try PostgresConfig.tls(for: config.sslMode) { try NIOSSLContext(configuration: .clientDefault) })
        configuration.options.connectTimeout = .seconds(Int64(Self.connectTimeout.components.seconds))
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

    /// R11, R12: the session is read-only and bounded from its first statement; values go
    /// through `set_config` binds, never into the SQL text (R15).
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
            var configuration = PostgresConnection.Configuration(
                host: config.host, port: config.port, username: config.user, password: secret,
                database: config.database,
                tls: try PostgresConfig.tls(for: config.sslMode) { try NIOSSLContext(configuration: .clientDefault) })
            configuration.options.connectTimeout = .seconds(Int64(Self.connectTimeout.components.seconds))
            let helper = try await PostgresConnection.connect(
                configuration: configuration, id: Int.random(in: 1...Int.max), logger: nioLogger)
            defer { Task { try? await helper.close() } }
            try await helper.query("SELECT pg_cancel_backend(\(pid))", logger: nioLogger)
        } catch {
            throw PostgresError.classify(error)
        }
    }

    // MARK: - Queries (R7, R12, R15)

    /// Runs `query` on the connection, streaming its rows; the caller consumes the sequence.
    func execute(_ query: PostgresQuery) async throws(PostgresError) -> PostgresRowSequence {
        let connection = try await connect()
        touch()
        do {
            return try await connection.query(query, logger: nioLogger)
        } catch {
            let classified = PostgresError.classify(error)
            if connection.isClosed {
                state = .error(classified.description)
            }
            throw classified
        }
    }

    /// Every row of a Wraith-generated query, within `timeout` (R7: catalog queries are bounded).
    func rows(
        _ query: PostgresQuery, timeout: Duration = PostgresClient.catalogTimeout
    ) async throws(PostgresError) -> [PostgresRow] {
        let result = await withTaskGroup(of: Result<[PostgresRow], PostgresError>?.self) { group in
            group.addTask {
                do {
                    return .success(try await self.execute(query).collect())
                } catch {
                    return .failure(PostgresError.classify(error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(.timeout(timeout))
        }
        return try result.get()
    }

    /// R4: the inactivity timer, re-armed at every query.
    private func touch() {
        lastActivity = .now
        idleClose?.cancel()
        idleClose = Task { [weak self] in
            guard (try? await Task.sleep(for: ConnectionLifecycle.idleLimit)) != nil else { return }
            await self?.close()
        }
    }
}
