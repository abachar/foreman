# Configuration reference

> Every key of the configuration, its type, its default and where it is decoded. The rules live in [`specs/config/00-study.md`](specs/config/00-study.md) (R2–R7) and in each domain's study; this file is the flat view, kept in step with the code in the same commit as any key change. Every key is optional (config R2); an invalid value is reported in the UI and the default stays (config R7); the files are watched and reloaded live (config R6).

**Two files, one schema** (config R4, 2026-08-30): the global `$XDG_CONFIG_HOME/foreman/config.json` (else `~/.config/foreman/config.json`) and the workspace's `<root>/.foreman/config.json`. Every section below is accepted in both; a section that is an object in both is merged key by key, one level deep, and the workspace's key wins — any other value (a string, a number, an array such as `repos`) is replaced whole. In practice `agents`, `shortcuts`, `theme`, `terminal` and `formatter` belong in the global file, `repos`, `commands`, `postgres` and `browser` in the workspace's.

Example with every section (values are the defaults unless noted):

```json
{
  "repos": ["."],
  "commands": {
    "root": {
      "$env": { "CLICOLOR": "1" },
      "build": "xcodebuild build -scheme Foreman",
      "docs-tree": { "run": "ls", "cwd": "docs", "env": { "CLICOLOR": "1" } }
    }
  },
  "agents": {
    "claude": { "command": "claude --continue" },
    "my-agent": { "title": "My agent", "command": "my-agent --resume", "icon": "terminal", "enabled": true }
  },
  "postgres": { "host": "localhost", "port": 5432, "database": "postgres", "user": "postgres", "sslmode": "prefer", "options": { "application_name": "foreman" }, "statementTimeout": 30 },
  "editor": { "insertFinalNewline": true },
  "formatter": { "timeout": 5, "swift": "swift format", "md": "npx --no-install prettier --stdin-filepath file.md" },
  "git": { "path": "/usr/bin/git" },
  "browser": { "url": "http://localhost:3000" },
  "terminal": { "font": "JetBrains Mono", "fontSize": 13, "theme": "system" },
  "theme": { "interfaceFontSize": 13, "accent": "#4A86E0" },
  "shortcuts": { "git.changes": "cmd+shift+g" }
}
```

## `repos` — `Workspace/WorkspaceConfig.swift`

| Key | Type | Default | Note |
|---|---|---|---|
| `repos` | `[string]` | absent → scan for `.git/` (depth ≤ 2, `node_modules`, `target`, `.build`, `DerivedData` skipped) | Paths relative to the root; a missing folder is dropped with a warning. No repo at all → no git panels (git R1b). |

## `commands` — `Run/RunCatalog.swift` (run R1–R3, R8)

`{ "<repo>": { "<name>": <command> } }`. `<repo>` is `.` or a path under the root; `root` spells `.` in ids (`root:build`) and is accepted as a key unless a `root/` folder exists. A missing repo keeps its commands greyed.

| Key | Type | Default | Note |
|---|---|---|---|
| `<name>` | `string` | — | Short form: the text passed as is to `$SHELL -l -c`, cwd = the repo. |
| `<name>.run` | `string` | — | Long form. |
| `<name>.cwd` | `string` | the repo | Relative to the repo. |
| `<name>.env` | `{string: string}` | `{}` | Injected in the process environment, never on the command line. |
| `$env` | `{string: string}` | `{}` | Reserved key: environment for every command of the repo, under the command's own `env`. |

Commands detected from manifests (run R14) need no config. Without any command there is no ▶ Run button and no `cmd+r` (run R6b).

## `agents` — `Agents/AgentCatalog.swift` (agents R3)

`{ "<id>": { title?, command?, icon?, enabled? } }`, id `[a-z0-9][a-z0-9_-]*`. Built-ins: `claude` (`claude`), `antigravity` (`agy`), `opencode` (`opencode`), `pi` (`pi`) — all shown unless `enabled: false`; `{}` is enough to keep one. An unknown id is a custom agent (`command` mandatory).

