# Study — browser

> Feature `browser` (2026-08-28): a web page as a center tab, to look at what the agent just built (`localhost:3000`, a docs site, a PR) without leaving the workspace. Decisions in [`decisions.md`](decisions.md), open points in [`questions.md`](questions.md).

## Goal

The loop *agent edits → `run` serves → I look at the page* leaves the window today. A browser tab keeps it inside: the page next to the code, the diff and the agent, with the same splits, shortcuts and restoration as every other tab. It is a **developer's viewport**, not a browser product: address bar, back/forward/reload, zoom, Web Inspector, bookmarks from the config — nothing else.

## User stories

- US1 — I click *Browser* in the toolbar: a tab opens on `config.browser.home` (`http://localhost:3000`); `cmd+r` still runs my `dev` command, the page reloads with `cmd+shift+r`.
- US2 — I split the center: the page on the right, `views.tsx` on the left; the agent edits, Vite hot-reloads, I see it.
- US3 — I right-click on an element › *Inspect Element*: Safari's Web Inspector opens on the page.
- US4 — I close the window and reopen the workspace: the tab is back on the same URL.
- US5 — `cmd+e` in the page sends its URL to the agent's prompt ("fix the layout of http://localhost:3000/admin").
- US6 — The *Browser* button's menu lists my bookmarks (`App`, `Docs`, `Storybook`) from `config.browser.bookmarks`.

## Functional rules

### Tab

- R1 — Tab kind `browser.page`, payload `{ "url": "<string>" }` (`layout` R28); title = the page's title, else its host, else `Browser`; icon `globe` in the bar and on the home screen (no file icon). Any number of browser tabs, in any group (`product` R4).
- R2 — Entry points: the toolbar item `browser.open` (`trailing`, before ▶ Run, `layout` R30), whose click opens a tab on the home URL (R8) and whose menu lists *New Tab*, then the bookmarks (R8); the home screen entry *Browser*; the shortcut `cmd+shift+o` (`browser.open`, global) — the same as the button.
- R3 — Content: one `WKWebView` per tab, created when the tab is first shown and loaded then (`architecture` P4); kept alive while the tab exists (switching tabs does not reload); released on close. Restoration (`product` R6): the URL only, loaded at the first show; no history, no scroll position, no form content.
- R4 — Chrome above the page, on the island (`design` R8): back, forward, reload/stop, an address field (the current URL, editable), the page zoom shown when it is not 100 %. No tab strip of its own (the layout's tab bar is the tab strip), no status bar, no favicon.

### Navigation

- R5 — The address field accepts a URL; without a scheme, `http://` is prepended (`localhost:3000`, `example.com/x`); whitespace is trimmed; text that does not parse as a URL is refused in place (the field turns red, nothing loads). **No search engine**: Foreman sends nothing anywhere the user did not type (`architecture`, security).
- R6 — Allowed schemes: `http`, `https`, `about:blank`, and `file` **only under the workspace root** (a built static site); any other `file` URL, `javascript:` and custom schemes are refused with a banner. Certificate errors are shown by WebKit's own page, never bypassed.
- R7 — Links: a normal click navigates in the tab; `cmd+click`, `window.open` and `target=_blank` open a **new browser tab** in the same group (the layout's R14 placement). A link with a non-web scheme (`mailto:`, `vscode:`) goes to the system (`NSWorkspace.open`). Downloads are refused with a banner in v1 (out of scope below).
- R8 — Config section `browser` (`config` R3): `{ "home": "<url>", "bookmarks": { "<name>": "<url>" } }`; `home` defaults to `about:blank`; bookmarks are listed in the button's menu in declaration order (`config` R5: sorted keys) and each opens a new tab. Invalid URLs are reported and skipped (`config` R7). Hot reload (`config` R6).
- R9 — JavaScript dialogs (`alert`, `confirm`, `prompt`) are shown as sheets on the window (`NSAlert`); `beforeunload` prompts are honoured when closing the tab (`layout` R15: the tab counts as dirty while the page says so).

### Shortcuts (scope `tab(browser.page)`, `layout` R22b)

- R10 — `cmd+l` focuses the address field (the editor's `cmd+l` is go-to-line: another scope); `cmd+shift+r` reloads (`cmd+r` stays the `run` palette, decision 2026-08-28); `cmd+[` / `cmd+]` back / forward; `cmd+=` / `cmd+-` / `cmd+0` zoom in / out / reset (`pageZoom`); `escape` in the address field restores the current URL and gives the focus back to the page; `cmd+opt+i` opens the Web Inspector (R11). `cmd+e` sends the URL to the active agent (`agents` R10b extended: the URL as plain text, no `@`).
- R11 — Every web view is `isInspectable`: Safari's Web Inspector through *Inspect Element* in the page's context menu, `cmd+opt+i`, or Safari's *Develop* menu.

### Isolation and privacy

- R12 — One `WKWebsiteDataStore` **per workspace**, identified by a UUID kept in `state.json` (`browser.dataStore`; `WKWebsiteDataStore(forIdentifier:)`, macOS 14): cookies and logins of one project never leak into another; removing the workspace's state drops them. No private-browsing mode in v1.
- R13 — No bridge between the page and the app: no `WKScriptMessageHandler`, no injected script, no user agent override. The page is untrusted content (`architecture`, security): nothing it does reaches the workspace beyond R7's system links.

## Edge cases

- The home URL is down (`localhost` before `run`): WebKit's own error page, the address field keeps the URL, reload retries.
- A page that never finishes loading: the reload button shows *stop*; closing the tab cancels it.
- A tab restored on a `file://` URL whose file is gone: WebKit's error page.
- Two workspaces open on the same folder (`product` R1 forbids it): not reachable.
- `about:blank` as home: an empty page with the address field focused.

## Out of scope for v1

- Tabs history UI, bookmarks editing from the UI (the config is the editor), a search engine, autofill, extensions.
- Downloads (`WKDownload`), printing, PDF export, reader mode.
- Find in page (`cmd+f`), page source, screenshots.
- Opening the markdown preview's external links or the terminal's links inside Foreman (they keep the system browser).
- Private/ephemeral tabs; per-tab user agents; mobile viewports.

## Technical options

- **Engine**: `WKWebView` (WebKit, the platform, `architecture` P3). Nothing else considered: Chromium embedding is out of proportion, `SFSafariViewController` is iOS-only.
- **Folder**: `Browser/` with `BrowserFeature` (registration: tab kind, toolbar item, home entry, shortcuts, config section), `BrowserTab` (`@Observable`: url, title, loading, canGoBack/Forward, zoom, the `WKWebView` it owns), `BrowserTabView` (SwiftUI chrome + an `NSViewRepresentable` around the web view), `BrowserConfig` (the section), `BrowserAddress` (R5 normalisation, a pure function). ~400 lines.
- **Delegates**: `WKNavigationDelegate` for R6 (decide policy per request) and the title; `WKUIDelegate` for R7 (`createWebViewWith` → new tab) and R9 (dialogs).
- **Tests** (pure parts only): R5 normalisation (`localhost:3000`, `example.com`, `https://x`, `not a url`, whitespace), R6 policy (`file` under/outside the root, `javascript:`), R8 section decoding and invalid entries, the payload round trip, the title fallback.
