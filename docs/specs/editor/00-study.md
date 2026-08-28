# editor — Study

## Goal

Center tab `editor.file`: read and edit the workspace's text files with tree-sitter highlighting, markdown preview, in-file search, plus two entry points: quick open (`cmd+p`, fuzzy over paths) and content search (`cmd+shift+f`, bottom panel). A **simple** editor: no completion, no LSP, no multiple cursors.

## User stories

- US1 — I click a file in the explorer: it appears in < 100 ms, highlighted, as a preview; I type, the tab becomes pinned and marked as modified; `cmd+s` saves.
- US2 — `cmd+p`, I type `usrctrl`, `UserController.java` comes up first; `enter` opens it.
- US3 — `cmd+shift+f`, I type a term: the workspace's occurrences appear grouped by file; a click opens the file at the line.
- US4 — A build regenerates an open, unmodified file: it reloads on its own. If it was modified, I am asked.
- US5 — A `README.md` opens as source; `cmd+shift+v` switches to preview.
- US6 — I open a binary or a 200 MB file by mistake: a clear message, no freeze.

## Functional rules

### Tab and lifecycle

- R1 — An `editor.file` tab references a file (a path relative to the root, absolute otherwise) and has a state: `preview` / `pinned`, `isDirty`, cursor position, scroll. The same file is only open once per group; opening it again activates the existing tab.
- R2 — Preview (quick open and the git diff; the tree no longer opens previews, `explorer` R12 amended 2026-08-28): italic title; one preview per group, replaced by the next one. Becomes `pinned` on the first edit, or with `cmd+k` ("keep open"; decision 2026-08-26: no `cmd+k enter` chord, the registry does not know about chords).
- R3 — Opening (`Editor.open(path, preview:, newGroup:, line:)`, called by the explorer, git, the palette, the search): read off the main actor; UTF-8 encoding detection (BOM tolerated), otherwise Latin-1 with a warning; line endings detected (LF/CRLF) and preserved on save; if `line` is given, the cursor goes there and the line is centred.
- R4 — Persistence (`layout` R28): path, `pinned`, cursor, scroll. `isDirty` is never persisted: when the window closes with a modified tab, a confirmation appears (`layout` R15); unsaved content is lost if it is confirmed. A file gone at restoration: the tab is ignored (`product` edge case, settled).
- R5 — Title: the file name; if two tabs of the same group have the same name, the parent folder is added (`a/index.ts`, `b/index.ts`). A `●` marker when `isDirty`.

### Editing

- R6 — v1 features: a gutter with line numbers (decision 2026-08-27), typing, selection, undo/redo (`cmd+z`/`cmd+shift+z`), cut/copy/paste, indentation keeping the previous line's indent, `tab` inserting according to the file (spaces/tabs detected over the first 100 lines, 4 spaces by default), `cmd+]`/`cmd+[` to indent/outdent the selection, `cmd+/` to comment/uncomment the line (prefix provided by the grammar), no `cmd+d` (reserved for split, `layout`), move a line with `opt+↑/↓`, go to line with `cmd+l`.
- R7 — In-file search: `cmd+f` (a bar at the top of the tab, case-insensitive by default, `enter`/`shift+enter` for next/previous, occurrences highlighted), `cmd+opt+f` to replace (one / all). `escape` closes the bar.
- R8 — Saving: `cmd+s` explicitly only, **no autosave**. Atomic write (`coding-rules`) keeping the encoding and the line endings; a final newline is added when missing (can be turned off with `insertFinalNewline` in the `editor` section of `.foreman/config.json` — there is no global config, config decision 2026-08-26). `cmd+opt+s` saves every modified tab.
- R9 — File modified on disk (through `FSWatchService`): if the tab is not `isDirty` → a silent reload with the cursor and scroll preserved; if it is `isDirty` → a "modified on disk" banner with *Keep my changes* / *Reload*. File deleted on disk: a "deleted" banner; the tab stays, `cmd+s` recreates it. File renamed (`Editor.fileRenamed`, `explorer` R17): the tab follows.
- R10 — Conflict on save (the file changed on disk since the last read, and the user did not answer the R9 banner): the save is refused with *Overwrite* / *Cancel*.

### Highlighting

