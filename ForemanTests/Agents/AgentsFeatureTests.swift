import Foundation
import Testing

@testable import Foreman

/// The button's decision and the badge (agents R4, R6), the persisted payload (R8).
struct AgentsFeatureTests {
    @Test func buttonActivatesRelaunchesOrSpawns() {
        let tab = TabID()
        #expect(AgentsFeature.buttonAction(primary: nil, state: nil) == .spawn)
        #expect(AgentsFeature.buttonAction(primary: tab, state: nil) == .spawn)
        #expect(AgentsFeature.buttonAction(primary: tab, state: .running(pid: 1)) == .activate(tab))
        #expect(AgentsFeature.buttonAction(primary: tab, state: .exited(.code(0))) == .relaunch(tab))
    }

    /// agents R8: a restored tab is idle with its command never run — the button must start it.
    @Test func buttonStartsARestoredTabThatNeverRan() {
        let tab = TabID()
        #expect(AgentsFeature.buttonAction(primary: tab, state: .idle) == .relaunch(tab))
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

    /// git R32: the session base survives a relaunch of the app.
    @Test func payloadKeepsTheSessionSnapshot() throws {
        let payload = AgentsFeature.Payload(
            id: "claude", cwd: "",
            session: AgentsFeature.Session(repo: ".", base: "4b825dc642cb6eb9a060e54bf8d69288fbee4904"))
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(AgentsFeature.Payload.self, from: data) == payload)
        // A payload written before M10 still decodes.
        let old = try JSONDecoder().decode(AgentsFeature.Payload.self, from: Data(#"{"id":"pi","cwd":"x"}"#.utf8))
        #expect(old.session == nil)
    }
}

/// agents R12–R13: naming and the payload of a worktree tab.
struct AgentWorktreeTests {
    @Test func nameCarriesTheAgentAndTheMinute() throws {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 8, 28, 14, 5)
        components.timeZone = .current
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))
        #expect(AgentsFeature.worktreeName(agent: "claude", date: date) == "claude-20260828-1405")
        #expect(
            AgentsFeature.title("Claude Code", branch: "foreman/claude-20260828-1405")
                == "Claude Code (foreman/claude-20260828-1405)")
    }

    @Test func folderLivesUnderApplicationSupport() {
        let folder = AgentsFeature.worktreeFolder(
            workspace: "Kanstrimi TV", name: "claude-20260828-1405",
            applicationSupport: URL(filePath: "/Users/me/Library/Application Support"))
        #expect(
            folder.path(percentEncoded: false)
                == "/Users/me/Library/Application Support/Foreman/worktrees/Kanstrimi TV/claude-20260828-1405")
    }

    @Test func payloadKeepsTheWorktree() throws {
        let payload = AgentsFeature.Payload(
            id: "claude", cwd: "/tmp/wt", session: nil,
            worktree: AgentsFeature.Worktree(repo: "", folder: "/tmp/wt", branch: "foreman/claude-20260828-1405"))
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(AgentsFeature.Payload.self, from: data) == payload)
    }
}

/// agents R10, R10a: the mention text and the active agent choice.
struct AgentSendTests {
    let cwd = URL(filePath: "/ws/app")

    @Test func mentionIsRelativeUnderTheCwd() {
        let file = URL(filePath: "/ws/app/src/main.swift")
        #expect(AgentMention.path(file, lines: nil, isDirectory: false).text(relativeTo: cwd) == "@src/main.swift ")
        #expect(
            AgentMention.path(file, lines: 12...12, isDirectory: false).text(relativeTo: cwd) == "@src/main.swift:12 ")
        #expect(
            AgentMention.path(file, lines: 12...30, isDirectory: false).text(relativeTo: cwd)
                == "@src/main.swift:12-30 ")
    }

    @Test func folderKeepsItsSlashAndOutsidePathsStayAbsolute() {
        let folder = URL(filePath: "/ws/app/src")
        #expect(AgentMention.path(folder, lines: nil, isDirectory: true).text(relativeTo: cwd) == "@src/ ")
        let outside = URL(filePath: "/ws/other/x.txt")
        #expect(AgentMention.path(outside, lines: nil, isDirectory: false).text(relativeTo: cwd) == "@/ws/other/x.txt ")
        #expect(AgentMention.literal("abc1234").text(relativeTo: cwd) == "@abc1234 ")
    }

    @Test func activeAgentIsTheLastActivatedLiveTab() {
        let first = TabID()
        let last = TabID()
        let candidates: [(id: TabID, state: TerminalState?)] = [(first, .idle), (last, .running(pid: 1))]
        #expect(AgentsFeature.activeAgentTab(lastActivated: last, candidates: candidates) == last)
        #expect(AgentsFeature.activeAgentTab(lastActivated: nil, candidates: candidates) == first)
        #expect(AgentsFeature.activeAgentTab(lastActivated: TabID(), candidates: candidates) == first)
    }

    @Test func exitedAndGoneTabsAreSkipped() {
        let exited = TabID()
        let gone = TabID()
        let live = TabID()
        let candidates: [(id: TabID, state: TerminalState?)] = [
            (exited, .exited(.code(0))), (gone, nil), (live, .idle),
        ]
        #expect(AgentsFeature.activeAgentTab(lastActivated: exited, candidates: candidates) == live)
        #expect(AgentsFeature.activeAgentTab(lastActivated: nil, candidates: [(exited, .exited(.code(1)))]) == nil)
    }
}
