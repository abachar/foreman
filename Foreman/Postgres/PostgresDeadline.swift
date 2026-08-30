import Foundation

/// The feature's one deadline race (postgres R7, R13): the work and a sleep, whichever finishes
/// first, the loser cancelled.
///
/// Written once rather than twice because the two users want exactly the same thing — a bounded
/// catalog query and a bounded `pg_cancel_backend` answer — down to mapping the elapsed limit
/// onto `PostgresError.timeout`.
nonisolated enum PostgresDeadline {
    static func run<T: Sendable>(
        within limit: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async throws(PostgresError) -> T {
        let outcome = await withTaskGroup(of: Result<T, PostgresError>?.self) { group in
            group.addTask {
                do {
                    return .success(try await work())
                } catch {
                    return .failure(PostgresError.classify(error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(.timeout(limit))
        }
        return try outcome.get()
    }
}
