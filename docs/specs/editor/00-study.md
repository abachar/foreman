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

- R1 — An `editor.file` tab references a file (a path relative to the root, absolute otherwise) and has a state: `preview` / `pinned`, `isDirty`, cursor position, scroll. The same file is only open once per group; opening it again activates the existing tab. **Amended 2026-08-30**: an *untitled* tab is one whose file is a scratch (R34); it is an `editor.file` tab like any other — nothing else in the tab, its payload or its restoration knows about it.
- R2 — Preview (quick open and the git diff; the tree no longer opens previews, `explorer` R12 amended 2026-08-28): italic title; one preview per group, replaced by the next one. Becomes `pinned` on the first edit, or with `cmd+k` ("keep open"; decision 2026-08-26: no `cmd+k enter` chord, the registry does not know about chords).
- R3 — Opening (`Editor.open(path, preview:, newGroup:, line:)`, called by the explorer, git, the palette, the search): read off the main actor; UTF-8 encoding detection (BOM tolerated), otherwise Latin-1 with a warning; line endings detected (LF/CRLF) and preserved on save; if `line` is given, the cursor goes there and the line is centred.
- R4 — Persistence (`layout` R28): path, `pinned`, cursor, scroll. `isDirty` is never persisted: when the window closes with a modified tab, a confirmation appears (`layout` R15); unsaved content is lost if it is confirmed. A file gone at restoration: the tab is ignored (`product` edge case, settled).
- R5 — Title: the file name; if two tabs of the same group have the same name, the parent folder is added (`a/index.ts`, `b/index.ts`). A `●` marker when `isDirty`.

### Editing

- R6 — v1 features: a gutter with line numbers (decision 2026-08-27), typing, selection, undo/redo (`cmd+z`/`cmd+shift+z`), cut/copy/paste, indentation keeping the previous line's indent, `tab` inserting according to the file (spaces/tabs detected over the first 100 lines, 4 spaces by default), `cmd+]`/`cmd+[` to indent/outdent the selection, `cmd+/` to comment/uncomment the line (prefix provided by the grammar), no `cmd+d` (reserved for split, `layout`), move a line with `opt+↑/↓`, go to line with `cmd+l`.
- R7 — In-file search: `cmd+f` (a bar at the top of the tab, case-insensitive by default, `enter`/`shift+enter` for next/previous, occurrences highlighted), `cmd+opt+f` to replace (one / all). `escape` closes the bar.
- R8 — Saving: `cmd+s` explicitly only, **no autosave**. Atomic write (`coding-rules`) keeping the encoding and the line endings; a final newline is added when missing (can be turned off with `insertFinalNewline` in the `editor` section of `.foreman/config.json` — there is no global config, config decision 2026-08-26). `cmd+opt+s` saves every modified tab. **Amended 2026-08-30**: on an untitled tab (R34), `cmd+s` asks **where** — an `NSSavePanel` on the workspace root — and only then writes; "no autosave" is about the user's files, a scratch has its own rule (R34).
- R9 — File modified on disk (through `FSWatchService`): if the tab is not `isDirty` → a silent reload with the cursor and scroll preserved; if it is `isDirty` → a "modified on disk" banner with *Keep my changes* / *Reload*. File deleted on disk: a "deleted" banner; the tab stays, `cmd+s` recreates it. File renamed (`Editor.fileRenamed`, `explorer` R17): the tab follows.
- R10 — Conflict on save (the file changed on disk since the last read, and the user did not answer the R9 banner): the save is refused with *Overwrite* / *Cancel*.

### Highlighting

