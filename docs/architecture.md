# Architecture

> How Foreman is put together: principles, structure, retained dependencies, architecture rules. The *what* is in [`specs/`](specs/), the code style in [`coding-rules.md`](coding-rules.md). This file changes when an architecture decision changes; every change is dated in the `decisions.md` of the domain concerned.

## Principles

- **P1 — The simplest thing that works.** One user, no backward compatibility, no third-party plugins. We write the code for today's need; we abstract when there are **two** real implementations, not before. No protocol, adapter or double "just in case".
- **P2 — Use the libraries.** If a maintained library does the job, we use it directly, the way it is meant to be used. Rewriting what a library does is a mistake, not caution.
- **P3 — Use the platform.** AppKit/SwiftUI/Foundation first (`NSToolbar`, `NSSplitView`, `NSOutlineView`, `NSTextView`, `FileManager`, `Process`). We do not reimplement one because it does not do *exactly* what we imagine; we adapt the need.
- **P4 — Lazy by default.** No work (connection, scan, tree read) before a panel or a tab is actually used; a hidden panel costs nothing.
- **P5 — Nothing breaks opening a workspace.** Invalid config, missing repo, unreadable state: degradation announced in the UI, never a crash or a blank screen.

## Overview

One window = one folder = one workspace. In the center, tab groups in a split tree; around it, three panel slots (left, right, bottom), one visible panel per slot; above, a native toolbar. There is no free-form shell: a terminal surface only exists to host an agent or a `run` command.

```
│ [Claude] [OpenCode]      TOOLBAR              [▶ Run] │
┌──────────┬──────────────────────────────────┬──────────┐
│  LEFT    │        CENTER (splits →          │  RIGHT   │
│  panel   │        tab groups)               │  panel   │
│          ├──────────────────────────────────┤          │
│          │           BOTTOM panel           │          │
└──────────┴──────────────────────────────────┴──────────┘
```

| Feature | Surfaces | Default shortcut |
|---|---|---|
| Explorer | left panel: file tree | `cmd+shift+e` |
| Editor | center tabs: file / markdown; bottom panel: content search | `cmd+p` quick open, `cmd+shift+f` |
| Agents | toolbar buttons; one terminal tab per agent | `config.shortcuts["agents.<id>"]` |
| Run | ▶ Run button + palette; one terminal tab per command | `cmd+r` |
| Git | right panel: changes, history (one at a time); center tab: diff | `cmd+shift+g` / `cmd+shift+h` |
| Postgres | right panel: schema; center tabs: query + results | `cmd+shift+b` / `cmd+shift+q` |
| Browser | one center tab: the page of `config.browser.url` (`WKWebView`, private session) | `cmd+shift+o` |

Full shortcut table and their state: [`shortcuts.md`](shortcuts.md).

## Structure

One Xcode project (SwiftUI macOS app, without App Sandbox: we read the whole disk and launch processes), one app target, one test target, one folder per feature. No internal framework, no "plugin" targets, no dynamic loading.

```
Foreman.xcodeproj
Foreman/
├── App/          # entry point, windows, menus, ThemeService
├── Workspace/    # config.json, state.json, FSWatch, Keychain
├── Layout/       # splits, tab groups, PanelManager, ShortcutRegistry, toolbar, home screen
├── Palette/      # shared fuzzy palette (quick open, run)
├── Highlight/    # tree-sitter → attributes, shared (editor, diff, sql)
├── Terminal/     # SwiftTerm surface + process, TerminalService
├── Explorer/  Editor/  Agents/  Run/  Git/  Postgres/  Browser/
ForemanTests/         # same split
cli/foreman           # shell script: `open -a Foreman "$(pwd)"`
```

- Direction of dependencies, by convention: `App` → features → shared folders (`Layout`, `Palette`, `Highlight`, `Terminal`, `Workspace`). A feature may call another feature directly (`Git` calls `Editor.open(path)`); we avoid cycles, that's all.
- A feature = one folder with an entry point (`GitFeature.swift`) that registers its panels, tabs, toolbar items and shortcuts with `Layout` at startup.
- Adding a feature: one folder here, one line in [`specs/README.md`](specs/README.md).

## Architecture rules

