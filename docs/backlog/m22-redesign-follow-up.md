# M22 — Redesign, follow-up

Seventh round driven by use (2026-10-17): the author's pass over [M21](m21-ui-redesign.md) on the installed build — the gaps listed by 21.12 that the author kept, and four remarks of their own (the tab widths, the panel tabs, a slow search, a left slot with a Project view of real projects).

Domains: [`run`](../specs/run/00-study.md) (the Run tab's state), [`git`](../specs/git/02-study-worktrees.md) (R40 amended: three entries), [`layout`](../specs/layout/00-study.md) (R16 and R2 amended: tab widths, tab titles, split / more buttons), [`design`](../specs/design/00-study.md) (R5, R17 amended), [`editor`](../specs/editor/00-study.md) (R20–R21: search speed), [`explorer`](../specs/explorer/00-study.md) (the Explorer and a new Project view). Each task writes its rules (dated) in the same commit. No dependency added.

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Verified before M22 (2026-10-17, on `main` e869677)

- **Run tab** (`RunFeature.panelBadge`): a green dot while a command runs, nothing after it ends; the ✗ / ✓ is only on the command's sub-tab and on the Run widget.
- **Branch menu** (`GitBranchMenu`, git R40): no way to open an agent in a worktree, to merge it, or to add one from the menu; `GitFeature.addWorktree` and the agents' *New Worktree…* (agents R6) already exist.
- **Center tabs** (`TabButton`): 120 pt minimum, 240 pt maximum, so a short title (`pom.xml`) leaves an empty band.
- **Panel tabs** (`PanelHeaderView`): every tab shows icon and title; the left slot's two titles plus the Explorer's three buttons overflow a 260 pt panel (`Pr…` seen in the 21.11 capture).
- **Search** (`ContentSearch`, `SearchModel`): one `JSONDecoder` per `rg --json` line, a linear lookup of the file group and one SwiftUI update **per match** (up to 2 000), no cap on a line's length (a minified bundle sends megabytes per match); nothing is measured yet.
- **Projects**: `RunCatalog.manifests` already lists the manifests run detects (`package.json`, `pom.xml`, `Package.swift`, `Makefile`…), at the root, in the declared repos and in the root's first-level folders (run R14).

## Tasks

One branch `feat/m22` from `main`, one commit per task (author, 2026-10-17). **By eye**: each task is checked on the author's workspace.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 22.1 | **Run tab state**: the bottom slot's *Run* tab carries the state of the last command to end — ✗ in `statusRed` after a failure, ✓ in `statusGreen` after a success — and an orange dot while one runs; the mark goes when the failed sub-tab is shown | run R10 amended | `PanelDescriptor.badge`, `PanelCountView` (a new `ToolbarBadge.symbol`) | the tab's mark from the sessions' states (pure) | S | 🟢 | `feat/m22` |
| 22.2 | **Branch menu, three entries**: *New worktree…* under the worktrees (a branch name, the folder `<repo>-wt/<branch>` beside the repo), and in a worktree's submenu *Open terminal agent here* (the agents of `config.agents`, a submenu when there are several, agents R5 in that folder) and *Merge into <base>…* (confirmed, run in the main folder: `git merge --no-ff <branch>`, refused while the main folder is dirty) | git R40 amended, new R41 | `NSMenu`, `GitCLI`, `AgentsFeature.launch(_:in:)` | the menu entries (pure), the merge's arguments and its refusal on a dirty main folder (pure over `GitStatus`) | M | 🟢 | `feat/m22` |
| 22.3 | **Tab bar buttons**: at the right end of each group's tab bar, *Split Right* (`cmd+d`, R9) and a *…* menu (the tab context menu's close entries, *Split Right*, *Split Down*) | layout R16 amended | SwiftUI `Menu`, existing actions | the menu entries (pure). **By eye**: view 02 | S | 🟢 | `feat/m22` |
| 22.4 | **Search speed**: measure first (an `os_signpost` interval per search, the time to the first result and to the last), then: results batched to the panel (one update per 50 ms, not per match), the file group found by a dictionary, long lines cut to 300 characters around the match (`rg --json` ignores `--max-columns`); the numbers measured are written in the `editor` decisions | editor R21 amended | `rg`, `os_signpost`, `AsyncStream` | the batching, the grouping, the long-line window; the numbers in `editor` decisions; the hang (stdout and stderr through `FileHandle.bytes`) found after the author's test and fixed | M | 🟢 | `feat/m22` |
| 22.5 | **Tab widths**: a center tab is as wide as its icon, title and close button, its title up to 180 pt, truncated in the middle past it; no minimum width any more | layout R16 amended; design R5 | SwiftUI | the width rule (pure: a short and a long title) | S | 🟢 | `feat/m22` |
| 22.6 | **Panel tabs, title on the active one only** (the left slot only — Project, Explorer, Changes; author, 2026-10-17): the other tabs of the slot's header show their icon (and their count) alone, their title in the tooltip | design R17 amended; layout R2 | `PanelHeaderView` | — (**by eye**: a 260 pt left panel holds its three tabs and its buttons) | S | 🟢 | `feat/m22` |
| 22.7 | **Project, Explorer, Changes**: the left slot gets three tabs — *Project* (new: the real projects of the workspace, a folder holding a manifest of `RunCatalog.manifests` plus `build.gradle`, `Cargo.toml`, `go.mod`, at the root, in the declared repos and their first-level folders; each row the folder's name and its type's icon, a click unfolds it on its files with the explorer's tree), *Explorer* (the whole tree, today's *Project*, `explorer.tree` keeps its id and `cmd+shift+e`), *Changes* | explorer R1 amended, new rules (Project view); layout R2 | `FileTreeStyle` / `NSOutlineView`, `ExplorerModel` levels | project detection over a fixture tree (types, nesting, exclusions) | M | 🟢 | `feat/m22` |