- R11 — v1 grammars (mapped by extension and by file name): java, kotlin, typescript, tsx, javascript, json, yaml, toml, markdown, bash (`.sh`, `.zsh`, `.zshrc`…), swift, html, css, dockerfile (`Dockerfile*`), sql (`.sql`, `.psql`; shipped on 2026-08-28 from tree-sitter-sql's `gh-pages` branch, decision of that day). Unknown extension → plain text.
- R12 — Highlighting is provided by the shared `Highlight/` folder (`architecture.md`): Neon attaches a highlighter to the `NSTextView`, parses off the main actor, incrementally and cancellably on every keystroke, and applies the attributes itself. The editor only provides the grammar (R11) and the theme: the roles (`keyword`, `string`, `comment`, `type`, `function`, `number`, `variable`, `punctuation`…) are mapped to colors by `ThemeService`.
- R13 — Highlighting is degradable: a missing grammar, a parsing error or too slow (> 200 ms on the first parse) → plain text, a `debug` log, no banner.
- R14 — Markdown: the tab has two modes, `preview` (the default since 2026-08-29; `source` until then) and `source`, toggled with `cmd+shift+v`; the mode is persisted with the tab (a restored tab keeps the mode it had). The preview is rendered from the `swift-markdown` AST: headings, lists, code (highlighted through R11 when the language is known), tables, links (opened in the browser on `cmd+click`; relative links to a workspace file opened in Foreman), local workspace images only, never a remote resource (`architecture.md`, security).

### Untitled tabs

- R34 — **An untitled tab is a scratch file** (2026-08-30). *File ▸ New File* opens an `editor.file` tab on a new empty file under `<root>/.foreman/scratches/`, named `Untitled`, then `Untitled 2`, `Untitled 3`… — the first free name in that folder, so the numbering is per workspace and survives a restart. Being untitled is read off the path and nothing else: no flag in the payload, no "no file yet" state, restoration (R4) works unchanged.
  - The draft is written to its scratch ~1 s after the last keystroke, so quitting the app brings it back untitled at the next launch. The tab stays `isDirty` all the same: the file on disk is Foreman's, not a name the user chose, so closing the tab still asks (`layout` R15) and `cmd+s` still names it (R8). The write carries the new modification date, so Foreman's own write never comes back as a "modified on disk" banner (R9).
  - `cmd+s` asks where to write it (`NSSavePanel`, the workspace root by default), **moves** the scratch there and the tab becomes an ordinary file tab: title (R5), highlighting from the new extension (R11), recent files (R19), and the explorer shows the file. Nothing else happens: it is the same tab, on a new path.
  - The scratch is deleted with its tab (after `layout` R15's confirmation). The folder and its `.gitignore` stay for the next draft.
  - The drafts are **not** files of the workspace: `<root>/.foreman/scratches/.gitignore` holds `*`, so git reports them ignored and they reach neither the Changes panel (`git` R6) nor the user's own `.gitignore`; the tree does not show them (`explorer` R3); quick open does not index them (R18 already skips `.foreman`); they never enter the recent list (R19).

### Size limits and binaries

- R15 — Detection **before** the full read: a file is binary if it contains a null byte in its first 8 KB or if its extension is in a known list (images, archives, executables…). A binary is not opened: a "binary file — N KB" tab with *Reveal in Finder*.
- R16 — Size: > 2 MB → opened **read-only without highlighting** with a banner; > 50 MB → refused (a message with the size). A line longer than 10,000 characters → highlighting disabled for the file.

### Quick open (`cmd+p`)

- R17 — Shared palette (`Palette/`, `architecture.md`, also used by `run`); fuzzy search over the workspace's relative paths, case-insensitive, scored by the chosen fuzzy library (subsequence with bonuses on `/`, `.`, `_`, `-` and camelCase boundaries, and on the file name). The 50 best results are shown; `↑↓` navigate, `enter` opens (pinned), `cmd+enter` opens in a new group, `escape` closes.
- R18 — The path index is built **the first time the palette is opened**, off the main actor, by walking the workspace with the shared exclusion list (`architecture.md`) plus the known gitignored entries (through `Git.statusChanges`, otherwise ignored); it is then maintained by `FSWatchService`. Cap: 200,000 entries; beyond that the index is truncated with a warning in the palette.
- R19 — Empty palette (nothing typed): this workspace's recently opened files, most recent first (a list of 50 persisted in `state.json`).

### Content search (`cmd+shift+f`)

- R20 — **Bottom** panel `editor.search`: a search field, *case* / *whole word* / *regex* options, an include filter (glob, e.g. `src/**/*.ts`). Run through the `rg` binary when it is in the `PATH`, otherwise `grep -rn` (`Process` with an array of arguments, never a shell — `architecture.md`, security); the shared exclusions are applied; `.gitignore` is honoured natively by `rg`.
- R21 — (**Amended 2026-10-17**, M22 22.4: results reach the panel in batches — the first match at once, then at most one update every 50 ms — the file groups are found by a dictionary, and a line longer than 300 characters is cut around its first match with `…` on the cut sides, since `rg --json` ignores `--max-columns`; each search is an `os_signpost` interval `search` with a `search.first` event.) Results grouped by file, expanded, one row per match with the match highlighted; a click or `enter` opens the file at the line (as a preview), `cmd+enter` pins it. Cap of 2,000 matches (a "results truncated" message). A running search is cancelled by the next one or by closing the panel.
- R22 — No multi-file replace in v1 (`sed`/`rg` in the terminal).

### Reading aids (2026-10-16, M21 21.8–21.11, reference view 02)

- R53 — **Print margin**: a 1 pt `separator` line at the column `config.editor.printMargin` (120 by default, `0` for none), the full height of the text, under the text; its x is the text's left inset plus `column` times the advance of one character of the editor font. A 1 pt `separator` line also closes the gutter on the text's side (`design` R25).
- R54 — **Indent guides** (M21 21.9): every visible line gets a 1 pt `separator` line at the column of each enclosing indentation level but the outermost (a line indented three levels has guides at one and two levels); a level is the indentation unit the tab detected (R6), a tab counting 4 columns; a blank line takes the smaller level of the nearest non-blank lines around it, so a guide runs through a block's blank lines and stops between two blocks. The guide of the caret's **innermost block** (the innermost fold region holding the caret's line, R26) is drawn in `textDisabled` over the lines strictly inside the block, at the column of the block's first line's indentation. A folded line draws none.
- R55 — **Matched brackets** (M21 21.9): the bracket just before the caret — else the one at the caret — and its pair are drawn on a tint of the accent; the pairs come from the syntax tree of R26's parse (an opener and its closer among the children of one node), so a bracket inside a string or a comment never matches. No grammar, no matching.
- R56 — **Sticky lines** (M21 21.11; 3 at most and only for languages with folding rules — decision 2026-10-16): the first lines of the fold regions (R26) the top of the editor is in — class, method, block — stay pinned over the text, outermost first, with their line numbers, on the editor's `surface` and a 1 pt `separator` under them; each slot is checked against the line it covers, so a block whose body no longer reaches below the pinned lines lets go of its line instead of covering its own end. A click on a pinned line scrolls it to the top. They replace a path bar under the tabs (`design` decision 2026-10-16).

### Problems (2026-10-16, M21 21.7, reference views 12 and 13)

- R50 — **A diagnostics store** keeps, per file, the last list a language server published (R40) — for every file the server speaks about, open in a tab or not (a project server such as `jdtls` reports the whole project); a publication replaces the file's list, an empty one clears it, closing a tab leaves it as the server last said it. Each list carries the server's name (its binary past a launcher: `xcrun sourcekit-lsp` is `sourcekit-lsp`). Errors and warnings are problems; information and hints are not counted nor listed.
- R51 — **The Problems panel** (`editor.problems`, the bottom slot's fourth tab, `layout` R2; its tab carries the number of problems, red with an error, orange otherwise): a scope *Current file* (the active tab's file) / *Project*, an error and a warning filter each showing its count for the scope, a message filter; then one group per file — its icon, name, folder and count; the files with an error first, then by path — each row the severity icon, the message, the server, `line:column`; the **Foreman config** group comes first in the *Project* scope, holding the config's errors (`config` R7) and the shortcut problems (`layout` R24). A click opens the file at the line, as a preview.
- R52 — The status bar's ⊗ / ⚠ counters (`layout` R39) are the active file's from the store, and the project's on a tab that is not a file; a click on them shows Problems on *Current file* (on *Project* when the active tab is not a file).

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
