# layout — Study

## Goal

Define the structure of a workspace window: the toolbar, the zones, the split tree of the center zone, the tab groups, the panel state machine (`PanelManager`) and the shortcut registry (`ShortcutRegistry`). This domain knows no concrete tab kind or panel: it hosts what the features declare when they register with `Layout` at startup (`architecture`).

## Geometry

```
│ [Claude] [OpenCode]      TOOLBAR              [▶ Run] │
┌──────────┬──────────────────────────────────┬──────────┐
│          │ ┌────────────────┬─────────────┐ │          │
│  LEFT    │ │ [t1] [t2]      │ [file.md]   │ │  RIGHT   │
│  panel   │ │  group A       │  group B    │ │  panel   │
│          │ ├────────────────┴─────────────┤ │          │
│          │ │ [t3]         group C         │ │          │
│          │ └──────────────────────────────┘ │          │
│          ├──────────────────────────────────┤          │
│          │           BOTTOM panel           │          │
└──────────┴──────────────────────────────────┴──────────┘
```

- The center zone (CENTER) is the whole split tree; the three panel slots frame it globally, never per split.
- LEFT and RIGHT take the full height; BOTTOM takes the width of CENTER only.
- The toolbar (TOOLBAR) is the window's native bar, above the four zones; it is not part of the zone layout.

## User stories

- US1 — I press a panel's shortcut: it appears in its slot; I press it again: it disappears. The center content does not move or lose its state.
- US2 — Two features declare a panel on the left; calling the second replaces the first without destroying it (its state is kept).
- US3 — I split the active group (vertically or horizontally): a new empty group appears with the home screen, and takes the focus; I open a file or an agent in it.
- US4 — I move between groups and tabs entirely from the keyboard.
- US5 — I resize the panels with the mouse and find their sizes again when I reopen.
- US6 — A feature declares a shortcut that is already taken: I know it at startup, and I can override it in `config.json`.

## Functional rules

### Zones and panels

- R1 — A window has exactly four zones: `center` (always visible) and three optional slots `left`, `right`, `bottom`, topped by a toolbar (R30–R32).
- R2 — A slot shows at most one panel at a time. `PanelManager`'s state is `[PanelSide: PanelID?]` (three optionals).
- R3 — Toggle: the shortcut of the panel visible in its slot hides it; the shortcut of another panel of the same slot replaces it; the shortcut of a hidden panel shows it. One shortcut never drives two slots.
- R4 — Hidden panels keep their UI state (expanded tree, selection, scroll) but consume nothing (`architecture`: laziness): the feature receives `deactivate()` and stops its work; `activate()` starts it again.
- R5 — A panel is only built (`makeView`) at its first activation; its view is then kept in memory for as long as the window lives.
- R6 — Keyboard focus: showing a panel gives it the focus; hiding it gives the focus back to the active tab group. `escape` from a panel gives the focus back to the center without hiding the panel.

### Center zone: splits and groups

