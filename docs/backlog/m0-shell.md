# M0 — Shell

M0 = **Shell**: an app that opens a folder in a window, with its zones, its panels, its tabs, its shortcuts, its toolbar, its home screen, and that persists and restores its state. No business feature: the only content is the home screen and a demo tab.

Domains covered: [`product`](../specs/product/), [`config`](../specs/config/), [`layout`](../specs/layout/).

The **Library / native** column is mandatory (`AGENTS.md`): what we use instead of writing. The **Tests** column: what is tested, nothing else.

## Tasks

Each task depends only on the previous ones. One task = one PR.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 0.1 | **Skeleton**: Xcode project created by the author (SwiftUI macOS app, Swift 6, strict concurrency, target 26, no sandbox, a Swift Testing test target), Xcode `.gitignore`, `.swift-format`, a `Foreman/<feature>/` tree, a CI workflow with `xcodebuild test` + lint | — | Xcode template | none | S | 🟢 | — |
| 0.2 | **Window = folder**: opening a folder (the *Open…* menu, a CLI argument, `application(_:open:)`), one window per folder, activation when it is already open, `$HOME` by default; `cli/foreman` script | product R1, R2, R8; the "folder gone" edge case | SwiftUI `WindowGroup(for: URL.self)` + `openWindow`, `NSOpenPanel`, `NSApplicationDelegateAdaptor`; the CLI = `open -a Foreman "$(pwd)"` | folder resolution (argument → canonical URL, `$HOME` by default) | S | 🟢 | |
| 0.3 | **`Workspace`: config**: reading `.foreman/config.json` (no global config, decision 2026-08-26), per-feature sections (`config.section("x")` → `Decodable`), an error with its line, the `password` key ignored with a warning, missing `repos` ignored | config R1–R5, R7, R11 | `JSONSerialization` (parsing, `NSJSONSerializationErrorIndex` → line), `JSONDecoder` per section | sections exposed; invalid JSON → the last valid config + the error line/message; `password` ignored; missing section → empty | M | 🟢 | |
| 0.4 | **`Workspace`: `state.json`**: read at startup, atomic debounced write ~1 s and on close, a schema version, `.bak` when unreadable, relative/absolute paths, a read-only root reported once | config R8–R10; edge cases | `FileManager.replaceItemAt`, `JSONSerialization` (a versioned envelope) + `Codable` per section, `Task` + `Task.sleep` for the debounce | round trip; unknown version → defaults + `.bak`; a path under/outside the root; the debounce (two close writes = a single one) | M | 🟢 | |
| 0.5 | **`FSWatchService`**: one FSEvents stream per workspace, path filters, ~300 ms debounce, `AsyncStream<[URL]>`; `Workspace.configChanges` wired to it (the config hot-reloaded) | config R6; architecture (a shared resource) | **AsyncFileMonitor** (`FolderContentMonitor`, decision 2026-08-26); `FSWatchService` = prefix filtering + batches | debounce/coalescing over a temporary directory; config modified → the new value on `configChanges`, invalid → no emission + an error | M | 🟢 | |
| 0.6 | **Split tree**: `enum LayoutNode` (`split`/`group`), pure operations `split(group, orientation)`, `close(group)`, `neighbor(of:direction:)`, `moveTab(direction)`, equal-share geometry | layout R7–R12; the "split refused under 300×150" edge case | — (pure logic, ~150 lines) | each operation over trees of 1 to 5 groups; the split collapsing; the last group never closing; the neighbour by overlap | M | 🟢 | |
| 0.7 | **Tab groups**: `TabGroup` (an ordered list, an active tab), insertion after the active tab, closing → the left neighbour/first tab, `isDirty` → chained confirmations, a single active group | layout R13–R15, R17 | — (pure logic) | insertion/closing/activation; the confirmation chain (cancelling stops everything) | S | 🟢 | |
| 0.8 | **`PanelManager`**: `[PanelSide: PanelID?]` state, toggle/replacement, `activate`/`deactivate` on the feature, lazy and retained `makeView`, focus (show → the panel, hide/`escape` → the active group) | layout R1–R6; the duplicate-id and changed-side edge cases | — (pure logic) | toggle on the same shortcut; replacement in the same slot; `makeView` called once; `activate`/`deactivate` symmetric | S | 🟢 | |
| 0.9 | **`ShortcutRegistry`**: parsing `"cmd+shift+g"`, the `global`/`tab(kind)` scopes, the `shortcut → action` table, `config.shortcuts` overrides, conflicts → neither bound + an error, recomputation on `configChanges`, terminal-surface priority (everything except `cmd+…`) | layout R22–R26; config R4 | `NSEvent.addLocalMonitorForEvents(.keyDown)` | parsing (valid/invalid); a conflict after an override; a `tab` scope masking `global`; the user overriding a layout shortcut; a feature unable to override the layout | M | 🟢 | |
| 0.10 | **Rendering the zones**: `NSSplitViewController` (left / center / right) + a second one for center / bottom, collapsible items, default and minimum sizes, persistence per slot, automatic shrinking then hiding when the window is too small, minimum window size | layout R18–R21; the off-screen frame edge case | `NSSplitViewController`, `NSSplitViewItem` (`canCollapse`, `minimumThickness`), `NSWindow.minSize` | size computation (a pure function: available space → sizes/hiding in the order right, left, bottom) | L | 🟢 | |
| 0.11 | **Rendering the center**: the split tree → views (a non-resizable `NSSplitView`, or `HStack`/`VStack` with equal shares), a single tab bar (scrollable, the active tab visible, a minimum width), a home screen for an empty group (actions + shortcuts, agents, recents — empty sections in M0), keyboard navigation between groups | layout R16, R33–R34; product R3, R5 | SwiftUI for the tab bar and the home screen | none (views) | L | 🟢 | |
| 0.12 | **Toolbar**: `NSToolbar` + a delegate in `Layout/`, item registration by the features (`id`, title, SF Symbol icon, placement, action or menu, badge), `cmd+opt+t` persisted; in M0: empty (validated with a demo item, removed afterwards) | layout R30–R32 | `NSToolbar`, `NSToolbarItem`, `NSMenu` | a duplicate id refused; the leading/trailing order | M | 🟢 | |
| 0.13 | **Layout persistence**: the `layout` section of `state.json` (tree, groups, tabs with `id`/`kind`/opaque payload, active tab, visible panels, sizes, window frame), restoration in R29's order, unknown `kind` ignored, panels activated after the first frame | layout R27–R29; product R6 | `Codable` | full round trip; unknown `kind` → the tab ignored + the group collapsing; the restoration order (activation after the frame) | M | 🟢 | |
| 0.14 | **Demo tab** `demo.hello`: a minimal `CenterTabDescriptor` (a text view, the payload = the title) to exercise tabs, splits, moving and persistence end to end; along with it, the three demo panels (`cmd+shift+1/2/3`) and the toolbar item (`Foreman/Demo/`); removed at the start of M1 | — | — | none | S | 🟢 | |

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done (with the PR number).

