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