| Key | Type | Default | Note |
|---|---|---|---|
| `title` | `string` | the id (built-ins: their name) | Toolbar tooltip, home screen, tab title. |
| `command` | `string` | built-in command | Passed as is to `$SHELL -l -c`, cwd = the repo chosen at launch. |
| `icon` | `string` | `terminal` (built-ins: `agent-<id>`) | An SF Symbol, a built-in logo (`agent-claude`, `agent-antigravity`, `agent-opencode`, `agent-pi`), or an SVG/PNG path relative to the root. |
| `enabled` | `bool` | `true` | `false` hides the agent. |

Shortcut per agent: `shortcuts["agents.<id>"]`, none by default.

## `postgres` — `Postgres/PostgresConfig.swift` (postgres R1–R3, R12)

One object = one connection per workspace. Without `database` and `user` there is no Schema panel and no query shortcut (postgres R2).

| Key | Type | Default | Note |
|---|---|---|---|
| `host` | `string` | `localhost` | |
| `port` | `int` | `5432` | `1…65535`. |
| `database` | `string` | — | Required. |
| `user` | `string` | — | Required. |
| `sslmode` | `disable` \| `prefer` \| `require` | `prefer` | |
| `password` | `string` | Keychain (`foreman.postgres.<host>:<port>/<database>/<user>`) | Used as is, never logged nor copied to the Keychain; keep the file out of git then (config R11). |
| `options` | `{string: string}` | `{}` | Startup parameters (`application_name`…), passed as they are. |
| `statementTimeout` | `int` seconds | `30` | `1…3600`. |

## `editor` — `Editor/EditorFeature.swift`

| Key | Type | Default | Note |
|---|---|---|---|
| `insertFinalNewline` | `bool` | `true` | On save. Read on every use. |

## `formatter` — `Editor/FormatterCatalog.swift` (editor R25–R26, R30)

One command per lowercased extension (or whole file name without one, e.g. `Dockerfile`); the file's content goes to stdin, stdout replaces it (`cmd+shift+l`). Read on every use.

| Key | Type | Default | Note |
|---|---|---|---|
| `timeout` | `number` seconds | `5` | `1…60`, clamped. |
| `<ext>` | `string` | — | Shell command, `$SHELL -l -c`, cwd = the file's folder. |

## `lsp` — `Editor/LSPCatalog.swift` (editor R35, R39)

One language server command per lowercased extension (or whole file name without one); the server is started at the first tab of that language and stopped with the last (editor R36). Read on every use. A server needing per-project state puts it on its own command line — `config.json` is per workspace, so the path is written once, here (`jdtls -data <this project>/.foreman/jdtls`).

| Key | Type | Default | Note |
|---|---|---|---|
| `timeout` | `number` seconds | `10` | `1…60`, clamped. Bounds `initialize` and the shutdown (editor R36, R39). |
| `<ext>` | `string` | — | Shell command, `$SHELL -l -c`, cwd = the workspace root. It must be the server's **stdio** invocation: most need a flag for it (`--stdio`), and without it they print a usage message and exit — which the banner now quotes back (editor R39). |

```json
{
  "lsp": {
    "swift": "xcrun sourcekit-lsp",
    "ts": "typescript-language-server --stdio",
    "tsx": "typescript-language-server --stdio",
    "js": "typescript-language-server --stdio",
    "jsx": "typescript-language-server --stdio",
    "html": "ngserver --stdio --ngProbeLocations node_modules --tsProbeLocations node_modules",
    "java": "jdtls -data /Users/me/Projects/shop/.foreman/jdtls"
  }
}
```

## `git` — `Git/GitFeature.swift` (git R26)

| Key | Type | Default | Note |
|---|---|---|---|
| `path` | `string` | `git` found in the login shell's `PATH` | Executable, resolved once per window. |

## `browser` — `Browser/BrowserConfig.swift` (browser R2)

