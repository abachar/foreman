# Shortcuts

> Single table of the default shortcuts, across all features, and their implementation state. The source rule is in the spec cited; the task that ships a shortcut updates its row. `config` notation (`cmd`, `shift`, `opt` = Option ⌥, `ctrl`, `+`; `alt` accepted as an alias). Every shortcut can be overridden through `config.shortcuts["<id>"]` (`config` R4).

Scope: `global`, `tab(kind)` (a tab of that kind is active), `panel` (a panel has the focus), `terminal` (the active tab is a terminal surface and the center has the keyboard) — `layout` R22b —; `native` (native component, outside the registry), `menu` (the app's SwiftUI menu). Status: 🟢 implemented · ⚪ to do.

## Layout (`layout` R23)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+w` | `layout.tab.close` | Close the active tab | global | 🟢 |
| `cmd+1` … `cmd+9` | `layout.tab.N` | Tab N (9 = last) | global | 🟢 |
| `cmd+shift+[` / `cmd+shift+]` | `layout.tab.previous` / `.next` | Previous / next tab | global | 🟢 |
| `cmd+d` / `cmd+shift+d` | `layout.split.vertical` / `.horizontal` | Split right / below | global | 🟢 |
| `cmd+opt+←→↑↓` | `layout.focus.*` | Focus the neighbouring group | global | 🟢 |
| `cmd+opt+shift+←→↑↓` | `layout.move.*` | Move the active tab to the neighbouring group | global | 🟢 |
| `escape` | `layout.focus.center` | Give the focus back to the center | panel | 🟢 |
| `cmd+shift+n` | `layout.window.new` | New window (open a folder) | global | 🟢 |
| `cmd+opt+t` | `layout.toolbar.toggle` | Hide / show the toolbar | global | 🟢 |
| `cmd+o` | — | *File ▸ Open…* | menu | 🟢 |

## Explorer (`explorer` R21)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+shift+e` | `explorer.tree` | Show / hide the tree | global | 🟢 |
| `↑↓` `←` `→` | — | Navigate, collapse, expand | native | 🟢 (native `NSOutlineView`) |
| `space` | — | Open as a preview | native | 🟢 |
| `cmd+↓` | — | Open pinned | native | 🟢 |
| `enter` | — | Rename | native | 🟢 |
| `cmd+delete` | — | Delete (trash) | native | 🟢 |

## Editor (`editor` R6–R8, R14, R17, R23, R24)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+p` | `editor.quickOpen` | Quick open | global | 🟢 |
| `cmd+shift+f` | `editor.search` | Content search (bottom panel) | global | 🟢 |
| `cmd+s` / `cmd+opt+s` | `editor.save` / `.saveAll` | Save / save all | tab(editor.file) | 🟢 |
| `cmd+z` / `cmd+shift+z` | — | Undo / redo | tab(editor.file) | 🟢 (native `NSTextView`, Edit menu) |
| `cmd+]` / `cmd+[` | `editor.indent` / `.outdent` | Indent / outdent | tab(editor.file) | 🟢 |
| `cmd+/` | `editor.comment` | Comment / uncomment | tab(editor.file) | 🟢 |
| `opt+↑` / `opt+↓` | `editor.moveLine.*` | Move the line | tab(editor.file) | 🟢 |
| `cmd+l` | `editor.goToLine` | Go to line | tab(editor.file) | 🟢 |
| `cmd+k` | `editor.keepOpen` | Pin the preview tab (no chord, decision 2026-08-26) | tab(editor.file) | 🟢 |
| `cmd+f` / `cmd+opt+f` | `editor.find` / `.replace` | Find / replace in the file (`NSTextFinder`); `escape` closes the bar (native) | tab(editor.file) | 🟢 |
| `cmd+shift+v` | `editor.togglePreview` | Markdown source / preview | tab(editor.file) | 🟢 |
| `cmd+shift+l` | `editor.format` | Format the active file (`01-study-formatter.md` R24) | tab(editor.file) | ⚪ (M7) |
| `enter` / `cmd+enter` / `escape` / `↑↓` | — | Palette: open / new group / close / navigate | native | 🟢 |

## Terminal (`terminal` R12) — `agent.*` / `run.*` surfaces

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+c` / `cmd+v` | — | Copy the selection / paste | native (SwiftTerm) | 🟢 |
| `cmd+k` | `terminal.clear` | Clear the scrollback | terminal | 🟢 |
| `cmd+=` / `cmd+-` | `terminal.zoomIn` / `.zoomOut` | Font zoom | terminal | 🟢 |
| `ctrl+…`, `opt+…`, `esc`, arrows | — | To the process (`layout` R25) | native | 🟢 |

## Agents (`agents` R9)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| *(no default)* | `agents.<id>` | Open / activate the agent's tab | global | 🟢 |

## Run (`run` R5, R6, R9)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+r` | `run.palette` | Command palette | global | 🟢 |
| `enter` / `cmd+enter` / `opt+enter` / `escape` | — | Palette: launch / new tab / copy / close | native | 🟢 |
| `cmd+.` | `run.stop` | Stop the process (`SIGINT`, second press < 2 s → `SIGTERM`); no effect outside a `run.*` tab (decision 2026-08-27) | terminal | 🟢 |

## Git (`git`)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+shift+g` | `git.changes` | Changes panel | global | 🟢 (2026-08-27) |
| `cmd+shift+h` | `git.history` | History panel | global | ⚪ (M4) |
| `cmd+enter` | — | Commit (message field) | native | 🟢 (2026-08-27) |

## Postgres (`postgres`)

| Shortcut | Id | Action | Scope | Status |
|---|---|---|---|---|
| `cmd+shift+b` | `postgres.schema` | Schema panel (default changed on 2026-08-27: `cmd+shift+d` belongs to `layout.split.horizontal`) | global | ⚪ (M5) |
| `cmd+shift+q` | `postgres.query` | Query panel | global | ⚪ (M5) |
| `cmd+enter` / `cmd+.` | — | Execute / cancel | native | ⚪ (M5) |
| `cmd+c` | — | Copy the grid selection (TSV) | native | ⚪ (M5) |
| *(no default)* | `postgres.history` | Query history panel (`cmd+opt+h` from `postgres` R20 ruled out: it is macOS *Hide Others*) | global | ⚪ (M5) |

## Free

`cmd+t` (no shell, `product` R4), `cmd+n`, `cmd+shift+1…9`, `cmd+e`, `cmd+g`, `cmd+shift+o`, `cmd+shift+p` (kept free: it is the command palette elsewhere, postgres decision 2026-08-27), `cmd+opt+l` (free but left to the layout's `cmd+opt+…` family, editor decision 2026-08-27).

## Open points

- Several defaults clash with the author's macOS system shortcuts (noted 2026-08-26, list to be established); to be handled in M6 (polish) — until then, override through `config.shortcuts`.
