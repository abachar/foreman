# config — Study

## Goal

Define where and how Foreman reads its configuration and persists its state, per workspace.

## Locations

| Scope | Path | Content |
|---|---|---|
| Global | `$XDG_CONFIG_HOME/foreman/config.json`, else `~/.config/foreman/config.json` | what is the same in every workspace (agents, shortcuts, theme, formatters…): the same schema as the workspace file, merged under it (R4, 2026-08-30) |
| Workspace | `<root>/.foreman/config.json` | workspace config (repos, commands, postgres, shortcuts…); every key, type and default in [`docs/config.md`](../../config.md) (2026-08-29) |
| Workspace | `<root>/.foreman/state.json` | persisted UI state (splits, tabs, panels, sizes) |
| Secrets | macOS Keychain, or `postgres.password` in `config.json` for a local dev database (decision 2026-08-27) | Postgres password |

## User stories

- US1 — I open a folder with no config at all: everything works with default values (auto-detected repos, no commands, no Postgres).
- US2 — I describe my workspace in `.foreman/config.json` (repos, commands, PG connection, agents) and the features use it.
- US3 — I edit `config.json` while Foreman is running: the config is reloaded without a restart.
- US4 — I can override a shortcut per workspace.
- US5 — I close and reopen the workspace: I find my state again.

## Functional rules

- R1 — `.foreman/` is created on demand (the first write of `state.json`), never `config.json`: that one is always written by the user.
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
  - `repos`: paths relative to the root; absent → scan for `.git/` (depth ≤ 2, ignoring `node_modules`, `target`, `.build`, `DerivedData`).
  - `commands`: `<repo or "."> → <name> → <shell command>`, run in the repo's folder.
  - `postgres`: **a single object** (one connection per workspace); the password is read from the Keychain (key `foreman.postgres.<host>:<port>/<database>/<user>`) unless the section carries a `password` (decision 2026-08-27). Detail in [postgres](../postgres/).
  - `agents`: `<id> → { title, command, icon, enabled }`; overrides a built-in agent or declares a new one. Detail in [agents](../agents/).
  - `commands`: short form (a string) or long form (`{ "run", "cwd", "env" }`). Detail in [run](../run/).
  - `shortcuts`: `<panel/action id> → <shortcut>`; overrides the defaults declared by the features.
- R4 — **Amended 2026-08-30** (from use; reinstates the global config and the merge of 2026-08-26, cancelled the same day). Precedence: feature defaults < global file < `<root>/.foreman/config.json`. The merge is **one level deep**: a section that is an object in both files is merged key by key and the workspace's key wins; any other value (a string, a number, an array such as `repos`) is replaced whole. So a workspace overrides one agent or one shortcut without copying the globals, and no deep recursive merge is needed. Both files are optional (R2), both are watched and reloaded live (R6), both are treated the same when invalid (R7): the last valid version of *that* file stays and the error names it. Every section is merged the same way — nothing in the code knows that `repos` or `postgres` make no sense globally.
- R5 — `Workspace` exposes the config to the features; each feature decodes its own section (`config.section("postgres")`), `Workspace` does not know the features' schemas (`architecture`: config by section).
- R6 — `config.json` is watched (through the single FSEvents stream); on every valid change, `Workspace` publishes the new config on its `configChanges` stream (`AsyncStream`), which interested features subscribe to.
- R7 — An invalid `config.json` (malformed JSON, unexpected type) does not prevent opening: the last valid config stays active and the error is shown (line + message).
- R8b — `.foreman/postgres-history.json` (`postgres` R20) follows the same rules as `state.json`: written by Foreman only, atomically, versioned, `.bak` when unreadable; both belong in `.gitignore`.
- R8 — `state.json` is written by Foreman only, debounced (~1 s after the last change) and on close. It is never watched.
- R9 — `state.json` carries a schema version number; an unreadable state or one with an unknown version is ignored (start from the default state) and saved as `state.json.bak`.
- R10 — Paths in `state.json` (terminal cwds, open files) are relative to the workspace root when they are inside it, absolute otherwise.
- R11 — Foreman never writes a secret into `.foreman/`. The user may write `postgres.password` in `config.json` (a local dev convenience, decision 2026-08-27): it is used as is, never logged and never copied to the Keychain; `config.json` is then to be kept out of version control.

## Edge cases

- Read-only workspace root: `state.json` is not written, the app works without persistence and says so once.
- `$HOME` as the workspace: `~/.foreman/` is created in the user's home; acceptable (it is how a shell behaves with its dotfiles).
- `.foreman/` versioned or not: the user's choice; recommended `.gitignore` → `.foreman/state.json` and `.foreman/postgres-history.json` (every file written by the app).
- A repo declared in `repos` but missing on disk: ignored with a warning.

## Out of scope for v1

- Config in YAML/TOML, or spread over more files than the two of R4.
- A graphical preferences editor.
- Automatic schema migration between versions.
