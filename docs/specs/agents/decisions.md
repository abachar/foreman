# agents — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-26 | The `agents` domain is distinct from `run`: dedicated buttons in the toolbar | Agents declared as `run` commands | A run is defined by the user; an agent is a tool Wraith knows, with a button, an icon and a reused tab |
| 2026-08-26 | Built-in agents (Claude Code, Antigravity, OpenCode) detected in the PATH + `config.agents` to add/override/hide | Config only; a fixed list without config | Zero config in the common case, extensible for a custom agent or for options |
| 2026-08-26 | One tab per agent, reused: the button activates the existing tab, otherwise it creates it; "New session" through the menu | A new tab on every click; a folder chooser before every launch | Avoids duplicates; the rare case has its menu entry |
| 2026-08-26 | The agent lives on a terminal surface (the only use of the terminal along with `run`, `product` R4); state derived from the end of the process (`terminal` R6); no deep integration in v1 | An agent ↔ workspace bridge (selection, automatic diff) | Ship the launching first; the explorer and git already refresh through FSEvents |
| 2026-08-26 | Restoration without relaunching the command | Automatic relaunch | The same rule as `run` R13; an implicit relaunch can burn sessions/tokens |
| 2026-08-27 | R8 confirmed in use (M6 6.4): `idle` restoration, no per-agent `resume: true` | An automatic `claude --continue` at restoration | Relaunching by hand is one click and never burns a session by surprise; nobody missed it in M2–M5 |
| 2026-08-27 | R9 confirmed: no default shortcut for any agent, `config.shortcuts["agents.<id>"]` only | `cmd+shift+a` for the first agent of the config | Reserving a `cmd+shift+<letter>` for one agent out of five is arbitrary; the toolbar button is one click and the home screen shows the (absent) shortcut |
| 2026-08-27 | The login shell's environment is resolved **once per window** (`$SHELL -l -c '/usr/bin/env -0'`, off the main actor, `Workspace.loginEnvironment()`); R2's detection walks the resulting `PATH` without launching any other process | One shell per agent; reading `ProcessInfo` only (the app's PATH, incomplete) | R2 asks for the login shell's PATH without polling; a single process at first need, reused on every `configChanges` |
