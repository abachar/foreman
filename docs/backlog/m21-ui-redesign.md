# M21 — UI redesign

Sixth round driven by use (2026-10-16): the window takes the layout of the thirteen reference views in [`design/02-redesign/`](../specs/design/02-redesign/), designed with the author from IntelliJ, Xcode, Kiro and Zed. The islands and the tokens of M8 stay; what moves is **where things live** — panel tabs instead of toolbar toggles, a status bar, the History, Search, Run and Problems tabs at the bottom, the Database on the right — and the editor gains the reading aids of IntelliJ.

Domains: [`layout`](../specs/layout/00-study.md) (R2, R3, R17, R30 amended; status bar new), [`design`](../specs/design/00-study.md) (R3, R5, R15, R17 amended), [`git`](../specs/git/00-study.md) (Changes and History move; branch menu new), [`run`](../specs/run/00-study.md) ("No panel" amended), [`editor`](../specs/editor/00-study.md) (Problems, print margin, indent guides, matched braces, sticky lines new; R27 amended), [`config`](../specs/config/00-study.md) (R7: errors also in Problems). Each task writes its rules (dated) in the same commit; the gaps are listed in [`02-redesign/README.md`](../specs/design/02-redesign/README.md#gaps-with-the-current-specs-to-amend-when-the-tasks-are-planned). No dependency added.

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Verified before M21 (2026-10-16, on `main` 0b8d7b5)

- **Panels** (`Layout/PanelManager.swift`): one visible panel per slot, `[PanelSide: PanelID?]`. Registered today: `explorer.tree` *Explorer* left, `git.changes` *Changes* right, `git.history` *History* right, `postgres.schema` *Schema* right, `editor.search` *Search* bottom. `PanelHeaderView` (28 lines) is a title, not tabs.
- **Toolbar** (`Layout/WorkspaceToolbar.swift`, option A of M8): the layout adds one toggle per left/right panel (R30, design R15), the agents and *Browser* are `.center`, *Run* is `.trailing` and is already a pull-down (`RunFeature.menuEntries`).
- **Run**: a command opens a **center terminal tab** (`kind: run.<id>`, `isTerminal: true`), reused on relaunch (`run` US2).
- **Diagnostics**: `LSPServers` publishes per URL, but `EditorFeature+LSP` keeps them **only on the open tab** (`EditorTab.diagnostics`): a project-wide list needs a store.
- **Editor gutter**: `LineNumberRulerView` (`NSRulerView`) already draws the numbers and a chevron on the first line of each fold region (R27); `CurrentLineTextView` paints the current line (design R22). No margin line, no guides, no brace matching, no sticky lines.
- **Active group**: an accent stroke when the centre holds more than one group (design decision 2026-08-27) — dropped by this milestone.
- **History** (M20): the commit's files under the log (`VSplitView`), sized for a side panel.

## What waits for another milestone

- The **theme feature** (a designed light theme, a theme picker): a milestone of its own (author, 2026-10-16).
- The **toolbar centre**: empty for now; a status zone needs an agent driven through an SDK, a CLI agent does not say what it is doing.
- A **Specs / backlog panel** with *Start task*: neither kept nor dropped.
- **Other operating systems**: Foreman stays Swift + AppKit (author, 2026-10-16).

## Tasks

Each task depends on the previous ones unless noted. One branch `feat/redesign` from `main` for the whole milestone, one commit per task (author, 2026-10-16). **By eye**: each task is checked against its reference view.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 21.1 | **Panel tabs**: a slot's header lists **every panel registered on that side** as tabs (icon, title, count badge), a click shows that panel (R3's replace, state kept); *Explorer* renamed *Project*, *Schema* renamed *Database*; `git.changes` moves to the **left**, `git.history` to the **bottom**; a panel persisted on its old side comes back hidden (existing edge case) | layout R2, R3 amended; design R17; git (surfaces) amended | `PanelHeaderView` → a SwiftUI tab strip; `PanelManager` gains `panels(on:)`, the descriptor an `order` and a `badge` | panels per side in registration order; a tab click replaces, the hidden panel keeps its state; restoration of a moved panel. **By eye**: views 04, 05, 06 | M | 🟢 | `feat/redesign` |
| 21.2 | **Status bar**: a 28 pt bar under the zones — three slot toggles (left / bottom / right: shows the slot's last panel, or hides it), the active file's ⊗ / ⚠ counters, then items the active tab provides through a new `CenterTabDescriptor.statusItems` (editor: LSP server state, `line:col`, language, encoding; terminal: `cols×rows`; diff: `+n −n`; browser: host); no branch there; the panel toggles **leave the toolbar** | layout new rule (status bar), R30 amended; design R15 amended, new rule (status bar look) | SwiftUI in `WorkspaceView`; `PanelManager` gains the last panel per side (persisted in `state.json`) | last panel per side (first registered by default, persisted, a withdrawn panel R36); position and diff counters as pure functions. **By eye**: every view, status bar | M | ⚪ | |
| 21.3 | **Toolbar**: left, a **project widget** (name ▾: *Open…*, *Open Recent ▸*, *Reveal in Finder*) then the branch widget's button (menu in 21.4); centre **empty**; right, the agents with their badges, *Browser* (only with `config.browser.url`), then the **Run widget** (current command ▾, ▶, ■ in one group, the icon carrying the last state ✓ / ✗ / ●) | layout R30 amended (placements); design R15 amended; run (widget) amended; browser R1 (place) | `NSToolbar`, `ToolbarButton`, `NSMenu` | the Run widget's state from `RunFeature`'s states; the toolbar order (`ToolbarTests` updated). **By eye**: views 01, 08, 10 | M | ⚪ | |
| 21.4 | **Branch widget menu**: current branch and *n worktrees* in the button; the menu lists the worktrees (folder, the agents working there with their badge, ahead count, a submenu: *Compare with main*, *Check out in main folder*, *Reveal in Finder*, *Remove worktree…*), local then remote branches, *Fetch*, *Pull*, *Push*, *New branch…*, *Stash changes…*, with a filter field; several repos → one submenu per repo | git new rule (branch menu), reusing R36–R39 actions | `NSMenu` with a search field item (`NSMenuItem.view`), existing `GitCLI` operations | menu entries built from the model as a pure function (order, current checked, held branches tagged, agents attached). **By eye**: view 11 | M | ⚪ | |
| 21.5 | **Run in the bottom panel**: a `run.output` bottom panel, one sub-tab per command (state chip ✓ / ✗ / ●), *Restart*, *Stop* (`cmd+.`), *Clear scrollback*; launching a command shows the panel and its sub-tab; the center `run.<id>` tabs disappear (restored sub-tabs instead, `run` R13) | run study ("No panel") and R13 amended; layout | `TerminalService` / `TerminalSurfaceView` reused as is, SwiftUI chips | launch opens or reuses the sub-tab (US2), the state per command, restoration of the sub-tabs. **By eye**: view 08 | L | ⚪ | |
| 21.6 | **History at the bottom**: the wide layout — the commit's files **beside** the log (`HSplitView`) instead of below; rows in columns: refs as chips, full message, author, date, short hash; filter field and *All branches* in the panel header | git R19, R19b amended | SwiftUI `HSplitView`, `FileTreeView` (M20) | the existing history tests; the row's ref chips from `for-each-ref` (pure). **By eye**: view 05 | M | ⚪ | |
| 21.7 | **Problems**: an `editor.problems` bottom panel fed by a **diagnostics store** keeping every URL a server publishes (not only open tabs); scope *Current file* / *Project*, error and warning filters with counts, a message filter, groups per file, the config and shortcut problems first (`config` R7, `layout` R24) as a *Foreman config* group; a click opens the file at the position; the status bar counters (21.2) open it on *Current file* | editor new rules (Problems); config R7 amended; layout R24 amended | SwiftUI `List` with sections, `FileIcon` | the store (publish replaces a URL, an empty list clears it, closing a tab keeps the project scope), scope and filters, ordering. **By eye**: views 12, 13 | M | ⚪ | |
| 21.8 | **Editor, first pass**: a 1 pt `separator` line between the gutter and the text; a **print margin** at column 120 (`editor.printMargin`, 0 = off, `docs/config.md`); the active group's accent stroke removed — the active tab's accent underline, a grey underline for the other groups' active tab | editor new rule (print margin); design R3, R5 amended; layout R17 amended | `NSRulerView.draw`, `CurrentLineTextView.drawBackground(in:)` | the margin's x from the font advance (pure); config decoding of the key. **By eye**: views 02, 03, 10 | S | ⚪ | |
| 21.9 | **Indent guides, active block, matched braces**: one guide per indentation level of the visible lines (blank lines take the surrounding level, tab width honoured); the guide of the caret's innermost block brightened; the brace at or before the caret and its pair highlighted, skipping strings and comments | editor new rules | `CurrentLineTextView.drawBackground(in:)`, `Folding` regions, the highlight roles (strings / comments), TextKit 2 rendering attributes | guide levels for a buffer (pure), the active block from the caret and the regions, bracket matching across strings and comments. **By eye**: view 02 | L | ⚪ | |
| 21.10 | **Fold markers**: an opening marker on a region's first line and a closing one on its last; the caret's block markers in `textPrimary`, the others in `textDisabled` | editor R27 amended | `LineNumberRulerView` | the markers per line for a set of regions (pure). **By eye**: view 02 | S | ⚪ | |
| 21.11 | **Sticky lines**: the first lines of the enclosing regions (class, method…) scrolled above the viewport stay pinned at the top of the editor, on the editor's own ground with a separator under them, at most 3; a click scrolls to the line | editor new rule | an `NSView` over the `NSScrollView`'s clip view, `Folding` regions | the pinned lines for a top visible line and a set of regions (pure), the cap. **By eye**: view 02 | M | ⚪ | |
| 21.12 | **Review against the reference views**: the author goes through `02-redesign/` view by view on a real workspace; the gaps found become dated decisions or a task of M22 | — | — | **By eye**: the thirteen views | S | ⚪ | |

## Decided during the milestone

Settled by the author on 2026-10-16, before 21.1; each is dated in the `decisions.md` of its domain.

- The status bar never hides, and has no shortcut of its own (`layout`). (21.2)
- A slot toggle on a side whose panel was never shown opens the slot's first panel — Project, History, Database (`layout`). (21.2)
- History keeps the linear log, with its branch and tag chips; the lanes of view 05 wait for a later milestone (`git`). (21.6)
- The config error banner stays, next to the *Foreman config* group of Problems (`config`). (21.7)
- Sticky lines: 3 at most, for the languages with folding rules (`editor`). (21.11)

## Where it stands

Planned on 2026-10-16. 21.1 done the same day (panel tabs; Changes left, History bottom).
