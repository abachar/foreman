# Decisions — browser

| Date | Decision | Rejected | Why |
|---|---|---|---|
| 2026-08-28 | A browser is a center tab (`browser.page`) built on `WKWebView`, with a minimal chrome and Safari's Web Inspector | A side panel; an embedded Chromium; opening the system browser | The page belongs next to the code and the agent, in the splits; WebKit is the platform (P3) and ships the inspector for free |
| 2026-08-28 | **One tab per window on `config.browser.url`**, no button without the section (the agents' model) | The first draft of the same day: any number of tabs, an address field, bookmarks, zoom shortcuts, a persistent store per workspace | "Too much for the need" (author): the page to look at is the one the project serves; everything else is a browser product |
| 2026-08-28 | Private session: a non-persistent data store per window, *Clear Website Data* in the menu | A persistent store per workspace (`WKWebsiteDataStore(forIdentifier:)`) | Asked in use: start clean, nothing written for the page; a login that has to survive is the system browser's job |
| 2026-08-28 | The Web Inspector's tab set is left to the inspector | Hiding Timelines/Profiler from the app | WebKit has no host API for it; the inspector's own tab bar menu hides tabs and remembers |
| 2026-08-28 | Reload is `cmd+shift+r`; `cmd+r` stays the `run` palette even in a browser tab | `cmd+r` reload, scope `tab(browser.page)` | The scope would mask the palette exactly when the user looks at the page their command serves |
| 2026-08-28 | No search engine, no bridge to the page, no `file://` | A search field; a JS bridge for later | `architecture` security: nothing sent that the user did not type, nothing from the page reaches the app |
