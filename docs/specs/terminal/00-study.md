# terminal — Study

## Goal

Provide the **terminal surface** that hosts the tabs of the `agents` and `run` features: a pseudo-terminal (PTY), a **process** launched inside it (the agent or the command), VT emulation and rendering by SwiftTerm, a lifecycle (running → exited), events (process output, bell, title) and the `TerminalService` type (shared `Terminal/` folder) used by the features.

**This is not a user-facing tab kind** (`product` R4) and **it is not a shell**: no `cmd+t`, no "new terminal", no prompt. One terminal tab = one process; when it ends, the surface freezes with its exit code. The user interacts with the process (agents are full-screen TUIs: typing, colors, mouse, resizing), never with a shell.

## Why SwiftTerm and not libghostty

The need changed: we are not emulating a terminal for the user, we are showing TUIs (Ink, Bubbletea…) and build output. SwiftTerm (pure Swift, SPM, built-in PTY, full VT/xterm, 24-bit, mouse, used by heavy TUIs) covers that with no zig build, no vendored C, no unstable API. libghostty (Metal rendering, shell integration, Ghostty config) brings nothing to the product and was the riskiest milestone. Decision: **SwiftTerm alone**, used as it is designed (`LocalProcessTerminalView`: PTY + process + view), with no fallback planned (`architecture.md`, "use the libraries").

## User stories

- US1 — I click an agent or launch a run: the surface appears in < 100 ms and the process starts with my usual environment (PATH, login shell variables).
- US2 — The agent (a full-screen TUI) works as it does in Terminal: typing, colors, mouse, resizing, copy/paste.
- US3 — An inactive tab shows me that the process rang the bell or ended (and how: the exit code).
- US4 — I close a tab whose process is running: a confirmation appears; the process is stopped cleanly.
- US5 — A feature can launch a command in a folder, know its state (running / exit code) and send it a signal.
- US6 — When the workspace reopens, my agent/run tabs are recreated at the same cwd, ready to be relaunched (`product` R7).

## Functional rules

### Process and environment