- R7 — The center zone is a binary tree: node = `split(orientation, first, second)`, leaf = `group(id)`. The tree always has at least one leaf.
- R8 — A split shares the space **equally** between its two children. Splits are not resizable in v1.
- R9 — Splitting the active group (`cmd+d` / `cmd+shift+d`) creates a sibling: `vertical` puts the new group on the right, `horizontal` below. **The active tab moves into the new group**, which becomes active; the command is refused (beep) when the group holds fewer than two tabs (amended 2026-08-28; until then the new group was empty). Opening a tab "in a new group" (`explorer` R13, the palette's `cmd+enter`) still creates an empty sibling and opens the tab there.
- R10 — Closing the last tab of a group closes the group; the parent split collapses (the sibling takes all the space). The last group of the tree never closes: closing its last tab leaves it empty, on the home screen (R33).
- R11 — Moving between groups by direction (`←→↑↓`): the target is the neighbouring group whose rectangle overlaps the active group the most in that direction. No neighbour → no effect.
- R12 — Moving the active tab to the neighbouring group in a direction: the tab leaves its group (R10 applies if the group empties) and becomes the active tab of the target group. No neighbour → no effect. No drag and drop in v1.

### Tab groups

- R13 — A group is an ordered list of tabs + an active tab. Each tab has a stable `id` (a UUID generated at creation, persisted), a `kind` (a namespaced id declared by a feature: `editor.file`, `agent.claude`, `run.backend:test`, `git.diff`…), a title, a "modified" state (`isDirty`) and a "preview" state (`isPreview`, italic title, `editor` R2) provided by its owner.
- R14 — A new tab is inserted just after the active tab and becomes active. Closing the active tab activates its left neighbour, or the first tab if there is none.
- R15 — Closing an `isDirty` tab asks for confirmation (the wording belongs to the owning feature, the mechanism to the layout). Closing a group or a window chains the confirmations one by one.
- R16 — The tab bar is a single component (`product` R3): tabs scroll horizontally when there are too many, the active tab is always visible, no tab is truncated below a minimum width.
- R17 — There is exactly one **active group** per window; clicking in a group, moving into it from the keyboard or opening a tab in it makes it active. All tab commands (new, close, `cmd+1..9`) apply to the active group.

### Resizing and sizes

- R18 — Only panels are resizable, with the mouse, by their inner edge. The width of a side panel and the height of a bottom panel are persisted **per panel** in `state.json` (`panelSizes`, keyed by panel id; amended 2026-08-28, per slot until then — the old per-slot keys are simply dropped at restoration). A panel that was never resized takes its slot's default (R19).
- R19 — Default sizes: `left` 260 pt, `right` 320 pt, `bottom` 240 pt. Minimum for a panel: 160 pt. The center zone always keeps at least 300 × 150 pt (400 × 200 until 2026-08-26).
- R20 — Minimum window size: 800 × 500 pt. If space is still missing (a shrunk window with three panels open), the panels are **shrunk to their minimum** in the order `right`, `left`, `bottom`, then hidden in the same order; they come back on their own when the space returns. Their persisted size is not modified by this adjustment.
- R21 — The tabs of a group receive the size of the group; content that needs to know its size (a terminal surface) receives it through a resize callback, debounced by the producer.

### Shortcuts

- R22 — A shortcut is declared, never captured ad hoc (`coding-rules`). The `ShortcutRegistry` is the single `shortcut → action` table, fed by: the layout's actions (below), the features' panels and actions, then the overrides (`config` R4).
- R22b — Every action has a **scope**: `global` (default), `tab(kind)` (only active while a tab of that kind has the focus in the active group), or `panel` (only active while a panel has the focus; `escape`, decision 2026-08-27). Two actions with disjoint scopes may share a shortcut; a `tab(kind)` action masks a `global` action with the same shortcut while it is active. The layout's actions are global.
- R23 — The layout's default shortcuts (`config` notation):

  | Action | Shortcut |
  |---|---|
  | Close the active tab | `cmd+w` |
  | Go to tab N of the active group | `cmd+1` … `cmd+9` (`cmd+9` = last) |
  | Previous / next tab | `cmd+shift+[` / `cmd+shift+]` |
  | Vertical / horizontal split | `cmd+d` / `cmd+shift+d` |
  | Focus the neighbouring group | `cmd+opt+←` `→` `↑` `↓` |
  | Move the tab to the neighbouring group | `cmd+opt+shift+←` `→` `↑` `↓` |
  | Give the focus back to the center | `escape` (from a panel only) |
  | Hide / show the toolbar | `cmd+opt+t` |

- R24 — Conflicts: two actions on the same shortcut **after** the overrides are applied → neither is bound, and an error is shown with both ids. A feature cannot redefine a layout shortcut; only the user can, through `config.json`. **Precision 2026-08-30** (the rule has not changed, its second half was never implemented): "shown" means in the window, in the same place as a config error (`config` R7) — at startup and after every rebuild (R26) — and covers the three problems the registry knows: a conflict, an override naming an unknown action, an override that does not parse. The log alone does not satisfy R24.
- R25 — Capture priority: the registry receives the key event before the tab's content, **except** for a terminal surface (agent, run) that has the focus: it receives everything that is not a `cmd+…` shortcut (`ctrl`/`opt` combinations alone belong to it). A shortcut without `cmd` can therefore only be declared for a non-terminal context (`escape` is the only such case in v1).
- R26 — Shortcuts can be overridden hot (`config` R6): an event from `Workspace.configChanges` rebuilds the whole table and reapplies R24.

### Persistence (`state.json`, see `config`)

- R27 — The layout owns the `layout` section of `state.json`: split tree, groups (ordered tabs with `id`, `kind`, the feature's opaque payload, the active tab), the active group, the visible panel per slot, the size per slot, the window frame.
- R28 — A tab's payload is an opaque JSON string provided by the owning feature (`serialize`) and handed back as is at restoration (`restore`). An unknown `kind` at restoration, or a `restore` that fails → the tab is ignored (R10 applies). The layout never reads the payload.
- R29 — At restoration, the order is: rebuild the tree and the groups, restore the tabs, apply the visible panels, then give the focus to the active group. Panels restored visible are activated (R4) after the first frame, not before (`architecture`: nothing at startup that could wait).

### Toolbar

- R30 — The window has a native toolbar (`NSToolbar`). It contains only items declared by the features (`id`, title, icon, placement, kind): placement `leading`, `center` or `trailing` (amended 2026-08-27, `design` R15: the Explorer toggle leads, the agents are centred, Run and the Database/Git/History toggles trail; `center` is new); kind *action* (click → callback) or *menu* (click → a list of entries provided on demand, with subtitles and badges). Order: the features' registration order, `leading` on the left, `trailing` on the right. The layout declares the panel toggles itself (amended 2026-08-27): one *action* item per registered panel of the left and right slots, whose badge-less icon carries a 1 pt accent outline while the panel is visible.
- R31 — An item may carry a **badge** (`none` / `dot(color)`) updated by the owning feature (agent running, run failed). An item whose `id` is already taken is refused and logged as a `fault`. Right-clicking (or long-clicking) an *action* item opens its secondary menu when it declares one.
- R32 — `cmd+opt+t` hides/shows the toolbar (persisted in `state.json`). The items' actions stay reachable through their shortcuts and through the palette.

### Home screen

- R33 — A group **without tabs** shows the home screen, in the spirit of IntelliJ's empty zone, on **two columns** (amended 2026-08-28; until then one column with a hand-picked "Actions" list in the middle): on the left the available agents (buttons, `agents` R2) then the workspace's recent files (`editor` R19); on the right, as documentation, **every action of the `ShortcutRegistry` that has a shortcut**, grouped by the feature its id is namespaced under (`layout`, `explorer`, `editor`…), features and actions in registration order, each row performing its action; a **family** of actions (same parent id, same modifiers, titles sharing a leading phrase) is folded into one row (`Tab N · cmd+N`, `Focus Group · cmd+opt+←→↑↓`, `Move Line · opt+↑↓`). The two columns are centred in the group. The left entries are provided by the features through a home-entry registration (`id`, title, icon, section `agents`/`recent`, action; same rules as R30); the layout knows none of them inline.
- R34 — The home screen is not a tab: it does not appear in the bar, does not close, is not persisted. Opening a tab in the group replaces it; closing the last tab brings it back (R10). It takes the group's keyboard focus (global shortcuts work, `escape` has no effect).
- R35 — **Tab context menu** (2026-08-28): right-clicking a tab of the bar opens a native menu with, in this order: *Close*, *Close Other Tabs*, *Close All Tabs*, *Close Unmodified Tabs*, *Close Tabs to the Left*, *Close Tabs to the Right*. Every entry acts on the group of the clicked tab, not on the active group; the clicked tab is the pivot of *Others*, *Left* and *Right*. *Unmodified* closes the tabs that are not `isDirty`, the clicked one included. The tabs close one by one in bar order through R15 (a dirty tab asks its owner; a refusal stops the rest), R10 applies if the group empties. An entry with nothing to close is disabled.
- R36 — **A feature shows only what it can serve** (2026-08-29, generalising `agents` R2 and `browser` R2): a panel, a toolbar item and a global shortcut exist only while the feature has content — `git` needs a repo (`git` R1b), `postgres` its section (`postgres` R2), `run` a command (`run` R6b). `Layout` exposes `unregister(panel:)`, `removeToolbarItem`, `shortcuts.unregister`; withdrawing a visible panel hides and deactivates it, and frees its shortcut. A panel registered after the restoration (R29) takes its restored slot if nothing filled it since. Tab kinds stay registered so tabs restore (R28).

### Menus

- R37 — **The menu bar is the Mac's, filled from the `ShortcutRegistry`** (2026-08-30, from use; the first wording — one submenu per feature namespace — was tried the same day and dropped: it read as `Layout / Editor / Explorer / Postgres / Git / Terminal / Browser / Run` and overflowed the bar). The bar is `File / Edit / View / Tools / Run`, before the `Window` and `Help` macOS owns; `File`, `Edit` and `View` already exist, so Foreman's entries are **appended** to them under a separator, never a second menu of the same name. The map:

  | Menu | Entries |
  |---|---|
  | File | Open… · Open Recent ▸ (`product` R8) · Quick Open… · Save · Save All · Close Tab |
  | Edit | *(the natives macOS puts there)* · Find · Find and Replace… · Find in Project… · Go to Line… · Toggle Comment · Indent · Outdent · Move Line Up / Down · Format File · Fold / Unfold Region |
  | View | Explorer · Toggle Toolbar · Toggle Markdown Preview · Tabs ▸ (previous, next, 1…9) · Split ▸ · Focus Group ▸ · Move Tab ▸ · Focus Center · Zoom In / Out |
  | Tools | Agents ▸ (one per `config.agents`) · Git ▸ · Postgres ▸ · Browser ▸ |
  | Run | Run Command… · Stop Command · Clear Scrollback |

  Nothing is declared twice: the map names action ids and everything else — title, shortcut, what the action does — comes from the registry (R22). **Having a shortcut is not a reason to be in a menu, and having none is not a reason to be left out**: an agent has no default shortcut and belongs there, *Send to Agent* has one and does not (it is the same action three times, one per scope). An action the map names but no feature registered is dropped, submenus and separators left empty with it: a window without a repo shows no *Git* submenu. The commands of `config.json` stay in the ▶ Run button, not in the menu. Because the actions belong to a window and the bar belongs to the app, the bar is rebuilt when the key window changes.
- R37b — **Every menu shows the shortcut of the action it offers**: the menu bar, the tab context menu (R35), a toolbar item's secondary menu (R31) and the features' context menus (`explorer` R20). The text comes from `ShortcutRegistry.shortcut(for:)`, so it follows the user's overrides. In the menu bar the key equivalent is **shown, not bound**: the registry's key monitor takes the event first (R25) and an item must never fire a second time — to be verified before the bar is built.

## Edge cases

- A persisted window frame outside the current screens: the window is recentred on the main screen with its persisted size (clamped to the screen).
- Two features declare the same `PanelID`: the second is refused and logged as a `fault` (a programming invariant, the features are compiled together).
- A panel changes slot between two versions (the feature changed its `side`): the `[side: id]` state no longer finds it in the old slot → considered hidden.
- `cmd+N` with N > the number of tabs: no effect (except `cmd+9` = last).
- A split when the center zone can no longer guarantee 300 × 150 pt per group after dividing: the split is refused (system beep), nothing changes.
- The window closes during an R15 confirmation: cancelling the confirmation cancels the close.

## Out of scope for v1

- Resizing splits (fixed equal shares).
- Zooming / temporarily maximising a group.
- Tab drag and drop (between groups or to reorder); reordering from the keyboard.
- Pinned tabs, hover preview, middle-click to close.
- Several visible panels in the same slot (stacked or as tabs).
- Floating or detached panels (`product`).
- Splits with more than two children (the binary tree covers every arrangement).

## Technical options

- **Split tree**: an indirect `enum LayoutNode: Codable` (`split`/`group`) in `Layout/`, manipulated by `LayoutManager` (`@MainActor @Observable`). The operations (split, close, neighbor, move) are pure functions over the tree + the computed geometry, tested without UI (it is a state machine).
- **Panel rendering**: `NSSplitView` (an `NSSplitViewController` with three collapsible `NSSplitViewItem`s) for left / center / right, and a second one for center / bottom; minimum sizes and per-slot persistence through the native APIs (`holdingPriority`, `collapsed`). The center zone's splits (equal shares, not resizable) stay in SwiftUI (`HStack`/`VStack`). No manual layout through `GeometryReader` (`architecture`: use the platform).
- **Shortcuts**: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` at window level, ahead of SwiftUI; the registry decides and either consumes or passes the event on (R25). No SwiftUI `.keyboardShortcut` scattered around (R22).
- **Toolbar**: `NSToolbar` with its delegate in `Layout/`; the item list and their badges live in `LayoutManager`. SwiftUI `.toolbar` rejected (order and secondary menus are hard to control, R30–R31).
- **Feature registration**: `struct`s internal to `Layout/` — `PanelDescriptor(id, title, side, defaultShortcut, makeView)`, `CenterTabDescriptor(kind, makeView(payload), serialize)`, a toolbar item (`id, title, icon, placement, kind`) and a home entry (`id, title, icon, section, action`) — handed to `Layout` by each feature at startup (`GitFeature.register(in:)`). Activating/deactivating a panel and closing a tab are closures on the descriptor, not broadcast events.

## Decisions

See [decisions.md](decisions.md).
