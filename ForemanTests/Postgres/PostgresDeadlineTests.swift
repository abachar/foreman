import Foundation
import Testing

@testable import Foreman

/// postgres R7, R13: the bounded wait shared by the catalog queries and the cancel answer.
struct PostgresDeadlineTests {
    @Test func theWorkWinsWhenItAnswersWithinTheLimit() async throws {
        let value = try await PostgresDeadline.run(within: .seconds(10)) { 42 }
        #expect(value == 42)
    }

    @Test func pastTheLimitTheFeaturesOwnTimeoutIsThrown() async {
        do {
            try await PostgresDeadline.run(within: .milliseconds(10)) { try await Task.sleep(for: .seconds(30)) }
            Issue.record("expected a timeout")
        } catch {
            guard case .timeout(let limit) = error else {
                Issue.record("expected a timeout, got \(error)")
                return
            }
            #expect(limit == .milliseconds(10))
        }
    }

    @Test func theWorksOwnErrorIsClassifiedAndKept() async {
        do {
            _ = try await PostgresDeadline.run(within: .seconds(10)) { () -> Int in
                throw PostgresError.passwordRequired
            }
            Issue.record("expected the work's error")
        } catch {
            guard case .passwordRequired = error else {
                Issue.record("expected passwordRequired, got \(error)")
                return
            }
        }
    }
}
