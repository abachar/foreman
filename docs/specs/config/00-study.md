# config — Study

## Goal

Define where and how Wraith reads its configuration and persists its state, per workspace.

## Locations

| Scope | Path | Content |
|---|---|---|
| Workspace | `<root>/.wraith/config.json` | workspace config (repos, commands, postgres, shortcuts…) |
| Workspace | `<root>/.wraith/state.json` | persisted UI state (splits, tabs, panels, sizes) |
| Secrets | macOS Keychain | Postgres passwords, never in a file |

## User stories

- US1 — I open a folder with no config at all: everything works with default values (auto-detected repos, no commands, no Postgres).
- US2 — I describe my workspace in `.wraith/config.json` (repos, commands, PG connection, agents) and the features use it.
- US3 — I edit `config.json` while Wraith is running: the config is reloaded without a restart.
- US4 — I can override a shortcut per workspace.
- US5 — I close and reopen the workspace: I find my state again.

## Functional rules

- R1 — `.wraith/` is created on demand (the first write of `state.json`), never `config.json`: that one is always written by the user.
- R2 — No `config.json` = empty config; every key is optional.
- R3 — Schema of `config.json` (v1):
  ```json
  {
    "repos": ["backend", "frontend"],
    "commands": { "backend": { "build": "mvn compile", "test": "mvn test" } },
    "postgres": { "host": "localhost", "port": 5432, "database": "ccoe", "user": "postgres" },
    "agents": { "claude": { "command": "claude --continue" } },
    "shortcuts": { "git.status": "cmd+shift+g" }
  }
  ```
  - `repos`: paths relative to the root; absent → scan for `.git/` (depth ≤ 2, ignoring `node_modules`, `target`, `.build`).
  - `commands`: `<repo or "."> → <name> → <shell command>`, run in the repo's folder.
  - `postgres`: **a single object** (one connection per workspace), without a password; the password is read from the Keychain (key `wraith.postgres.<host>:<port>/<database>/<user>`). Detail in [postgres](../postgres/).
  - `agents`: `<id> → { title, command, icon, enabled }`; overrides a built-in agent or declares a new one. Detail in [agents](../agents/).
  - `commands`: short form (a string) or long form (`{ "run", "cwd", "env" }`). Detail in [run](../run/).
  - `shortcuts`: `<panel/action id> → <shortcut>`; overrides the defaults declared by the features.
- R4 — Precedence: feature defaults < `.wraith/config.json`. There is no global configuration: everything is per workspace.
- R5 — `Workspace` exposes the config to the features; each feature decodes its own section (`config.section("postgres")`), `Workspace` does not know the features' schemas (`architecture`: config by section).
- R6 — `config.json` is watched (through the single FSEvents stream); on every valid change, `Workspace` publishes the new config on its `configChanges` stream (`AsyncStream`), which interested features subscribe to.
- R7 — An invalid `config.json` (malformed JSON, unexpected type) does not prevent opening: the last valid config stays active and the error is shown (line + message).
- R8 — `state.json` is written by Wraith only, debounced (~1 s after the last change) and on close. It is never watched.
- R9 — `state.json` carries a schema version number; an unreadable state or one with an unknown version is ignored (start from the default state) and saved as `state.json.bak`.
- R10 — Paths in `state.json` (terminal cwds, open files) are relative to the workspace root when they are inside it, absolute otherwise.
- R11 — No secret is ever written into `.wraith/`; any sensitive value detected in `config.json` (a `password` key) raises a warning and is ignored.

## Edge cases

- Read-only workspace root: `state.json` is not written, the app works without persistence and says so once.
- `$HOME` as the workspace: `~/.wraith/` is created in the user's home; acceptable (it is how a shell behaves with its dotfiles).
- `.wraith/` versioned or not: the user's choice; recommended `.gitignore` → `.wraith/state.json` and `.wraith/postgres-history.json` (every file written by the app).
- A repo declared in `repos` but missing on disk: ignored with a warning.

## Out of scope for v1

- Config in YAML/TOML, or across several files.
- A graphical preferences editor.
- Automatic schema migration between versions.
