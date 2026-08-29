import Foundation
import Testing

@testable import Foreman

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

/// The ▶ Run menu and badge (run R6b), the stop escalation (R9).
struct RunToolbarTests {
    private func command(_ repo: String, _ name: String, problem: String? = nil) -> RunCommand {
        RunCommand(
            id: RunCatalog.id(repo: repo, name: name), repo: repo, name: name, command: "make \(name)",
            cwd: URL(filePath: "/ws"), env: [:], problem: problem)
    }

    @Test func menuListsCommandsWithTheirBadge() {
        let rows = RunFeature.menuRows([command(".", "test"), command("x", "y", problem: "repo not found: x")]) {
            $0 == "root:test" ? .dot(.blue) : .none
        }
        #expect(rows.map(\.badge) == [.dot(.blue), .none])
        #expect(rows.map(\.isEnabled) == [true, false])
        #expect(rows[1].subtitle == "repo not found: x")
    }

    @Test func buttonBadgeIsBlueThenRedThenNone() {
        #expect(RunFeature.toolbarBadge(anyRunning: true, hasUnseenFailure: true) == .dot(.blue))
        #expect(RunFeature.toolbarBadge(anyRunning: false, hasUnseenFailure: true) == .dot(.red))
        #expect(RunFeature.toolbarBadge(anyRunning: false, hasUnseenFailure: false) == .none)
    }

    @Test func secondStopWithinTwoSecondsEscalatesToTerm() {
        let now = ContinuousClock.now
        #expect(RunFeature.stopSignal(lastStop: nil, now: now) == SIGINT)
        #expect(RunFeature.stopSignal(lastStop: now, now: now + .seconds(1)) == SIGTERM)
        #expect(RunFeature.stopSignal(lastStop: now, now: now + .seconds(3)) == SIGINT)
    }
}
