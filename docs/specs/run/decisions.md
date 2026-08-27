# run — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-27 | `"root"` accepted as an alias for `"."` in `commands` | `.` alone | The id reads `root:name`, and the author instinctively wrote `root`; zero cost |
| 2026-08-27 | R3b: a single source of commands, `.wraith/config.json` | Global/workspace precedence | The global config was removed (config, 2026-08-26) |
| 2026-08-27 | `cmd+.` (`run.stop`) with the `terminal` scope, a no-op outside a `run.*` tab | One `tab(kind: "run.<id>")` action per command | One action, one shortcut row; `ShortcutRegistry` has no unregistration |
| 2026-08-27 | Relaunching a `running` tab (R7) orchestrated in `Run/` (`SIGINT`, wait 10 s for `exited`, `relaunch`); `TerminalService` unchanged | A `relaunch` that stops the process itself | M2: `run` reuses `TerminalService` as is; the wait is a need of `run` alone |
| 2026-08-27 | The R10 tab badge is set by `Run/` on top of `TerminalService`'s one; `blue` added to `ToolbarBadge` | Configurable colors inside `TerminalService` | One line in `Layout/` against an abstraction for two callers |
| 2026-08-27 | "Most recently launched first" (R5): an in-memory list per window | A field in `state.json` | No format migration for a convenience; to be revisited in use |
| 2026-08-27 | A command removed from the config: its open tabs stay, a persisted tab is not restored (unregistered kind); its `run.<id>` shortcut stays registered and does nothing | The command inside the tab's payload | The same policy as `agents`; the layout already ignores an unknown kind |
| 2026-08-26 | The `cmd+r` palette **and** a ▶ Run button (menu) in the toolbar; no panel | The palette alone (decision of 2026-08-25); a panel of buttons | One click for the daily case, the palette for the keyboard; a panel would cost a slot |
| 2026-08-26 | CLI agents are not `run` commands | Declaring `claude` in `commands` | A run is defined by the user; an agent is known to Wraith (`agents`) |
| 2026-08-25 | One terminal tab per command (`repo:name`), reused; relaunch = `ctrl+c` then resend; `cmd+enter` forces a new tab | A new tab every time | Avoids piling up; the "I want to keep the old one" case has its shortcut |
| 2026-08-25 | Config only: no automatic detection, no sequences and no dependencies | `package.json`/`Makefile` detection; `"deploy": ["build","test"]` | Explicit and predictable; `a && b` covers sequences |
| 2026-08-26 | `env` per command or per repo, injected into the process's environment (replaces "`K=V` prefixed onto the command" of 2026-08-25); the command itself is never modified | A `K=V` prefix on the line; templating | Wraith launches the process (`terminal` R3): there is nothing left to escape |
| 2026-08-26 | The running/exit-code state derived from the end of the process (`terminal` R6) (replaces "OSC 133" of 2026-08-25) | Shell integration; a process outside the terminal | Wraith launches the process: reliable whatever the shell; the login shell's environment is preserved by `$SHELL -l -c` |
| 2026-08-25 | Stopping: `cmd+.` → `SIGINT`, a second press → `SIGTERM`; never an automatic `SIGKILL` | A direct kill | Let the process stop cleanly (servers, databases) |
| 2026-08-25 | The palette (fuzzy + UI) is a shared folder (`Palette/`), common to quick open and `run` | A component duplicated in each feature | `architecture.md`: what two features need lives in a shared folder |
