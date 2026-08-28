# Decisions — browser

| Date | Decision | Rejected | Why |
|---|---|---|---|
| 2026-08-28 | A browser is a center tab (`browser.page`) built on `WKWebView`, with a minimal chrome (back/forward/reload, address field, zoom) and Safari's Web Inspector | A side panel; an embedded Chromium; opening the system browser | The page belongs next to the code and the agent, in the splits; WebKit is the platform (P3) and ships the inspector for free |
| 2026-08-28 | Reload is `cmd+shift+r`; `cmd+r` stays the `run` palette even in a browser tab | `cmd+r` reload, scope `tab(browser.page)` | The scope would mask the palette exactly when the user looks at the page their command serves |
| 2026-08-28 | One `WKWebsiteDataStore` per workspace (`WKWebsiteDataStore(forIdentifier:)`, its UUID in `state.json`) | The default shared store; an ephemeral store | Two projects' logins must not mix (`localhost` cookies collide across projects); ephemeral would log out on every relaunch |
| 2026-08-28 | No search engine, no bridge to the page, `file://` only under the root | A search field; a JS bridge for later | `architecture` security: nothing sent that the user did not type, nothing from the page reaches the app |
| 2026-08-28 | `cmd+click`, `window.open` and `target=_blank` open a new browser tab in the same group | Navigating in place; the system browser | OAuth popups and "open in new tab" are how dev pages work; the group is where the user looks |
