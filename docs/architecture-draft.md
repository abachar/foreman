# Architecture (brouillon initial)

> Extrait du README d'origine (2026-08-25). Source de départ, à ventiler et affiner dans `specs/`. En cas de conflit, `specs/` fait foi.

## Vision

One window, one workspace, terminal at the center:

```
┌──────────┬──────────────────────────────┬──────────┐
│          │  [term 1] [term 2] [file.md] │          │
│  LEFT    │                              │  RIGHT   │
│  panel   │      CENTER (tabs:           │  panel   │
│          │      terminals + views)      │          │
│          ├──────────────────────────────┤          │
│          │      BOTTOM panel            │          │
└──────────┴──────────────────────────────┴──────────┘
```

**Layout rules (non-negotiable):**
- The center zone is always visible. It holds tabs: terminal tabs (libghostty) and view tabs contributed by plugins (editor, diff…). Terminal is the default tab type.
- Left / Right / Bottom are panel slots. **At most ONE panel visible per slot at a time.**
- Every panel is toggled by a keyboard shortcut. Pressing the shortcut of the visible panel hides it; pressing the shortcut of another panel on the same side replaces it.
- Plugins declare panels; they never control layout directly. The core `PanelManager` decides.

## Architecture

### Core (target `WraithApp`)
Knows nothing about git, postgres, or markdown. Provides:
- **TerminalHost** — libghostty surfaces + PTY management (`posix_openpt`/forkpty, zsh), tabs in the center zone
- **PanelManager** — the one-panel-per-side state machine (3 optionals: left/right/bottom → active panel id or nil)
- **ShortcutRegistry** — shortcut → panel/action mapping, conflict detection, overrides from workspace config
- **Services** exposed to plugins: `WorkspaceService` (root path, config), `FSWatchService` (single FSEvents stream, multiplexed, debounced ~300ms, ignores `target/`, `node_modules/`, `.git/objects`), `ThemeService`

### Plugin contract (target `WraithKit`, separate framework)
```swift
public protocol Plugin {
    var id: String { get }
    var panels: [PanelDescriptor] { get }
    var centerTabs: [CenterTabDescriptor] { get }   // e.g. editor tabs
    func activate(context: PluginContext)
    func deactivate()
}

public struct PanelDescriptor {
    let id: String                       // "git.status"
    let title: String
    let side: PanelSide                  // .left, .right, .bottom
    let defaultShortcut: KeyboardShortcut
    let makeView: () -> AnyView          // lazy: built on first activation
}

public protocol PluginContext {
    var workspace: WorkspaceService { get }
    var terminal: TerminalService { get }    // sendCommand(toTab:_:), newTab(cwd:)
    var events: EventBus { get }             // fs changes, panel lifecycle, openFile requests
}
```

Plugins are **statically compiled** (one Swift target each, registered in an array at startup). The protocol is the boundary; dynamic loading may come later.

### Plugins (each its own target)
| Plugin | Panels / tabs | Default shortcuts |
|---|---|---|
| `PluginExplorer` | left: workspace file tree | ⌘⇧E |
| `PluginGit` | left: changes per repo · bottom: diff & history | ⌘⇧G / ⌘⇧H |
| `PluginEditor` | center tabs: file viewer/editor, markdown preview | ⌘P (quick open) |
| `PluginPostgres` | right: schema browser · bottom: query + results grid | ⌘⇧D |
| `PluginRun` | no panel — command palette entries → terminal | ⌘R |

## Workspace config

A workspace is any folder opened with `wraith .`. Optional `.wraith.json` at the root:

```json
{
  "repos": ["backend", "frontend", "e2e"],
  "commands": {
    "backend":  { "build": "mvn compile", "test": "mvn test" },
    "frontend": { "start": "npm start",   "test": "npm run test" },
    "e2e":      { "test": "npx playwright test" }
  },
  "postgres": { "host": "localhost", "port": 5432, "database": "ccoe" },
  "shortcuts": {}
}
```

Git repos are auto-detected (scan for `.git/`) when `repos` is absent. `commands` feed PluginRun. `postgres` prefills the connection (never store passwords here — use Keychain).

## Dependencies

| Dependency | Role | Notes |
|---|---|---|
| **libghostty** | terminal emulation (VT parsing, state) + Metal rendering | vendored in `Vendor/libghostty`, **pinned to a specific commit** — the C API is not stable yet. Fallback plan: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) behind the same `TerminalSurface` interface |
| **SwiftGit2 / libgit2** | git status, diff, log | SPM or vendored |
| **PostgresNIO** | Postgres client | SPM |
| **SwiftTreeSitter** + grammars (java, typescript, markdown, sql) | syntax highlighting | SPM |
| **swift-markdown** | markdown preview | SPM |

## Repository layout

```
wraith/
├── Package.swift / Wraith.xcodeproj
├── Sources/
│   ├── WraithApp/          # core: app, layout, terminal host, services
│   ├── WraithKit/          # plugin contract (framework)
│   ├── PluginExplorer/
│   ├── PluginGit/
│   ├── PluginEditor/
│   ├── PluginPostgres/
│   └── PluginRun/
├── Vendor/
│   └── libghostty/
├── cli/
│   └── wraith              # shell script: open -a Wraith --args "$(pwd)"
└── Tests/
```

## Roadmap (build in this order)

- [ ] **M0 — Shell**: app window, 3-zone layout, PanelManager + ShortcutRegistry with a dummy panel, `wraith` CLI opens a folder
- [ ] **M1 — Terminal**: PTYManager + libghostty surface rendering (Metal), center tabs, multiple terminals. *Hardest part — do it early. If the libghostty bridge blocks, ship M1 on SwiftTerm behind `TerminalSurface` and swap later.*
- [ ] **M2 — Explorer + Editor**: file tree (lazy, FSEvents refresh), open file as center tab, tree-sitter highlighting, markdown preview, ⌘P quick open
- [ ] **M3 — Git**: repo auto-detection, changes panel per repo, side-by-side diff, history view
- [ ] **M4 — Run**: `.wraith.json` commands surfaced as palette actions / buttons, output sent to a dedicated terminal tab
- [ ] **M5 — Postgres**: connection via PostgresNIO, schema browser, query editor (reuse editor with SQL grammar), results grid
- [ ] **M6 — Polish**: themes, settings, Homebrew tap (`abachar/tap/wraith`), signed & notarized DMG

## Engineering conventions

- Swift 6, strict concurrency. UI state via `@Observable`. No singletons in plugins — everything through `PluginContext`.
- Plugins must not import each other or `WraithApp`; only `WraithKit`. Enforced by target dependencies.
- Panels are lazy: no work (no PG connection, no git scan) until first shown.
- One FSEvents stream for the whole workspace; plugins subscribe through `EventBus` with path filters.
- Secrets (PG passwords) go to Keychain, never to `.wraith.json`.
- Every milestone lands with unit tests on non-UI logic (PanelManager, config parsing, git service, PTY lifecycle).

