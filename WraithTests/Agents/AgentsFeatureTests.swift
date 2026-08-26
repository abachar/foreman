import Foundation
import Testing

@testable import Wraith

/// The button's decision and the badge (agents R4, R6), the persisted payload (R8).
struct AgentsFeatureTests {
    @Test func buttonActivatesRelaunchesOrSpawns() {
        let tab = TabID()
        #expect(AgentsFeature.buttonAction(primary: nil, state: nil) == .spawn)
        #expect(AgentsFeature.buttonAction(primary: tab, state: nil) == .spawn)
        #expect(AgentsFeature.buttonAction(primary: tab, state: .idle) == .activate(tab))
        #expect(AgentsFeature.buttonAction(primary: tab, state: .running(pid: 1)) == .activate(tab))
        #expect(AgentsFeature.buttonAction(primary: tab, state: .exited(.code(0))) == .relaunch(tab))
    }

    @Test func badgeShowsRunningThenMarked() {
        #expect(AgentsFeature.badge(running: true, marked: true) == .dot(.green))
        #expect(AgentsFeature.badge(running: false, marked: true) == .dot(.orange))
        #expect(AgentsFeature.badge(running: false, marked: false) == .none)
    }

    @Test func payloadRoundTripsWithARelativeFolder() throws {
        let payload = AgentsFeature.Payload(id: "claude", cwd: "backend")
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(AgentsFeature.Payload.self, from: data) == payload)
        #expect(AgentsFeature.kind(of: "claude") == "agent.claude")
    }
}
