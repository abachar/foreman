# terminal — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-26 | **SwiftTerm alone**; libghostty dropped (replaces "libghostty embedded" of 2026-08-25) | libghostty as the main path + SwiftTerm as a fallback; SwiftTerm as the main path + libghostty optional | The need is to show agent TUIs and build output, not to be a terminal emulator; SwiftTerm is enough, with no zig build and no vendored C |
| 2026-08-26 (afternoon) | **PTY and process through SwiftTerm's `LocalProcessTerminalView`**, used as designed; the exit code through `processTerminated`, the pid exposed for signals (replaces "a home-made `PTYSession`, `forkpty`" of 2026-08-26 morning) | A home-made PTY + `forkpty` + `waitpid`, SwiftTerm as pure VT | `architecture.md`: we do not write what a library already does; SwiftTerm provides the pid, the exit code and resizing |
| 2026-08-26 | One tab = **one process** launched through `$SHELL -l -c "<command>"`, with no prompt; process ended → a frozen surface + *Relaunch* | An interactive shell into which we `send()` the command; auto-close at the end | No free-form shell (`product` R4); the login shell's environment is preserved; the output stays readable after the end |
| 2026-08-26 | State from the end of the process (SwiftTerm), cwd = the launch cwd, **no shell integration** OSC 7/133 | Injecting shell integration | Reliable whatever the shell; nothing left to inject |
| 2026-08-26 | A fixed title provided by the feature; OSC 0/2 as a subtitle only | A dynamic title | The tabs are `Claude`, `backend:test`… identity wins |
| 2026-08-26 | Appearance (font, theme) handled by Wraith through `ThemeService` + the global config | The user's Ghostty config | No more Ghostty; a single theme for the whole UI |
| 2026-08-27 | The appearance override (R14) comes from the `terminal` section of `.wraith/config.json`, not from a global config | `~/.config/wraith/config.json` | Follows the config decision of 2026-08-26: a single source, per workspace |
| 2026-08-27 | **SwiftTerm `v1.20.0`**, `.upToNextMinor` | The `main` branch | The API we use is identical (`startProcess(...currentDirectory:)`, `processDelegate`, `bell`, `clearScrollback`, `installColors`); `main` rewrites `LocalProcess` with no gain for us; `architecture.md`: `.upToNextMinor` versions |
| 2026-08-25 | `cmd+w` asks for confirmation while the process is running; `SIGKILL` only on a forced close after 5 s | A direct kill; never a confirmation | Avoids killing a server or an agent by mistake |
| 2026-08-25 | Wraith's `cmd+…` shortcuts take priority over the surface | The surface wins | Tabs and splits are Wraith's |
| 2026-08-27 | Confirmed in use (M6 6.4): `bellStyle = .none` and R7's badge on an inactive tab, no visual bell | Going back to `.visual` | The badge is what the eye needs; a flashing surface under an agent is noise |
| 2026-08-27 | Confirmed in use (M6 6.2): `cmd+c` copies the selection, `ctrl+c` reaches the process; no agent needed `cmd+c` | Passing `cmd+c` to the process when there is no selection | No agent among the four used depends on it; one rule is easier to remember |