- R1 — A terminal tab runs **one command** provided by the owning feature, through `$SHELL -l -c "<command>"` (the user's `$SHELL`, otherwise `/bin/zsh`): the login shell loads the user's environment (PATH, profiles) then runs the command; there is **no prompt**, the shell ends with the command. The command is the text provided as is (`architecture.md`, security), never recomposed by Wraith.
- R2 — cwd: provided by the feature (`agents`: the root or a repo; `run`: the repo folder / `cwd`), necessarily under the root or an explicit absolute path. The cwd is the one used at launch; it is persisted (`config` R10) and used for restoration.
- R3 — Environment: the login shell's, enriched with `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=wraith`, `WRAITH_WORKSPACE=<root>`, plus the `env` provided by the feature (`run` R8). No variable from `config.json` is injected by default.
- R4 — No shell integration (OSC 7/133): useless, Wraith launches the process. The state comes from the end of the process (R6), the cwd is known (R2).

### State, title and signals

- R5 — Tab title: **fixed**, provided by the feature (`Claude`, `backend:test`). A title pushed by the process (OSC 0/2) is exposed as a subtitle/tooltip, never in its place.
- R6 — A tab's state: `idle` (created or restored, not launched yet) → `running` (a live process, pid known) → `exited(code)` (an exit code or a signal, reported by SwiftTerm when the process ends). Exposed by `TerminalService` and published as events; it is the only source of state for `agents` R6 and `run` R10.
- R7 — An **inactive** tab is marked (a badge) when: the bell rings, or its process ends. The marker disappears when the tab is activated. No system notification in v1.
- R8 — Process ended: the surface stays visible, frozen, with a status line at the bottom (`finished · code 0` / `code 1` / `signal SIGINT`) and a *Relaunch* button (same command, same cwd, a new PTY in the same tab). The tab never closes on its own.
- R9 — Signals: `signal(SIGINT|SIGTERM, to: tab)` sent to the PTY's **process group**. `SIGKILL` is never automatic.

### Closing

- R10 — A close request (`cmd+w`, group, window): if `running` → a confirmation (`layout` R15, the tab counts as "dirty" for that purpose); otherwise it closes immediately.
- R11 — Closing sends `SIGHUP` to the process group, releases the view (which closes the PTY), waits for the process to end (5 s max then `SIGKILL` **only in this forced-close case**); no descriptor and no zombie survives the tab.

### Input, mouse, appearance

- R12 — Keyboard: `layout` R25 — everything that is not a Wraith `cmd+…` shortcut goes to the process (including `ctrl+c`, `ctrl+d`, arrows, `esc`). `cmd+c`/`cmd+v` copy/paste (SwiftTerm's selection), `cmd+k` clears the scrollback, `cmd+=`/`cmd+-` zoom the font (scope `tab(terminal)`).
- R13 — Mouse: selection, copy, scrolling, forwarding mouse events to the TUIs that ask for them — all delegated to SwiftTerm. Detected links are clickable (`cmd+click`).
- R14 — Appearance: the monospaced font and the theme are defined by Wraith (`ThemeService`); the `terminal` section of `.wraith/config.json` (`font`, `fontSize`, `theme`) overrides them (the local config only, config decision 2026-08-26). Scrollback: 10,000 lines.
- R15 — Resizing: the surface receives its size in points from the layout (`layout` R21); SwiftTerm derives rows/columns from it and propagates the window size to the process.

### Service for the features (`Terminal/`)

- R16 — `TerminalService` (a concrete type in the shared `Terminal/` folder, injected into the features): `spawn(command:, cwd:, env:, kind:, title:) -> TabID` (creates the tab and launches), `relaunch(TabID)`, `signal(_:to:)`, `write(_ bytes:, to:)` (raw input, rarely useful), `state(of:) -> TerminalState`, `pid(of:)`, and an `events` stream (`started(tab, pid)`, `exited(tab, code)`, `bell(tab)`, `activated(tab)` — R7's marker cleared —, `closed(tab)`) as an `AsyncStream`, one per consumer (2026-08-27). The `kind` is the calling feature's (`agent.<id>`, `run.<id>`); there is no `terminal` kind.
- R17 — A feature can only act on the tabs of the current window; an unknown or closed `TabID` → `TerminalError.noSuchTab`.
- R18 — Several surfaces coexist without limit; each one has its own PTY and process. An `exited` or inactive surface consumes no CPU (`architecture.md`, performance).

## Edge cases

- `$SHELL` missing or not executable: fall back to `/bin/zsh`, with a message in the surface.
- Command not found (`command not found`): the shell exits with 127 → `exited(127)`, visible in the surface; no Wraith banner.
- The persisted cwd is gone at restoration: an `idle` tab with a "folder not found" banner, *Relaunch* disabled until it is fixed.
- A process that ignores `SIGINT`/`SIGTERM`: R11 (forced close only); otherwise it keeps running and the user sees `running`.
- Massive output (a verbose build): SwiftTerm reads and renders in batches; the scrollback is bounded (R14).
- A process that launches sub-processes (a server, `npm start`): they are in the PTY's process group and receive the R9/R11 signals.

## Out of scope for v1

- An **interactive shell** (`cmd+t`, "new terminal", "terminal here", a prompt): deliberately absent (`product` R4).
- libghostty, Metal rendering, Ghostty config, shell integration (OSC 7/133).
- Restoring the scrollback (`product`), tmux-style persistent sessions.
- System notifications, per-workspace profiles.

## Technical options

- **Dependency**: `SwiftTerm` (SPM, `.upToNextMinor`), imported in `Terminal/`. We use `LocalProcessTerminalView` **as it is designed**: it opens the PTY, launches the process (`startProcess(executable: $SHELL, args: ["-l", "-c", command], environment:, currentDirectory: cwd)` (checked on SwiftTerm 1.20.0, 2026-08-27)), renders the output, forwards the input, propagates resizing, and reports the end through `LocalProcessTerminalViewDelegate.processTerminated(source:exitCode:)`. No home-made PTY and no `forkpty`.
- **View**: `LocalProcessTerminalView` (AppKit) inside an `NSViewRepresentable`; a `TerminalTab` (`@MainActor @Observable`) per tab carries the R6 state, the pid (`process.shellPid`), the title and the badge. Signals (R9, R11): `killpg(pid, SIGINT|SIGTERM|SIGHUP)` on the process group, then `SIGKILL` after 5 s on a forced close only. *Relaunch* (R8) = a new view/new process in the same tab.
- **Events**: the SwiftTerm delegate's callbacks (`processTerminated`, `setTerminalTitle`, bell) are converted into an `AsyncStream<TerminalEvent>` by `TerminalService`.
- **Tests**: state logic (R6: idle → running → exited transitions), badge (R7), close confirmation (R10) and relaunch (R8) on a `TerminalTab` driven by simulated events; no test of SwiftTerm itself.

## Decisions

See [decisions.md](decisions.md).
