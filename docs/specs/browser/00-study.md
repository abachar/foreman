# Study — browser

> Feature `browser` (2026-08-28, cut down the same day): **one** web page per window, on the URL of the config, to look at what the agent just built. Decisions in [`decisions.md`](decisions.md), open points in [`questions.md`](questions.md).

## Goal

The loop *agent edits → `run` serves → I look at the page* leaves the window today. One browser tab per window, like an agent's tab: a button, the page on `config.browser.url`, Safari's Web Inspector, a private session wiped at every launch. Nothing of a browser product: no bookmarks, no history, no tabs of its own.

## User stories

- US1 — `.foreman/config.json` says `"browser": { "url": "http://localhost:3000" }`: a *Browser* button appears; I click it, the page opens in a tab; clicking again activates that tab.
- US2 — I split the center: the page on the right, the code on the left; Vite hot-reloads, I see it.
- US3 — Right-click › *Inspect Element*: the Web Inspector opens (Elements, Console, Network…; I hide the tabs I do not want from its own tab bar, it remembers).
- US4 — I relaunch Foreman: the tab is back on the config URL, logged out (private session).
- US5 — *Clear Website Data* in the button's menu: cookies and storage gone, the page reloaded.

## Functional rules

- R1 — **One browser tab per window**, kind `browser.page`, no payload beyond the kind (the URL is the config's). The button (`browser.open`, toolbar `center`, right after the agents' buttons — the same family, `layout` R30) and `cmd+shift+o` open it in the active group, or activate it when it exists (`agents` R4 by analogy). Title: the page's title, else the host; icon `globe`. A second tab cannot be opened.
- R2 — Config section `browser` (`config` R3): `{ "url": "<http or https URL>" }`. **Without a valid `url`, there is no button and no tab** (`agents` R2 by analogy); an invalid URL is reported (`config` R7). Hot reload (`config` R6): a new URL loads in the existing tab.
- R3 — Content: one `WKWebView`, created when the tab is first shown and loaded then (`architecture` P4), kept alive while the tab exists; released on close. Restoration (`product` R6): the tab comes back on the config URL (not the last visited page).
- R4 — Chrome above the page, on the island (`design` R8): back, forward, reload/stop, the current URL (read-only, selectable). Navigation is the page's links; there is no address field to type in (the URL is the config's).
- R5 — Allowed: `http`, `https`, and the config's host; `file:`, `javascript:` and custom schemes are refused with a banner. Certificate errors: WebKit's page, never bypassed. Links with a non-web scheme (`mailto:`, `vscode:`) go to the system. `window.open` / `target=_blank` navigate **in the tab** (a single tab, R1). Downloads are refused with a banner.
- R6 — **Private session**: a non-persistent `WKWebsiteDataStore` per window (`WKWebsiteDataStore.nonPersistent()`): cookies, local storage and caches live in memory and vanish with the window. *Clear Website Data* (the button's menu) removes every data type of the store and reloads. Nothing is written under `~/Library` for the page.
- R7 — `isInspectable`: Safari's Web Inspector through *Inspect Element* (context menu) or Safari's *Develop* menu; there is no API to open it from the app, so no shortcut (found while shipping, 2026-08-28). Its tab set is the inspector's own setting (right-click on its tab bar; WebKit persists it) — there is no API for the host to restrict it.
- R8 — JavaScript dialogs (`alert`, `confirm`, `prompt`) as sheets (`NSAlert`). `beforeunload` is not asked when the tab closes (a private session has nothing to lose).
- R9 — Shortcuts (scope `tab(browser.page)`): `cmd+shift+r` reload (`cmd+r` stays the `run` palette), `cmd+[` / `cmd+]` back / forward, `cmd+e` sends the URL to the active agent (`agents` R10b: the URL as plain text). Zoom is WebKit's own `cmd+=` / `cmd+-` (native, no registration).
- R10 — No bridge between the page and the app: no `WKScriptMessageHandler`, no injected script, no user agent override. The page is untrusted content (`architecture`, security).

## Edge cases

- The URL is down (`localhost` before `run`): WebKit's error page; reload retries.
- The section is removed while the tab is open: the tab stays until closed, the button disappears.
- A page that never finishes loading: the reload button shows *stop*; closing the tab cancels it.

## Out of scope for v1

- Several tabs, bookmarks, history, an address field to type in, a search engine.
- Persistent sessions (a login that survives a relaunch), per-project cookie stores.
- Downloads, find in page, printing, zoom shortcuts of Foreman's own.
- Restricting the Web Inspector's tabs (no API; the inspector remembers the user's choice).

## Technical options

- **Engine**: `WKWebView` (`architecture` P3); nothing else.
- **Folder**: `Browser/` — `BrowserFeature` (registration, config section, the single tab like `AgentsFeature.primaryTabs`), `BrowserTab` (`@Observable`: url, title, loading, canGoBack/Forward; owns the `WKWebView` and its ephemeral store), `BrowserTabView` (chrome + `NSViewRepresentable`), `BrowserConfig` (the section, a pure decode). ~250 lines.
- **Delegates**: `WKNavigationDelegate` (R5 policy, title), `WKUIDelegate` (R8 dialogs; `createWebViewWith` returns `nil` after loading the request in the tab, R5).
- **Tests**: R2 decoding (missing, invalid, `http`/`https` only), R5 policy as a pure function, the title fallback.