## Added on the way (2026-10-17, author)

- **History's actions** in a row of their own under the tabs, like Search and Problems (git R18 amended).
- **The search hang**: see 22.4.
- **A slot keeps its size** when its tabs are switched: the thickness is per slot again (layout R18 amended).
- **The left slot like Xcode's navigators**: its tabs show icon and title and share the width, the actions of Explorer and Project sit in a bar at the bottom of the panel (replaces 22.6's icon-only tabs; design R17). The Changes tab no longer carries its count.
- **Changes no longer widens the left slot**: the commit area's working-copy picker was as wide as its longest entry (a worktree's label) and pushed the whole panel past its slot, shifting the tabs; it truncates now.
- **Explorer before Project**; the Project bar holds New File, New Folder, Follow Active Tab and the refresh; the bars' buttons stay left-aligned (explorer R1, R25 amended).
- **No folder prompts during the tests**: the test host opens no workspace (product decision 2026-10-17).
- **The branch widget follows the active tab** (author, on `ccoe`): it names the working copy holding the active tab's file — a diff tab's repo, an editor tab's folder, an agent tab's cwd — and keeps it while a tab outside every repo is active; the commit target of R10 stays the fallback and the commit area's own choice (git R40 amended). A worktree shows its own branch now, not its main folder's. `GitModel.shownCopy`, `GitFeature.followTab`, `EditorFeature.url(of:)`; tested in `GitModelTests`.
- **Choosing the projects** (author, on `ccoe`): a `projects` key in `config.json` with the shape of `repos` — the declared folders as the bases of the scan, each read one level deep like a repo (the author's first try, `["ccoe-backend", "ccoe-frontend"]`, listed nothing while a declared folder had to hold the manifest itself), or `!` exclusions covering what lies under them — chooses the Project tab's projects, and Run reads its detected commands from that same list (explorer R24, run R14, `config.md`). `WorkspaceConfig.projects` / `ignoredProjects`, `WorkspaceProject.detect(root:repos:declared:ignored:)`, `RunCatalog.detect(root:folders:)`; the Project tab reloads on a config change.
- **The *Detected* heading of the ▶ menu was clickable**: it is a section header now (run R15).
- **The toolbar's background changed in full screen**: AppKit hosts it in a window of its own there; `WorkspaceToolbar.groundHostWindow` gives that window the same ground when an item lands in it — the full-screen notification fired before the move and left the bar at `#282828` instead of `#45474B` until the menu bar's first reveal, measured on the author's captures (design R14 amended). **By eye**: full screen, light and dark, the theme switched while in full screen.

## Decided with the author (2026-10-17)

- The Project view lists real projects by their manifest; unfolding one shows its files (author's answer to the plan).
- One branch `feat/m22`, one commit per task, pushed; the author merges.

## Where it stands

Done and merged into `main` on 2026-10-17, with the follow-ups listed under *Added on the way*. Planned on 2026-10-17. 22.1–22.7 done on `feat/m22`, installed and checked by capture; 22.1 done (the Run tab's mark); 22.2 the three worktree entries of the branch menu; 22.3 the tab bar's buttons; 22.4 search batched, then the real cause found by the author's test — the search hung on any output larger than a pipe (`FileHandle.bytes` for stdout and stderr), now read through `PipeIO`; 22.5 tabs fit their title; 22.6 panel tabs title the shown one only; 22.7 the Project tab (explorer R24, R25; a project named by its manifest's `artifactId` / `name`), and the Explorer's New File / New Folder moved into its menu; the icon-only tabs narrowed to the left slot (author, 2026-10-17).
