import Foundation
import Testing
import WebKit

@testable import Foreman

/// browser R1, R2, R5: the section, the policy and the title, pure parts.
struct BrowserTests {
    @Test func sectionAcceptsHttpAndHttpsOnly() {
        #expect(BrowserConfig.parse(nil).url == nil)
        #expect(BrowserConfig.parse(BrowserConfig(url: " ")).url == nil)
        #expect(
            BrowserConfig.parse(BrowserConfig(url: "http://localhost:3000")).url == URL(string: "http://localhost:3000")
        )
        #expect(BrowserConfig.parse(BrowserConfig(url: " https://example.com/x ")).url?.host() == "example.com")
        for bad in ["localhost:3000", "file:///tmp/x", "ftp://x", "not a url"] {
            let parsed = BrowserConfig.parse(BrowserConfig(url: bad))
            #expect(parsed.url == nil, Comment(rawValue: bad))
            #expect(parsed.warning?.contains(bad) == true)
        }
    }

    @Test func policyLoadsWebHandsSchemesToTheSystemAndRefusesTheRest() throws {
        #expect(BrowserTab.policy(for: try #require(URL(string: "https://x.dev/a"))) == .load)
        #expect(BrowserTab.policy(for: try #require(URL(string: "about:blank"))) == .load)
        #expect(BrowserTab.policy(for: try #require(URL(string: "blob:https://x.dev/1-2-3"))) == .load)
        #expect(BrowserTab.policy(for: try #require(URL(string: "mailto:a@b.c"))) == .system)
        #expect(BrowserTab.policy(for: try #require(URL(string: "vscode://open"))) == .system)
        #expect(
            BrowserTab.policy(for: try #require(URL(string: "file:///etc/hosts")))
                == .refuse("Local files are not shown here."))
        #expect(
            BrowserTab.policy(for: try #require(URL(string: "data:text/html,<h1>hi</h1>")))
                == .refuse("This page cannot be shown."))
        #expect(
            BrowserTab.policy(for: try #require(URL(string: "javascript:alert(1)")))
                == .refuse("This link cannot be opened."))
    }

    /// browser R5 (2026-08-30): another application is only launched for a click on the top page.
    @Test func onlyAClickOnTheTopPageMayReachAnotherApplication() {
        #expect(BrowserTab.mayOpenInSystem(isMainFrame: true, navigationType: .linkActivated))
        #expect(BrowserTab.mayOpenInSystem(isMainFrame: true, navigationType: .formSubmitted))
        #expect(!BrowserTab.mayOpenInSystem(isMainFrame: false, navigationType: .linkActivated))
        for scripted: WKNavigationType in [.other, .reload, .backForward, .formResubmitted] {
            #expect(!BrowserTab.mayOpenInSystem(isMainFrame: true, navigationType: scripted))
        }
    }

    @Test func theConfirmationNamesTheSchemeAndBoundsThePagesURL() throws {
        let prompt = BrowserTab.openPrompt(for: try #require(URL(string: "mailto:a@b.c")))
        #expect(prompt.title == "Open a \u{201C}mailto\u{201D} link in another application?")
        #expect(prompt.detail == "mailto:a@b.c")

        let padded = try #require(URL(string: "vscode://x/" + String(repeating: "a", count: 500)))
        let long = BrowserTab.openPrompt(for: padded)
        #expect(long.detail.count == 301)
        #expect(long.detail.hasSuffix("\u{2026}"))
    }

    @Test func titleFallsBackToTheHost() throws {
        let url = try #require(URL(string: "http://localhost:3000/admin"))
        #expect(BrowserTab.displayTitle("Dashboard", url: url) == "Dashboard")
        #expect(BrowserTab.displayTitle("  ", url: url) == "localhost")
        #expect(AgentMention.url(url).text(relativeTo: URL(filePath: "/ws")) == "http://localhost:3000/admin ")
    }
}
