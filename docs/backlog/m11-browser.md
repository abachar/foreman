# M11 — Browser

M11 = **a web page as a center tab** ([`../specs/browser/00-study.md`](../specs/browser/00-study.md), 2026-08-28): look at what the agent built without leaving the workspace. One new folder `Browser/`, no dependency added (WebKit is the platform).

Domain covered: [`browser`](../specs/browser/).

The **Library / native** column is mandatory (`AGENTS.md`).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 11.1 | **Docs**: this backlog, the study, decisions, questions; `specs/README.md`, `architecture.md` (overview, structure, retained dependencies), `shortcuts.md` rows | — | — | — | S | 🟢 (2026-08-28) | |
| 11.2 | **The tab**: `BrowserFeature` (tab kind `browser.page`, payload `{url}`, toolbar item + menu, home entry, `cmd+shift+o`, `browser` config section with hot reload), `BrowserTab` (`@Observable`, owns the `WKWebView`, created at first show), `BrowserTabView` (chrome: back/forward/reload-stop, address field, zoom; `NSViewRepresentable` around the web view), `BrowserAddress` (R5), per-workspace data store (R12, UUID in `state.json`), restoration on the URL | browser R1–R5, R8, R12; layout R28, R30 | `WKWebView`, `WKWebsiteDataStore(forIdentifier:)`, `NSToolbar` item through `Layout` | R5 normalisation; R8 decoding (invalid URL skipped, `home` default); payload round trip; title fallback | M | ⚪ | |
| 11.3 | **Policy and delegates**: R6 scheme policy (`file` under the root only, `javascript:` refused, banner), R7 new-tab popups and system links, R9 JS dialogs as sheets and `beforeunload` as a dirty tab, R11 `isInspectable`, R10 tab shortcuts (`cmd+l`, `cmd+shift+r`, `cmd+[`/`]`, zoom, `cmd+opt+i`), R13 no bridge | browser R6, R7, R9–R11, R13; layout R15 | `WKNavigationDelegate`, `WKUIDelegate`, `NSAlert`, `NSWorkspace.open` | R6 policy as a pure function (under/outside root, schemes) | S | ⚪ | |
| 11.4 | **Send to agent**: `cmd+e` in a browser tab writes the URL (plain text) into the active agent; `agents` R10b amended | agents R10b, browser R10 | `AgentsFeature.send(.literal)` (already there) | the mention text for a URL | S | ⚪ | |

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Definition of done

- `cmd+shift+o` on a workspace with `"browser": { "home": "http://localhost:3000" }` shows the page next to an editor tab; `cmd+r` still opens the run palette; `cmd+shift+r` reloads.
- The tab comes back on its URL after a relaunch; two workspaces do not share cookies (log in on one, the other is logged out).
- *Inspect Element* opens the Web Inspector; a `file://` outside the root is refused with a banner.
- No `…Manager`/`…Service`, no protocol, no dependency; the page never reaches the app (no script handler).

## Decisions to take during the milestone

- 11.2: whether the address field is a `TextField` (SwiftUI) or an `NSTextField` — the `escape` and `cmd+l` focus handling decides.
- 11.3: `beforeunload` through `layout` R15 needs the tab's `isDirty` to follow the page; if WebKit does not expose it cleanly, closing runs the prompt through `WKUIDelegate` and the layout's confirmation is skipped for browser tabs.
