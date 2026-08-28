# agents — Study

## Goal

Feature `agents`: launch and come back to the **CLI agents** (Claude Code, Antigravity CLI, OpenCode…) in a terminal tab dedicated to each agent, with one click on a toolbar button (`layout` R30). Built-in agents are known to Foreman and shown when they are installed; `config.agents` adds to them or overrides them.

This is **not** `run`: a `run` command is defined by the user and lives in the palette; an agent is a tool Foreman knows, with its button, its icon and its reused tab.

## User stories

- US1 — I open a workspace: the buttons of the agents installed on my machine appear in the toolbar, nothing to configure.
- US2 — I click "Claude": a `Claude` tab opens at the workspace root and launches `claude`. I click again: the existing tab is activated, no duplicate.
- US3 — Right-click on the button: "New session" or "Launch in `backend`" to choose the repo.
- US4 — I can tell at a glance whether the agent is running or waiting (a badge on the button and on the tab).
- US5 — I add my own agent or change `claude`'s options in `config.json`: the button follows without a restart.

## Functional rules

### Built-in agents and detection

- R1 — Built-in agents (id, title, binary, default command):

  | id | Title | Binary | Command |
  |---|---|---|---|
  | `claude` | Claude Code | `claude` | `claude` |
  | `antigravity` | Antigravity | `agy` (verified 2026-08-27) | `agy` |
  | `opencode` | OpenCode | `opencode` | `opencode` |
  | `pi` | Pi | `pi` | `pi` |

- R2 — A built-in agent is **shown** when its binary is found in the `PATH` of the login shell's environment (the same one the terminals use, `terminal` R3, resolved once by `Workspace`). Not found → no button, no message. Detection is redone on every `Workspace.configChanges` and when the window opens, never by polling.
- R3 — `config.agents` (`config` R3): `{ "<id>": { "title"?, "command"?, "icon"?, "enabled"? } }`. A built-in id overrides its fields (e.g. `"claude": { "command": "claude --continue" }`); an unknown id declares a custom agent (`command` mandatory, always shown, no detection); `"enabled": false` hides a built-in one. Precedence: `config` R4. Id: `[a-z0-9][a-z0-9_-]*`. `icon`: an SF Symbol name, the name of a built-in logo (`agent-claude`, `agent-antigravity`, `agent-opencode`, `agent-pi`; checked 2026-08-28), or the path of an SVG/PNG file relative to the workspace root (rendered monochrome like a symbol; outside the root → ignored). The built-in ones have their SVG logo in the asset catalog (`agent-<id>`, 2026-08-27).

### Launching and the tab

- R4 — Clicking the button: if an `agent.<id>` tab exists in the window → it is activated (and its group takes the focus); otherwise → `TerminalService.spawn(command:, cwd: root, kind: "agent.<id>", title:)` in the active group (`terminal` R16): the process starts immediately, without a shell. **One tab per agent per window** in normal use.
- R5 — Button menu (right-click or long click): *New session* (forces a new `agent.<id>` tab, not reused afterwards: only the first tab created is the button's one), *Launch in …* for each repo in `config.repos`/auto-detection (cwd = the repo). The command is passed as is (`architecture.md`, security), with no `env` and no templating.
- R6 — The state is the terminal tab's (`terminal` R6): `idle` / `running` / `exited(code)`. Badge: a dot on the button and on the tab while `running`; the bell of an inactive agent tab marks the tab (`terminal` R7) and the button. Agent exited (`exited`): the surface stays frozen with *Relaunch* (`terminal` R8); clicking the agent's button relaunches in that same tab.
- R7 — Closing: `terminal` R10–R11 (a confirmation while the agent is running; a clean stop).
- R8 — Restoration (`layout` R28): the tab is recreated in the `idle` state at the same cwd, the title kept, an empty surface with *Relaunch*; the command is **not** relaunched automatically (the same choice as `run` R13); no `resume` option (confirmed in use, decision 2026-08-27).
- R9 — Shortcuts: `config.shortcuts["agents.<id>"]`, no default. Global scope. `cmd+opt+t` hides the toolbar (`layout` R32); the shortcuts stay active.

## Edge cases

- Binary present but the command fails (version, login required): the error appears in the surface, the state is `exited(code)`, no banner.
- Two windows: one tab per agent **per window**, independent.
- The user quits the agent (`/exit`): `exited(0)`, a frozen surface; the agent's button relaunches in the same tab.
- An agent that launches sub-processes: they are in the PTY's process group and follow the tab (`terminal` R9, R11).
- A `PATH` without the binary but with a shell alias/function: not detected; declare the agent in `config.agents` (no detection for a declared agent).

## Out of scope for v1

- Deep integration: sending a path or a selection to the agent, automatically opening the diff of the files it modifies, reading its state other than through the terminal. (v2 candidates; the git diff and the explorer already refresh through FSEvents.)
- MCP, APIs, hooks, named sessions, session history.
- Non-CLI agents (extensions, apps).

## Technical options

- **Folder**: `Agents/` (`architecture.md`). `AgentsFeature` declares to `Layout` one toolbar item per agent (on the `leading` side, `layout` R30) and a tab kind `agent.<id>` whose payload is `{ "id", "cwd" }`; the tab's view is `TerminalService`'s terminal surface (the `run` tab does the same, `run` R7).
- **Detection**: `Workspace` exposes the login shell's environment (PATH); the executable is looked up by simply walking the PATH entries (`FileManager.isExecutableFile`), off the main actor. No shell is launched to detect.
- **Icons**: `Layout/IconImage` resolves an SF Symbol name, an asset name (`agent-<id>`, an SVG template) or an absolute path to an SVG/PNG file (`NSImage(contentsOfFile:)`, `isTemplate`); `AgentsFeature` makes a relative path under the root absolute.
- **Tests**: parsing/merging `config.agents` with the built-ins (R3), PATH resolution over a temporary folder (R2), the button/tab state machine (R4, R6, R8) driven by simulated terminal events.

## Decisions

See [decisions.md](decisions.md).

Later studies: [`01-study-send.md`](01-study-send.md) (R10–R11, send to the active agent), [`02-study-worktrees.md`](02-study-worktrees.md) (R12–R13, worktrees).
