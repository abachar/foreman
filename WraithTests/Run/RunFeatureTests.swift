import Foundation
import Testing

@testable import Wraith

/// The launch decision (run R7, R9), the tab state and badge (R10), the persisted payload (R13).
struct RunFeatureTests {
    @Test func launchSpawnsRelaunchesOrStopsFirst() {
        let tab = TabID()
        #expect(RunFeature.launchAction(primary: nil, state: nil, newTab: false) == .spawn)
        #expect(RunFeature.launchAction(primary: tab, state: nil, newTab: false) == .spawn)
        #expect(RunFeature.launchAction(primary: tab, state: .idle, newTab: false) == .relaunch(tab))
        #expect(RunFeature.launchAction(primary: tab, state: .exited(.code(1)), newTab: false) == .relaunch(tab))
        #expect(RunFeature.launchAction(primary: tab, state: .running(pid: 1), newTab: false) == .stopThenRelaunch(tab))
        #expect(RunFeature.launchAction(primary: tab, state: .running(pid: 1), newTab: true) == .spawn)
    }

    @Test func stateFollowsTheExitCode() {
        #expect(RunFeature.RunState(.idle) == .idle)
        #expect(RunFeature.RunState(.running(pid: 1)) == .running)
        #expect(RunFeature.RunState(.exited(.code(0))) == .succeeded)
        #expect(RunFeature.RunState(.exited(.code(2))) == .failed(2))
        #expect(RunFeature.RunState(.exited(.signal(SIGINT))) == .failed(nil))
    }

    @Test func badgeShowsRunningThenTheResultUntilShown() {
        #expect(RunFeature.badge(.running, marked: false) == .dot(.blue))
        #expect(RunFeature.badge(.succeeded, marked: true) == .dot(.green))
        #expect(RunFeature.badge(.failed(1), marked: true) == .dot(.red))
        #expect(RunFeature.badge(.failed(1), marked: false) == .none)
        #expect(RunFeature.badge(.idle, marked: true) == .none)
    }

    @Test func payloadRoundTripsWithARelativeFolder() throws {
        let payload = RunFeature.Payload(id: "backend:test", cwd: "backend")
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(RunFeature.Payload.self, from: data) == payload)
        #expect(RunFeature.kind(of: "backend:test") == "run.backend:test")
    }
}

/// The palette rows (run R5).
struct RunPaletteTests {
    private let root = URL(filePath: "/ws")

    private func command(_ repo: String, _ name: String, problem: String? = nil) -> RunCommand {
        RunCommand(
            id: RunCatalog.id(repo: repo, name: name), repo: repo, name: name, command: "make \(name)",
            cwd: root, env: [:], problem: problem)
    }

    @Test func withoutAQueryRecentsComeFirstThenTheCatalogOrder() {
        let commands = [command(".", "lint"), command("backend", "build"), command("backend", "test")]
        let items = RunFeature.items(commands, recents: ["backend:test", "gone:x"], query: "")
        #expect(items.map(\.id) == ["backend:test", "root:lint", "backend:build"])
        #expect(items.first?.subtitle == "make test")
    }

    @Test func aQueryRanksFuzzilyOnRepoAndName() {
        let commands = [command(".", "lint"), command("backend", "build"), command("backend", "test")]
        let items = RunFeature.items(commands, recents: [], query: "bt")
        #expect(items.first?.id == "backend:test")
        #expect(!items.map(\.id).contains("root:lint"))
    }

    @Test func aGreyedCommandShowsItsReason() {
        let items = RunFeature.items(
            [command("frontend", "dev", problem: "repo not found: frontend")], recents: [], query: "")
        #expect(items.first?.subtitle == "repo not found: frontend")
    }
}
