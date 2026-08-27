import Foundation
import Testing

@testable import Wraith

/// postgres R5, R19: the feature's error and its messages.
struct PostgresErrorTests {
    @Test func cancellationIsClassified() {
        guard case .cancelled = PostgresError.classify(CancellationError()) else {
            Issue.record("expected cancelled")
            return
        }
    }

    @Test func ownErrorsPassThrough() {
        guard case .timeout = PostgresError.classify(PostgresError.timeout(.seconds(10))) else {
            Issue.record("expected timeout")
            return
        }
    }

    @Test func unknownErrorsAreWrapped() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        guard case .underlying = PostgresError.classify(error) else {
            Issue.record("expected underlying")
            return
        }
        #expect(PostgresError.classify(error).description == "boom")
    }

    @Test func serverErrorShowsItsSQLState() {
        #expect(
            PostgresError.server(message: "syntax error", sqlState: "42601", position: 3).description
                == "syntax error (42601)")
        #expect(PostgresError.server(message: "m", sqlState: nil, position: nil).description == "m")
        #expect(PostgresError.timeout(.seconds(10)).description.contains("10 s"))
    }
}
