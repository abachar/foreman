import Testing

@testable import Foreman

/// postgres R2, R11: what a config reload may and may not touch on the live session.
@MainActor
struct PostgresModelTests {
    private func config(database: String = "db", port: Int = 5432) -> PostgresConfig {
        var config = PostgresConfig(database: database, user: "u")
        config.port = port
        return config
    }

    /// R2, R11: the section decoded again to the same connection leaves the dot and the writes
    /// toggle alone — the server session did not restart, so the header must not say it did.
    @Test func refreshingAnUnchangedSectionKeepsTheLiveSession() {
        let model = PostgresModel()
        model.apply(.configured(config(), warnings: []))
        model.setState(.connected)
        model.setAllowWrites(true)

        model.setConfig(.configured(config(), warnings: ["postgres.port 70000 is out of range, using 5432."]))

        #expect(model.state == .connected)
        #expect(model.allowWrites)
        #expect(model.label == "u@localhost/db")
        #expect(model.configMessage == nil)
        #expect(model.warnings.count == 1)
    }

    /// R2: another database is another connection: the session starts over, read-only (R11).
    @Test func anotherConnectionStartsTheSessionOver() {
        let model = PostgresModel()
        model.apply(.configured(config(), warnings: []))
        model.setState(.connected)
        model.setAllowWrites(true)
        model.error = "relation does not exist"

        model.apply(.configured(config(database: "other"), warnings: []))

        #expect(model.state == .disconnected)
        #expect(!model.allowWrites)
        #expect(model.error == nil)
        #expect(model.label == "u@localhost/other")
    }

    /// R2: the section removed — the message replaces the label and the session is gone.
    @Test func aMissingSectionReplacesTheLabelWithItsMessage() {
        let model = PostgresModel()
        model.apply(.configured(config(), warnings: ["kept until the next decode"]))
        model.apply(.missing("No \"postgres\" section"))

        #expect(model.label == nil)
        #expect(model.configMessage == "No \"postgres\" section")
        #expect(model.warnings.isEmpty)
    }
}
