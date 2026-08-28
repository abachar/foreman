# run — Study

## Goal

Feature `run`: launch the commands declared in `config.json` (`commands`) on a workspace terminal surface, from a palette (`cmd+r`) or the **▶ Run** toolbar button, with one terminal tab reused per command and a state indicator. No panel. No automatic detection, no composition: the config is the only source. CLI agents are not `run` commands: see [agents](../agents/).

## User stories

- US1 — `cmd+r`, I type `bt`, `backend › test` comes up, `enter`: a `backend:test` tab opens in the repo's folder and launches `mvn test`.
- US1b — I click ▶ in the toolbar: the list of commands per repo appears with their state; a click launches one.
- US2 — I relaunch the same command: the same tab is reused (the running process is stopped first).
- US3 — An inactive command tab shows me whether it is running, whether it succeeded or failed.
- US4 — `cmd+.` in a command's tab stops the process cleanly.
- US5 — I edit `config.json`: the palette reflects the new list immediately.

## Functional rules

### Config

- R1 — The `commands` section (`config` R3): `{ "<repo or .>": { "<name>": "<command>" | { "run": "<command>", "cwd": "<subfolder>", "env": { "K": "V" } } } }`. The short form is a string; the long form adds `cwd` (relative to the repo, defaulting to the repo) and `env`. An `env` at the repo level (the reserved key `"$env"`) applies to all of its commands.
- R2 — The `<repo>` must be `.` (alias `root`, the spelling of the id, accepted as long as no `root/` folder exists — decision 2026-08-27) or a path relative to the root that exists on disk (not necessarily a git repo). Missing: the command is listed greyed out with the reason. `cwd` must stay under the root (`architecture.md`, security).
- R3 — A command's name: `[a-z0-9][a-z0-9:_-]*`, unique per repo. Full identifier `repo:name` (`.` becomes `root`). These ids are used by the shortcuts (`config.shortcuts["run.backend:test"]`, R11).
- R3b — A single source: the workspace's `.wraith/config.json` (`config` R4, config decision 2026-08-26: no global configuration). Two workspaces share nothing.
- R4 — Hot reload on `Workspace.configChanges` (`config` R6): the palette and the shortcuts are recomputed; a running tab is not affected.

### Palette and button

- R5 — `cmd+r` opens a palette (`Palette`, the shared folder, the same one as quick open). Entries `repo › name` with the command as the subtitle; fuzzy over `repo name`; default order: most recently launched first, then alphabetical.
- R6 — `enter` launches (R7); `cmd+enter` launches in a **new** tab (without reuse); `opt+enter` copies the command to the clipboard. `escape` closes.
- R6b — The **▶ Run** button (`run.toolbar`, a toolbar item declared to `Layout`, on the `trailing` side, of the menu kind, `layout` R30): the menu lists the commands grouped by repo, with the command as the subtitle and the state badge (R10) of the matching tab; a click launches (R7). The button carries a blue badge when at least one command is running, red when the last one to finish failed (cleared when the tab is activated). With no command configured at all, the menu shows a config example. Neither `commands` nor the button are touched by the agents.

### Execution

- R7 — Launching `repo:name`: if a `run.<id>` tab exists → it is activated; if it is `running`, the process receives `SIGINT` (R9) and, after `exited`, `TerminalService.relaunch`; if it is `idle`/`exited`, `relaunch` directly. Otherwise → `TerminalService.spawn(command:, cwd:, env:, kind: "run.<id>", title: "repo:name")` (`terminal` R16): the process starts immediately, with no shell and no prompt.
- R8 — The command is passed **as is** to `$SHELL -l -c` (`terminal` R1); the `env` values are injected into the process's environment (`terminal` R3), never prefixed onto the command line. Nothing is recomposed (`architecture.md`, security): the command is the user's text.
- R9 — Stopping: `cmd+.` (scope `terminal`, no effect outside a `run.*` tab, decision 2026-08-27) sends `SIGINT` to the process group (`terminal` R9); a second `cmd+.` within 2 s sends `SIGTERM`; never an automatic `SIGKILL`. Relaunching (R7) = stop then wait for `exited` (10 s max, then give up with a log: the tab stays `running` and the user sees that the process did not yield) before `relaunch`.
- R10 — State per `run` tab: `idle` / `running` / `succeeded` / `failed(code)`, derived from `terminal` R6 (`exited(0)` → `succeeded`, otherwise `failed`). Badge on the tab: a blue dot (running), green (0), red (≠ 0); cleared when the tab is activated after it ends, or on relaunch.
- R11 — A shortcut per command: `config.shortcuts["run.<id>"]` (`config` R3); no default. Global scope.
- R12 — Closing a `run` tab that is `running`: a confirmation (`terminal` R10). Closing the window: the same, one confirmation per tab.
- R13 — `run` tabs are restored (`layout` R28) in the `idle` state at the same cwd, the title kept, an empty surface with *Relaunch*; the command is **not** relaunched.

## Edge cases

- A command that launches an interactive shell or a TUI: works (it is a terminal surface); relaunching goes through `SIGINT` then `relaunch`, never through sent text.
- `commands` contains an `env` with a secret: `config` R11 (the `password` key) applies; other keys are accepted — it is the user's choice.
- Two workspaces declaring the same command: independent (tabs are per window).
- A command name clashing with a reserved key (`$env`): ignored with a warning in the palette.

## Out of scope for v1

- Automatic detection (`package.json`, `Makefile`, `pom.xml`).
- Sequences, dependencies, parallel commands, background tasks without a terminal.
- A dedicated panel; commands in the app menu.
- Capturing/parsing the output (problems, links to compilation errors).
- Variables/templating in the commands (`${file}`, `${branch}`).

## Technical options

- **Folder**: `Run/` (`architecture.md`). `RunFeature` declares the `run.toolbar` toolbar item and the `run.<id>` tab kind to `Layout`.
- **Shared palette**: `Palette/` (the shared folder, shipped in M1): `Palette.present(PaletteSource, over: NSWindow)`; `PaletteSource(placeholder:, results: (String) async -> Results, select: (PaletteItem, newGroup: Bool) -> Void, secondary: ((PaletteItem) -> Void)?)` — `newGroup` = `cmd+enter` (a new tab, R6), `secondary` = `opt+enter` (copy, R6; added in M3); items `PaletteItem(id:, title: AttributedString, subtitle:)`; fuzzy through **FuzzyMatch** (`FuzzyMatcher.topMatches`), the same one as quick open (`editor` R17).
- **Signals / state**: `TerminalService.signal(_:to:)`, `state(of:)`, `exited` events (`terminal` R16); `relaunch` refuses a `running` tab: the R7 relaunch (stop, wait for `exited`, `relaunch`) lives in `Run/`. Tab badge: `Run/` sets its own (blue/green/red, R10) on every event of its tabs, after `TerminalService`'s one (`terminal` R7); `ToolbarBadge.BadgeColor` gains `blue`.
- **Tests**: parsing/validating `commands` (R1–R3), building the environment (R8), the `run` tab state machine (R7, R9, R10) driven by simulated terminal events.

## Decisions

See [decisions.md](decisions.md).

Later study: [`01-study-detected.md`](01-study-detected.md) (R14–R16, detected commands).