| Key | Type | Default | Note |
|---|---|---|---|
| `url` | `string` | none → no button, no tab | `http` or `https` with a host; a new URL loads in the open tab. |

## `terminal` — `App/ThemeService.swift` (terminal R14)

Applies to every code surface: terminals, editor, diff, SQL editor, markdown code blocks.

| Key | Type | Default | Note |
|---|---|---|---|
| `font` | `string` | `JetBrains Mono` (system monospaced when not installed) | Family name. |
| `fontSize` | `number` | `13` | `8…32`, clamped. |
| `theme` | `light` \| `dark` \| `system` | `system` | Chooses the token set below. |

## `theme` — `App/ThemeService+Tokens.swift` (design R6, R8–R11)

Flat `{ "<token>": value }`; a value applies to **both** sets (`dark` and `light`). Unknown key, malformed color or out-of-range metric → warning, default kept. Colors as `#rgb` or `#rrggbb`.

Colors (defaults of the `dark` set, designed; `light` is derived mechanically, design R10):

| Token | Dark | Light | Carries |
|---|---|---|---|
| `windowBackground` | `#36373B` | `#FFFFFF` | the ground under the islands (lighter than them since 2026-08-29) |
| `surface` | `#1E1F22` | `#F2F3F5` | an island: editor, terminal, panels, preview |
| `surfaceRaised` | `#2B2D30` | `#E8E9ED` | toolbar, tab bar, panel headers, toolbar buttons |
| `surfaceSunken` | `#151618` | `#DDDFE4` | input fields, current line, hover/press fills |
| `surfaceOverlay` | `#26282C` | `#F7F8FA` | the palette |
| `textPrimary` | `#DFE1E5` | `#1E1F22` | text (≥ 4.5:1 on every surface, tested) |
| `textSecondary` | `#9DA0A8` | `#5A5D63` | subtitles, inactive tabs, icons (≥ 3:1) |
| `textDisabled` | `#6F737A` | `#9A9DA3` | greyed rows |
| `separator` | `#34363A` | `#D9DBE0` | thin lines inside an island |
| `border` | `#45484E` | `#C9CCD2` | outlines (toggles, fields) |
| `accent` | `#4A86E0` | `#3574F0` | focus, selection, active tab rule |
| `accentText` | `#FFFFFF` | `#FFFFFF` | text on the accent |
| `statusGreen` / `statusOrange` / `statusRed` / `statusBlue` | `#5FB865` / `#E0A63B` / `#E5534B` / `#4A86E0` | `#2E8B3E` / `#B9711A` / `#C93B34` / `#3574F0` | badges, banners |

Metrics (points) and type:

| Token | Default | Range | Carries |
|---|---|---|---|
| `islandRadius` | `8` | `0…32` | corner radius of the islands |
| `gutter` | `6` | `0…32` | ground visible between islands and window edges |
| `toolbarGap` | `2` | `0…32` | gap between the toolbar and the islands' top edge |
| `barHeight` | `36` | `24…64` | toolbar, tab bar, panel headers |
| `rowHeight` | `24` | `16…48` | native list rows (explorer, schema); grows with the font if needed |
| `contentInset` | `12` | `0…48` | padding inside the islands' content |
| `interfaceFontSize` | `13` | `10…24` | body size of the chrome; `small` = body − 2, `title` = body + 1 |
| `readingFontSize` | `16` | `10…32` | markdown preview body; headings × 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85, small × 0.875, code × 0.85 in `terminal.font` |
| `interfaceFont` | system font | family name | the chrome font (code keeps `terminal.font`) |

Syntax colors are not overridable (editor R12).

## `shortcuts` — `Layout/ShortcutRegistry` (config R3, layout R25)

`{ "<action id>": "<shortcut>" }` overriding the defaults declared by the features. Ids, defaults and syntax: [`shortcuts.md`](shortcuts.md).

## Files Foreman writes (never edit)

`.foreman/state.json` (UI state) and `.foreman/postgres-history.json`: versioned, atomic, `.bak` when unreadable; both in `.gitignore`.
