# M11 — Browser

M11 = **one web page per window** ([`../specs/browser/00-study.md`](../specs/browser/00-study.md), 2026-08-28, cut down the same day): the page of `config.browser.url` next to the code and the agent, a private session, the Web Inspector. One new folder `Browser/`, no dependency (WebKit is the platform).

Domain covered: [`browser`](../specs/browser/).

The **Library / native** column is mandatory (`AGENTS.md`).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 11.1 | **Docs**: this backlog, the study, decisions, questions; `specs/README.md`, `architecture.md`, `shortcuts.md` rows | — | — | — | S | 🟢 (2026-08-28) | |
| 11.2 | **The tab**: `BrowserConfig` (the section, R2), `BrowserFeature` (tab kind `browser.page`, the window's single tab like `AgentsFeature.primaryTabs`, toolbar item `center` after the agents, shown only with a URL, + menu *Clear Website Data*, home entry, `cmd+shift+o`, hot reload), `BrowserTab` (`@Observable`, owns the `WKWebView` on a non-persistent store, created at first show, `isInspectable`), `BrowserTabView` (chrome: back/forward/reload-stop, the URL; `NSViewRepresentable`), restoration on the config URL | browser R1–R4, R6, R7; layout R28, R30 | `WKWebView`, `WKWebsiteDataStore.nonPersistent()`, `NSToolbar` item through `Layout` | R2 decoding (missing, invalid, non-http); the title fallback | M | ⚪ | |
| 11.3 | **Policy, dialogs, shortcuts**: R5 (schemes, downloads refused, system links, popups in the tab), R8 dialogs as sheets, R9 shortcuts (`cmd+shift+r`, `cmd+[`/`]`, `cmd+opt+i`, `cmd+e` → `agents` R10b amended), R10 no bridge | browser R5, R8–R10; agents R10b | `WKNavigationDelegate`, `WKUIDelegate`, `NSAlert`, `NSWorkspace.open`, `AgentsFeature.send(.literal)` | R5 policy as a pure function | S | ⚪ | |
| 11.4 | **Agents from the config only**: the buttons follow `config.agents` (a built-in needs its id, `{}` is enough), declaration order, no `PATH` detection; `AgentCatalog.merge` keeps only declared ids, `AgentsFeature.detect` removed | agents R2 (amended 2026-08-28) | — | merge: undeclared built-ins dropped, `{}` keeps a built-in, order | S | ⚪ | |

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Definition of done

- With `"browser": { "url": "http://localhost:3000" }`, the button and `cmd+shift+o` show the page next to an editor tab; a second click activates the same tab; `cmd+r` still opens the run palette.
- Without the section: no button, no tab. Relaunch: the tab is back on the config URL, logged out; *Clear Website Data* logs out in place.
- *Inspect Element* opens the Web Inspector; a `file://` link is refused with a banner.
- No `…Manager`/`…Service`, no protocol, no dependency; no script handler.
