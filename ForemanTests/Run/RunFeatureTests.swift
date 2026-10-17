import Foundation
import Testing

@testable import Foreman

/// The launch decision (run R7, R9), the tab state and badge (R10), the persisted payload (R13).
struct RunFeatureTests {
    /// run R7 (amended 2026-10-16): the command's sub-tab is reused, stopped first when running.
    @Test func launchSpawnsRelaunchesOrStopsFirst() {
        let tab = TabID()
        #expect(RunFeature.launchAction(session: nil, state: nil) == .spawn)
        #expect(RunFeature.launchAction(session: tab, state: nil) == .spawn)
        #expect(RunFeature.launchAction(session: tab, state: .idle) == .relaunch(tab))
        #expect(RunFeature.launchAction(session: tab, state: .exited(.code(1))) == .relaunch(tab))
        #expect(RunFeature.launchAction(session: tab, state: .running(pid: 1)) == .stopThenRelaunch(tab))
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

    /// run R13 (amended 2026-10-16): the sub-tabs persisted, then restored when their command is
    /// known, the others waiting for detection.
    @Test func subTabsRoundTripAndComeBackWhenTheirCommandIsKnown() throws {
        let state = RunFeature.State(commands: ["root:test", "backend:dev", "web:lint"], selected: "backend:dev")
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RunFeature.State.self, from: data) == state)

        let split = RunFeature.restorable(state, known: ["root:test", "backend:dev"], open: ["root:test"])
        #expect(split.now == ["backend:dev"])
        #expect(split.later == RunFeature.State(commands: ["web:lint"], selected: "backend:dev"))
        #expect(RunFeature.restorable(state, known: ["root:test", "backend:dev", "web:lint"], open: []).later == nil)
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

    /// run R15: the *Detected* line is a heading, not an entry (it was clickable, 2026-10-17).
    @Test func theDetectedHeadingIsAHeader() {
        var detected = command("api", "dev")
        detected = RunCommand(
            id: detected.id, repo: detected.repo, name: detected.name, command: detected.command, cwd: detected.cwd,
            env: [:], problem: nil, source: "package.json")
        let rows = RunFeature.menuRows([command(".", "test"), detected]) { _ in .none }
        #expect(rows.map(\.id) == ["run.root:test", "run.detected", "run.api:dev"])
        #expect(rows.map(\.isHeader) == [false, true, false])
        #expect(rows[1].isEnabled == false)
    }

    /// run R6b (amended 2026-10-16): the widget's icon carries the current command's last state.
    @Test func theWidgetIconFollowsTheState() {
        #expect(RunWidget.Icon(nil) == .none)
        #expect(RunWidget.Icon(.idle) == .none)
        #expect(RunWidget.Icon(.running) == .running)
        #expect(RunWidget.Icon(.succeeded) == .succeeded)
        #expect(RunWidget.Icon(.failed(1)) == .failed)
        #expect(RunWidget.Icon(.failed(nil)) == .failed)
    }

    /// run R10 (amended 2026-10-17): the Run tab's mark.
    @Test func theRunTabShowsRunningThenTheLastEnd() {
        #expect(RunFeature.tabMark(isRunning: true, lastEnded: .failed(1)) == .dot(.orange))
        #expect(RunFeature.tabMark(isRunning: false, lastEnded: .failed(1)) == .symbol("xmark", .red))
        #expect(RunFeature.tabMark(isRunning: false, lastEnded: .failed(nil)) == .symbol("xmark", .red))
        #expect(RunFeature.tabMark(isRunning: false, lastEnded: .succeeded) == .symbol("checkmark", .green))
        #expect(RunFeature.tabMark(isRunning: false, lastEnded: nil) == .none)
    }

    @Test func secondStopWithinTwoSecondsEscalatesToTerm() {
        let now = ContinuousClock.now
        #expect(RunFeature.stopSignal(lastStop: nil, now: now) == SIGINT)
        #expect(RunFeature.stopSignal(lastStop: now, now: now + .seconds(1)) == SIGTERM)
        #expect(RunFeature.stopSignal(lastStop: now, now: now + .seconds(3)) == SIGINT)
    }
}