- R11 — v1 grammars (mapped by extension and by file name): java, kotlin, typescript, tsx, javascript, json, yaml, toml, markdown, bash (`.sh`, `.zsh`, `.zshrc`…), swift, html, css, dockerfile (`Dockerfile*`), sql (`.sql`, `.psql`; shipped on 2026-08-28 from tree-sitter-sql's `gh-pages` branch, decision of that day). Unknown extension → plain text.
- R12 — Highlighting is provided by the shared `Highlight/` folder (`architecture.md`): Neon attaches a highlighter to the `NSTextView`, parses off the main actor, incrementally and cancellably on every keystroke, and applies the attributes itself. The editor only provides the grammar (R11) and the theme: the roles (`keyword`, `string`, `comment`, `type`, `function`, `number`, `variable`, `punctuation`…) are mapped to colors by `ThemeService`.
- R13 — Highlighting is degradable: a missing grammar, a parsing error or too slow (> 200 ms on the first parse) → plain text, a `debug` log, no banner.
- R14 — Markdown: the tab has two modes, `preview` (the default since 2026-08-29; `source` until then) and `source`, toggled with `cmd+shift+v`; the mode is persisted with the tab (a restored tab keeps the mode it had). The preview is rendered from the `swift-markdown` AST: headings, lists, code (highlighted through R11 when the language is known), tables, links (opened in the browser on `cmd+click`; relative links to a workspace file opened in Foreman), local workspace images only, never a remote resource (`architecture.md`, security).

### Size limits and binaries

- R15 — Detection **before** the full read: a file is binary if it contains a null byte in its first 8 KB or if its extension is in a known list (images, archives, executables…). A binary is not opened: a "binary file — N KB" tab with *Reveal in Finder*.
- R16 — Size: > 2 MB → opened **read-only without highlighting** with a banner; > 50 MB → refused (a message with the size). A line longer than 10,000 characters → highlighting disabled for the file.

### Quick open (`cmd+p`)

- R17 — Shared palette (`Palette/`, `architecture.md`, also used by `run`); fuzzy search over the workspace's relative paths, case-insensitive, scored by the chosen fuzzy library (subsequence with bonuses on `/`, `.`, `_`, `-` and camelCase boundaries, and on the file name). The 50 best results are shown; `↑↓` navigate, `enter` opens (pinned), `cmd+enter` opens in a new group, `escape` closes.
- R18 — The path index is built **the first time the palette is opened**, off the main actor, by walking the workspace with the shared exclusion list (`architecture.md`) plus the known gitignored entries (through `Git.statusChanges`, otherwise ignored); it is then maintained by `FSWatchService`. Cap: 200,000 entries; beyond that the index is truncated with a warning in the palette.
- R19 — Empty palette (nothing typed): this workspace's recently opened files, most recent first (a list of 50 persisted in `state.json`).

### Content search (`cmd+shift+f`)

- R20 — **Bottom** panel `editor.search`: a search field, *case* / *whole word* / *regex* options, an include filter (glob, e.g. `src/**/*.ts`). Run through the `rg` binary when it is in the `PATH`, otherwise `grep -rn` (`Process` with an array of arguments, never a shell — `architecture.md`, security); the shared exclusions are applied; `.gitignore` is honoured natively by `rg`.
- R21 — Results grouped by file, expanded, one row per match with the match highlighted; a click or `enter` opens the file at the line (as a preview), `cmd+enter` pins it. Cap of 2,000 matches (a "results truncated" message). A running search is cancelled by the next one or by closing the panel.
- R22 — No multi-file replace in v1 (`sed`/`rg` in the terminal).

### Shortcuts

- R23 — The editor's shortcuts (`cmd+s`, `cmd+f`, `cmd+z`, `cmd+/`, `cmd+l`, `cmd+shift+v`…) are declared to the `ShortcutRegistry` with the scope **`editor.file` tab active**: they capture nothing while a terminal has the focus (`layout` R25). `cmd+p` and `cmd+shift+f` are global.

## Edge cases

- File without write permission: opened read-only with a banner; `cmd+s` offers *Reveal in Finder*.
- Non-UTF-8 encoding: read as Latin-1, with a banner; saving rewrites it as **UTF-8** with an explicit warning in the banner (no preservation of exotic encodings).
- A file being written by another process (a build): a burst of events coalesced by the debounce; the reload (R9) reads the final state.
- A grammar crashing on a pathological file: tree-sitter is robust; on a timeout, R13.
- Quick open on `$HOME`: the index is capped (R18), and the message invites opening a subfolder.
- `rg` missing and `grep` on a large workspace: slow but cancellable; a message suggests `brew install ripgrep`.

## Out of scope for v1

- LSP, completion, diagnostics, go-to-definition. (**Formatting** left this list on 2026-08-27: see [01-study-formatter.md](01-study-formatter.md).)
- Multiple cursors, column selection, minimap, code folding, advanced bracket matching.
- Multi-file replace.
- Side-by-side synchronised markdown preview.
- Editing files outside the workspace other than by opening an absolute path (no system "open a file").
- Autosave, local version history.
- Color themes specific to the editor (the roles are mapped by `ThemeService` onto the terminal theme, `terminal` R14).

## Technical options

- **Folder**: `Sources/Foreman/Editor/`; consumes the shared `Highlight/` and `Palette/` folders.
- **Text component**: `NSTextView` on **TextKit 2** (`NSTextLayoutManager`) inside an `NSViewRepresentable` (platform first, `architecture.md` P3). Undo, selection, IME, accessibility and performance on large files come for free. A custom view was rejected (huge cost), TextKit 1 rejected (deprecated in practice). Known risk: TextKit 2's blind spots (some APIs silently fall back to TextKit 1); to be validated by a prototype when M1 is broken down.
- **Highlighting**: `Highlight/` = SwiftTreeSitter + Neon used as designed (`architecture.md` P2): Neon's `TextViewHighlighter` attached to the `NSTextView`, with a `LanguageConfiguration` per grammar (the `highlights.scm` queries from the `tree-sitter-*` SPM packages). Neon handles incrementality, cancellation and applying the attributes; the editor never rewrites a parsing session. `Highlight/` carries the extension → grammar mapping (R11) and the role → color mapping through `ThemeService`.
- **Markdown**: `swift-markdown` (the `Document` AST) → SwiftUI (`Text` with `AttributedString` + blocks). Code blocks highlighted through `Highlight/`.
- **Fuzzy**: `Palette/` with the chosen fuzzy SPM library (`architecture.md`); the editor provides the paths and receives the selection. No home-made scoring.
- **Content search**: `Process` with `rg --json` (JSON parsed line by line) or `grep -rnI --null`; a cancellable `Task` produces an `AsyncStream<SearchMatch>`.
- **Tests** (parsers only): binary/encoding/indent/EOL detection (R3, R6, R15), parsing `rg`/`grep` output (R20), extension → grammar mapping (R11), deduplicated titles (R5).

## Decisions

See [decisions.md](decisions.md).

Later studies: [`01-study-formatter.md`](01-study-formatter.md) (R24–R25), [`02-study-folding.md`](02-study-folding.md) (R26–R28, code folding).