## Definition of done (M0)

- `foreman .` opens a window on the folder; running it again activates the existing window.
- `cmd+d` / `cmd+shift+d` split, `cmd+w` closes, `cmd+opt+←→↑↓` navigate, `cmd+opt+shift+←→↑↓` move a `demo.hello` tab.
- Three demo panels (one per slot, removed afterwards) toggle, replace each other, resize, and their sizes survive a reopen.
- An invalid `config.json` shows the error with its line; an overridden `shortcuts` applies hot; a conflict shows both ids.
- Closing and reopening restores splits, tabs, panels, sizes and the frame.
- `xcodebuild test` covers every "Tests" line above; lint clean; a single SPM dependency added (AsyncFileMonitor, decision 2026-08-26).

## To decide during M0 (decisions expected)

- 0.1: CI targets Xcode 27 through `setup-xcode`; unverified as long as the GitHub runners do not have 27 — to be confirmed at the first push, otherwise switch the workflow to `continue-on-error` until it is available.
- 0.11: rendering the center in pure SwiftUI or with nested `NSSplitView`s — **settled (2026-08-26): pure SwiftUI** (`HStack`/`VStack` with equal shares, `Divider`), since the splits are not resizable.
- 0.11: `cmd+t` stays free (removed along with the shell tab) — **settled (2026-08-26): free until M1.**
