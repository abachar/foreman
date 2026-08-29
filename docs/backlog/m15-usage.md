# M15 — Usage, first round

M0–M14 built the product; **M15 is the first round driven by use, not by a plan** (2026-08-30). Every task below comes from a friction the author met while working in Foreman, or from a rule that was written and never made visible. No new folder, no dependency.

Domains: [`terminal`](../specs/terminal/) (R7), [`git`](../specs/git/) (R6b), [`explorer`](../specs/explorer/) (R7, R17, R22, R23), [`layout`](../specs/layout/) (R24, R37), [`config`](../specs/config/) (R4), [`product`](../specs/product/) (R8).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 15.1 | **The Dock asks for attention**: bell or process end on an inactive tab while the app is in the background → `requestUserAttention(.criticalRequest)`, the icon bounces until Foreman is activated (AppKit cancels the request itself). Agent and run tabs alike, one call site in `TerminalService` | terminal R7 (amended) | `NSApplication.requestUserAttention` | pure `shouldRequestAttention(event:isAppActive:isTabActive:)` | XS | 🔴 | |
| 15.2 | **The Changes panel as a tree**: one tree per group (Conflicts, Staged, Changes), folders with a single child folded into one row (`src/main/java`), folders first then names in `localizedStandardCompare` order, everything expanded, nothing persisted, no per-folder action. The row itself (status letter, hover actions) does not change | git R6b (new) | SwiftUI, the existing `GitChangeRowView` | `PathTree` building: nesting, folding, order, a single file at the root, a rename shown as one entry | S | 🔴 | |
| 15.3 | **The same folding in the explorer**: an expanded folder whose chain of single-child folders is not empty shows the whole chain on its row and lists the last segment's children. **Lazy reading is kept** (`architecture` P4): the chain is read at expansion, never ahead of it, so a collapsed row still reads `src`. Rename (`shift+F6`) and drop target the **last** segment; the chain stops at a greyed folder (R4). No config key | explorer R23 (new), R7, R11, R17, R22 (amended) | `NSOutlineView`, `FileManager` | chain resolution (stop at two children, at a greyed folder, at a file), the persisted path of a folded row | M | 🔴 | |
| 15.4 | **Shortcut problems become visible**: `ShortcutRegistry.problems` (conflicts, overrides naming an unknown action or an unparsable shortcut) shown where the config error already is, instead of the log alone. R24 asked for it since M0 and only the log ever got it | layout R24 (implemented, not amended) | — | existing `ShortcutRegistryTests` | XS | 🔴 | |
| 15.5 | **Global configuration**: `$XDG_CONFIG_HOME/foreman/config.json`, else `~/.config/foreman/config.json`, merged under the workspace file — an object section present in both is merged key by key, one level, the workspace wins; any other value is replaced. Watched and hot-reloaded like the workspace file; invalid → the last valid global stays and the error is shown (config R7). `docs/config.md` says where each key belongs | config R4 (amended), R6, R7 | AsyncFileMonitor (the existing `FSWatchService`) | merge (one level, workspace wins, section only in one file, non-object value replaced), path resolution with and without `XDG_CONFIG_HOME` | S/M | 🔴 | |
| 15.6 | **Menus**: a menu bar generated from the `ShortcutRegistry` (one submenu per feature namespace, the R33 grouping), and **every menu shows the shortcut of the action it offers** — tab context menu (R35), explorer context menu (R20), a toolbar item's secondary menu (R31). Key equivalents are shown, never bound: the registry's monitor takes the event first (to be checked before anything else is built). The bar is rebuilt when the key window changes, the actions being per window | layout R37 (new), R22, R31, R33, R35, explorer R20 | `NSMenu`, `NSMenuItem.keyEquivalent` | the menu built from a registry (grouping, order, shortcut text) | M | 🔴 | |
| 15.7 | **Launching without a folder reopens the last project**: the folders opened are noted in the system's recent list; at launch, a command-line argument first, then a folder handed by the system, then the most recent one that still exists, then `$HOME`. *File ▸ Open Recent* lists them | product R8 (amended) | `NSDocumentController.noteNewRecentDocumentURL` / `recentDocumentURLs` | the launch folder chosen from (argument, pending folder, recents, home), a missing recent folder skipped | S/M | 🔴 | |

## Definition of done

- An agent rings while Foreman is behind the browser: the icon bounces until the app is activated, and stops on its own.
- A repo with changes across several folders reads as a tree in the Changes panel; `src/main/java/Foo.java` costs one folder row, not four.
- Expanding `src` in the explorer shows `src/main/java` on one row and its files under it; renaming that row renames `java`.
- A shortcut declared twice in `config.json` says so in the window, not only in Console.
- `agents` and `shortcuts` written once in `~/.config/foreman/config.json` apply to every workspace; a workspace that overrides one agent keeps the others.
- Every action reachable by a shortcut is also reachable from the menu bar, with its shortcut written next to it, and the menus of a right click say the same thing.
- Launching Foreman from the Dock reopens the project of the day before, not `$HOME`.

## Decisions taken during the milestone

- **The Dock bounces, notifications stay out** (2026-08-30): `requestUserAttention` needs nothing from the system and works on an unsigned build, unlike `UNUserNotificationCenter`, and Foreman cannot tell "waiting for input" from "finished" anyway — both are a bell (`terminal` R7).
- **A numbered Dock badge is deferred** (2026-08-30): it counts across every window, which nothing owns today; the bounce is enough until use says otherwise (`terminal/questions.md`).
- **The global config comes back** (2026-08-30): it cancels the "no global configuration" decision of 2026-08-26 and reinstates the merge written the same day. Reason from use: `agents`, `shortcuts` and `theme` are the same in every workspace and were being copied by hand.
- **Folding is revealed at expansion, not before** (2026-08-30): IntelliJ reads ahead to show `src/main/java` on a collapsed tree; Foreman keeps P4 and shows `src` until it is expanded.