- **Features do not drive the layout.** A feature *declares* (panel, slot, shortcut, `makeView`); `PanelManager` decides what is visible.
- **`makeView` is lazy** and side-effect free; work starts when the panel is activated and stops when it is deactivated (P4). What `activate()` starts, `deactivate()` stops.
- **Shared services, created once in `App` and injected**: `FSWatchService` (one FSEvents stream, multiplexed, ~300 ms debounce), `ThemeService`, `SecretStore`, `TerminalService`, `Palette`, `Highlight`. No `static let shared`. No disk polling.
- **No `EventBus`.** A notification between features is a closure or an `AsyncStream` exposed by the owner of the information (`Git` exposes `statusChanges`, `Explorer` subscribes to it).
- **Config by section**: each feature decodes its own section of `.foreman/config.json`; `Workspace` does not know the schemas. Every key is listed in [`config.md`](config.md).
- **Namespaced, stable identifiers** (`git.status`, `agent.claude`): they appear in `state.json` and in shortcuts; changing one is a migration.
- **Third-party types stay near their use.** A view or a persisted model never handles a `PostgresRow` or a tree-sitter `Node`; the feature converts to its own type where the UI or persistence needs it — and only there.
- **Persisted formats are versioned**; unknown version → ignored + `.bak`. One single disk exclusion list (`.git/objects`, `node_modules`, `target`, `.build`, `DerivedData`, `.foreman/state.json`).

## Retained dependencies

We import where we use. Versions `.upToNextMinor`, `Package.resolved` committed, updating = a dedicated commit.

| Need | Library | Note |
|---|---|---|
| Terminal surface + process | **SwiftTerm** | `LocalProcessTerminalView`: PTY, process, view, exit code through `processTerminated` |
| Git | `git` binary through `Process` | machine formats (`--porcelain=v2 -z`, `--format`); honours hooks, signing, helpers |
| Postgres | **PostgresNIO** | schema through `pg_catalog` |
| Highlighting | **SwiftTreeSitter + Neon** (ChimeHQ, `main` branch, editor decision 2026-08-26), 15 SPM grammars (`tree-sitter-*`; `sql` on tree-sitter-sql's `gh-pages` branch, editor decision 2026-08-28) | editor, git diff, Postgres query editor |
| Markdown | **swift-markdown** | preview |
| Fuzzy | **FuzzyMatch** (ordo-one) | fzf-style Smith-Waterman: boundary bonuses, ranges for highlighting (editor decision 2026-08-26) |
| Content search | `rg` binary (`grep` fallback) | `cmd+shift+f` |
| Secrets | Security.framework (Keychain) | PG password |
| Disk watching | **AsyncFileMonitor** (CleanCocoa) on FSEvents | one `FolderContentMonitor` per workspace, multicast; `FSWatchService` only adds path filtering and debounced batches |
| Web page | WebKit (`WKWebView`) | one per window on `config.browser.url`, `isInspectable`, a non-persistent data store (browser decisions 2026-08-28) |

Criterion for adding one: the library does the job, is maintained, is Swift 6 compatible → we use it. "I could write it myself" is only an argument under 50 trivial lines.

Rejected: libghostty (zig build, unstable API, nothing the product needs), libgit2/SwiftGit2 (bypasses the user's git config).

## Security

- Foreman writes no secret into the repository, `.foreman/`, logs or errors. The Postgres password comes from the Keychain, or from `postgres.password` in `config.json` when the user chose to write it there (config decision 2026-08-27, local dev).
- No command built by interpolating values coming from another file or from a program's output. `Process` with `arguments: [String]`. `run`/`agents` commands are the user's text, passed as is to `$SHELL -l -c`.
- Every path coming from the config, the state or an event is checked to be under the workspace root before writing.
- No unrequested network access: no telemetry, no updates, no remote resource in the markdown preview.
- Displayed content (files, markdown, SQL, terminal output) is untrusted: no sequence in it ever triggers an action in the app.

## Performance

- Workspace opened < 500 ms to the first frame; panel < 100 ms; typing with no synchronous work.
- Nothing at startup that could wait; disk read level by level; bursts smoothed at the producer (FSEvents, `state.json`, process output).
- Measure before optimising: a non-trivial optimisation quotes a number. The three budgets are `os_signpost` intervals (`App/Perf.swift`), measured in M6 6.5 (`backlog/m6-polish.md`, 2026-08-27).
