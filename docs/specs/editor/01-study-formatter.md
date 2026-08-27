# editor — Study: formatting

> The second study of the `editor` domain ([00-study.md](00-study.md)). It **continues the rule numbering**: `R1`–`R23` are in the first study, this one starts at `R24`. The decisions and the questions stay in [`decisions.md`](decisions.md) and [`questions.md`](questions.md), shared across the domain.

## Goal

Format the active tab's file with the formatter the user already uses for that project, without leaving Wraith and without Wraith having an opinion on the style. One trigger: the explicit action (`cmd+shift+l`); formatting on save was dropped by the author on 2026-08-27 (decisions.md). This is an extension of the editor, **not a new domain**: no `Formatter/` folder, no new feature, no new panel.

This study lifts the "formatting" line from 00-study.md's out-of-scope list; everything else on that line (LSP, completion, diagnostics, go-to-definition) stays there.

## User stories

- US7 — I open a `.ts`, I type, `cmd+shift+l`: the file is reformatted by the project's `prettier`, my cursor stayed on the line I was on, and `cmd+z` undoes the whole formatting in one go.
- US8 — *(dropped 2026-08-27)* formatting on save: the author does not need it.
- US9 — The formatter is not installed, or refuses my file because it does not compile: I see its error output in the tab's banner and my text has not moved.
- US10 — I open a file whose extension has no declared formatter: `cmd+shift+l` tells me once and does nothing.

## Functional rules

### Triggering

- R24 — One entry point, and only one: the `editor.format` action (default `cmd+shift+l`, scoped to `tab(editor.file)` like the editor's other actions, R23) on the active tab. No formatting on save (dropped 2026-08-27, R31), on typing, on paste, or over a selection (out of scope).
- R25 — The formatter is chosen by **file extension**, in the `formatter` section of `.wraith/config.json` (`config` R3, R5):
  ```json
  {
    "formatter": {
      "timeout": 5,
      "swift": "swiftformat --quiet",
      "java": "clang-format --assume-filename=file.java",
      "ts": "npx --no-install prettier --stdin-filepath file.ts",
      "json": "npx --no-install prettier --stdin-filepath file.json",
      "md": "npx --no-install prettier --stdin-filepath file.md",
      "yaml": "npx --no-install prettier --stdin-filepath file.yaml",
      "py": "black -q -",
      "sql": "sqlformat -",
      "Dockerfile": "dockfmt fmt"
    }
  }
  ```
  An extension without an entry has no formatter: the action shows "no formatter for `.<ext>` in .wraith/config.json" once and does nothing; saving is neither blocked nor delayed. Keys are matched case-insensitively; a file without an extension (`Dockerfile`) is looked up by its full name. `timeout` (R30, seconds, 1…60, default 5) is the section's only reserved key; it is never read as an extension. A badly typed value or an empty command drops that entry with a warning, never the whole section (config R7).
- R26 — The command is **the user's text**, run as is by `$SHELL -l -c "<command>"` with the login shell's environment (`terminal` R3, `Workspace.loginEnvironment()`) and `cwd` = the file's folder. No interpolation: Wraith injects neither the path, nor the content, nor any variable into the command line (`architecture.md`, security; the same policy as `run` and `agents`).
- R27 — The text **from the view** (not the file on disk) is written to `stdin`, the formatted text is read from `stdout`, the diagnostics from `stderr`. Wraith gives the formatter no path: a command that needs the file name to pick its parser receives it in its own line (`--stdin-filepath file.ts`), written by the user.

### Applying

- R28 — The result is applied **only if** all three conditions hold: exit code `0`, non-empty `stdout`, and text different from the current one. Otherwise nothing moves and `stderr` (truncated) appears in the tab's banner. A formatter that writes its diagnostics to `stdout` with a non-zero code therefore cannot overwrite the file.
- R29 — The replacement happens in the text view as **a single undo operation**: `cmd+z` gives back exactly the text from before the formatting. The cursor position is preserved by **line and column** (clamped to the new text), the scroll is preserved, and the tab becomes `isDirty` (formatting is a modification like any other). A formatter that changed nothing gives no feedback at all: no banner, no beep (decision 2026-08-27).
- R30 — Bound: `formatter.timeout` seconds, default 5, clamped to 1…60 (decision 2026-08-27). Beyond that the process is stopped (`SIGTERM` then `SIGKILL`), the text stays unchanged and the banner says so. One execution at a time per tab; a second trigger while one is running is ignored (a beep), never queued.
- R31 — *(dropped 2026-08-27, number kept stable)* formatting on save. `cmd+s` writes the view's text as it is; the `formatter` section has no `onSave` key.
- R32 — Refused with its reason on a read-only file or one above the read-only threshold (R16, 2 MB), and on a markdown tab in `preview` mode (R14): there is no editable text to replace.
- R33 — The formatter receives no path and Wraith writes nothing for it: everything goes through `stdin`/`stdout`. If the user's command writes to disk itself, Wraith neither detects nor prevents it — it is their command, like a `run` (`run` R2).

## Edge cases

- **A formatter that exits non-zero on a warning**: `tidy` returns 1 when it merely warns, even though its output on `stdout` is valid. Under R28 (exit code `0` required) nothing is applied and the warnings appear in the banner. `format-all` handles this by accepting `(0 1)` for `tidy` alone; Wraith does not, in v1 — the remedy is to use `prettier` for HTML, which is the recommended entry anyway. See the open question in `questions.md`.
- Binary missing from the `PATH`: the command returns `command not found` on `stderr` and a non-zero code; on top of that, the first word of the command is looked up in the resolved `PATH` (like `agents` R2) so we can say "`prettier` not found in PATH" rather than repeating the shell's complaint.
- Syntactically invalid file: the formatters (prettier, black, rustfmt) exit with an error; R28 applies and the text does not move.
- A formatter that is slow on the first call (a JVM, an `npx` resolving a package): R30's 5 s bound may cut it off; the banner then offers to raise the bound (`formatter.timeout`, in seconds) or to install the binary locally.
- Line endings: the view's text is always LF (`FileDocument.decode` normalises, R3) and saving restores the CRLFs (R8). The formatter only ever sees and returns LF.
- Encoding: the text is sent as UTF-8; a file read as Latin-1 is already rewritten as UTF-8 on save (R3, edge cases) — formatting does not change that policy.
- A formatter returning identical text: nothing is applied, and the tab does not become `isDirty` (R28: different text required).
- File modified on disk during the formatting: the save that follows applies R10 (conflict detected, *Overwrite* / *Cancel*), unchanged.
- Two tabs on the same file in two groups: impossible within a group (R1), and each group formats its own text; the second will get the conflict banner on save (R10).

## Out of scope for v1

- Formatting a selection only, format on type, format on paste.
- Formatting several files, a folder or the workspace.
- LSP (`textDocument/formatting`), organising imports, fix-all, linting, diagnostics.
- Automatic detection of a project's formatter (`.prettierrc`, `pom.xml`, `.editorconfig`): the command is declared in the config, full stop — the same policy as `run` R1 (no automatic detection).
- Formatting the `git` diff (read-only, `git` R13) and `postgres`'s SQL editor (`postgres` R9): if the need appears, it will reuse the same config section.
- A formatter embedded in the app: see the technical options and the decision of 2026-08-27.

## Technical options

The point to settle is a single one: **an embedded library or an external binary**.

### The user's binaries, launched by `Process`

This is what Wraith already does for `run`, `agents` and `rg`: `$SHELL -l -c "<command>"` with the login shell's environment resolved once per window (`Workspace.loginEnvironment()`), `stdin`/`stdout`/`stderr` as `Pipe`s, running off the main actor.

**The contract is not ours, and it is not a guess.** `format-all-the-code` (`github.com/lassik/emacs-format-all-the-code`, maintained since 2017) does exactly this for around eighty languages, and its helper `format-all--buffer-easy` documents the contract in one sentence: *"Runs the external program EXECUTABLE. The program shall read unformatted code from stdin, write its formatted equivalent to stdout, write errors/warnings to stderr, and exit zero/non-zero on success/failure."* Read on the upstream repository on 2026-08-27: **102 formatter definitions**, and every one of them but a handful goes through that helper. That is R26–R28, word for word, validated across a far larger set of languages than Wraith highlights.

**Targeted first (author's decision, 2026-08-27)**: six formatters cover what the author's projects need, and the R25 example and the manual checks of M7 use them — **prettier** (CSS, GraphQL, JavaScript, JSON, JSON5, JSX, Less, Markdown, PHP, SCSS, Solidity, Svelte, TOML, TSX, TypeScript, Vue, YAML, Angular, Flow), **black** (Python), **clang-format** (C, C++, Cuda, GLSL, Java, Objective-C, Protocol Buffers), **dockfmt** (Dockerfile), **sqlformat** (SQL), **swiftformat** (Swift). Nothing in the code knows this list: the section accepts any command, so the other formatters of the inventory below work the same way when the author reaches for them.

Below, the recommended command for each grammar Wraith actually has (`editor` R11, plus `sql` in M5), with the invocation taken from `format-all.el` rather than from memory. `<recommended>` is one of the six targeted formatters when they cover the language; the alternatives are the other formatters `format-all` defines for the same language, kept for later.

| Wraith grammar | Extensions | Recommended command | Alternatives |
|---|---|---|---|
| java | `.java` | `clang-format --assume-filename=file.java` | `google-java-format -`, `astyle` |
| kotlin | `.kt`, `.kts` | `ktlint --log-level=none --format --stdin` (later: not one of the six) | — |
| typescript | `.ts`, `.mts`, `.cts` | `prettier --stdin-filepath file.ts` | `deno fmt --ext ts -`, `oxfmt --stdin-filepath stdin.ts`, `ts-standard` |
| tsx | `.tsx` | `prettier --stdin-filepath file.tsx` | `deno fmt --ext tsx -`, `oxfmt --stdin-filepath stdin.tsx` |
| javascript | `.js`, `.mjs`, `.cjs`, `.jsx` | `prettier --stdin-filepath file.js` | `deno fmt --ext js -`, `oxfmt --stdin-filepath stdin.js`, `standard` |
| json | `.json`, `.jsonc` | `prettier --stdin-filepath file.json` | `deno fmt --ext json -`, `oxfmt --stdin-filepath stdin.json` |
| yaml | `.yaml`, `.yml` | `prettier --stdin-filepath file.yaml` | `deno fmt --ext yaml -`, `oxfmt --stdin-filepath stdin.yaml` |
| toml | `.toml` | `prettier --stdin-filepath file.toml` (with `prettier-plugin-toml`) | `taplo fmt -`, `oxfmt --stdin-filepath stdin.toml` |
| markdown | `.md`, `.markdown` | `prettier --stdin-filepath file.md` | `deno fmt --ext md -`, `mdformat -`, `markdownfmt` |
| bash | `.sh`, `.bash`, `.zsh`, `.zshrc`… | `shfmt -ln bash` (later: not one of the six) | `beautysh -` |
| swift | `.swift` | `swiftformat --quiet` (nicklockwood's, the one `format-all` defaults to) | `swift format` (Apple's, ships with Xcode) |
| html | `.html`, `.htm` | `prettier --stdin-filepath file.html` | `tidy -q --tidy-mark no -indent` (**exits 1 on warnings**, see the edge cases), `deno fmt --ext html -` |
| css | `.css` | `prettier --stdin-filepath file.css` | `deno fmt --ext css -`, `oxfmt --stdin-filepath stdin.css` |
| dockerfile | `Dockerfile*` | `dockfmt fmt` | — |
| sql (M5) | `.sql` | `sqlformat -` (`format-all`'s default) | `pg_format`, `sqlfluff fix --nocolor --dialect=postgres -` |

#### Reference: the external formatters `format-all` knows, by language

The full inventory, supplied by the author on 2026-08-27, kept here **for the future**: a user adding a grammar to `formatter` in `config.json` has the candidate names at hand, beyond the six targeted first. Every entry is an external command driven over `stdin`/`stdout` and therefore fits R26–R28 as is, **except** the ones marked `*`, which are Emacs-internal modes (`Emacs`, `auctex`, `ledger-mode`) and have no CLI: those languages have no formatter Wraith can call. Only the rows whose grammar Wraith highlights (the table above) get a recommended invocation; the rest are names, not verified command lines.

| Language | Formatters |
|---|---|
| Angular | prettier |
| Assembly | asmfmt |
| ATS | atsfmt |
| Awk | gawk |
| AZSL | clang-format |
| Bazel Starlark | buildifier |
| Beancount | bean-format |
| BibTeX | Emacs* |
| C / C++ / Objective-C | clang-format, astyle |
| C# | clang-format, astyle, csharpier |
| Cabal | cabal-fmt |
| Caddyfile | caddy fmt |
| Clojure / ClojureScript | cljfmt, zprint |
| CMake | cmake-format |
| Crystal | crystal tool format |
| CSS / Less / SCSS | prettier, prettierd, deno, oxfmt |
| Cuda | clang-format |
| D | dfmt |
| Dart | dartfmt, dart format |
| Dhall | dhall format |
| Dockerfile | dockfmt |
| Elixir | mix format |
| Elm | elm-format |
| Emacs Lisp | Emacs* |
| Erb | erb-format |
| Erlang | efmt |
| F# | fantomas |
| Fish shell | fish_indent |
| Fortran (free form) | fprettify |
| GDScript | gdscript-formatter |
| GLSL | clang-format |
| Gleam | gleam format |
| Go | gofmt, goimports |
| GraphQL | prettier, prettierd, oxfmt |
| Haskell | brittany, fourmolu, hindent, ormolu, stylish-haskell |
| HCL | hclfmt |
| HLSL | clang-format |
| HTML | tidy, deno, oxfmt |
| XHTML / XML | tidy |
| Hy | Emacs* |
| Java | astyle, clang-format, google-java-format |
| JavaScript / JSON / JSX | prettier, standard, prettierd, deno, oxfmt |
| JSON5 | prettier, deno, oxfmt |
| Jsonnet | jsonnetfmt |
| Kotlin | ktlint |
| LaTeX | latexindent, auctex* |
| Ledger | ledger-mode* |
| Lua | lua-fmt, stylua, prettier (plugin) |
| Markdown | prettier, prettierd, deno, markdownfmt, mdformat, oxfmt |
| Meson | muon fmt, meson format |
| Nginx | nginxfmt |
| Nix | nixpkgs-fmt, nixfmt, alejandra |
| OCaml | ocp-indent, ocamlformat |
| Perl | perltidy |
| PHP | prettier (plugin) |
| Protocol Buffers | clang-format |
| PureScript | purty, purs-tidy |
| Python | black, isort, ruff format, yapf |
| R | styler |
| Racket | raco fmt |
| Reason | bsrefmt |
| ReScript | rescript format |
| Ruby | rubocop, rubyfmt, rufo, standardrb, stree (syntax_tree) |
| Rust | rustfmt |
| Scala | scalafmt |
| Shell script | beautysh, shfmt |
| Snakemake | snakefmt |
| Solidity | prettier (plugin) |
| SQL | pgformatter, sqlformat, sqlfluff |
| Svelte | prettier (plugin) |
| Swift | swiftformat |
| Terraform | terraform fmt |
| TOML | prettier (plugin), taplo fmt, oxfmt |
| TypeScript / TSX | prettier, ts-standard, prettierd, deno, oxfmt |
| V | v fmt |
| Vue | prettier, prettierd, oxfmt |
| Verilog | iStyle, Verible |
| YAML | prettier, prettierd, deno, oxfmt |
| Zig | zig fmt |

Two things this table settles, which are R27's whole point:

- **A formatter that infers its parser from the file name needs the name in its own command line**, because Wraith passes no path. `format-all` hits the same wall and solves it the same way — it appends `--stdin-filepath <file>` for prettier and oxfmt, `-assume-filename` for clang-format, `-filename` for shfmt, and falls back to `--parser <lang>` / `-ln <dialect>` when there is no file. In Wraith it is the user who writes that flag, once, in the config; the value is a placeholder name (`file.ts`), not the real path.
- **Some formatters take a subcommand, not a flag** (`taplo fmt -`, `deno fmt --ext md -`, `dockfmt fmt`, `sqlfluff fix … -`). That falls out for free: the config holds a shell command line, not a binary name.

Cost: ~80 lines (launching, `Pipe`s, the time bound, the decision to apply), plus decoding the section. No dependency added. Binary detection: `AgentCatalog.executables(among:inPath:)` (`Wraith/Agents/AgentCatalog.swift`) is already written, `static` and pure — it is called directly rather than copied; note that it looks up the **first word** of the command, so `npx --no-install prettier …` is detected as `npx`, which is correct.

### An embedded SPM library

Only one really exists and is maintained: **swift-format** (`github.com/swiftlang/swift-format`), a Swift.org project. Checked on the upstream repository on 2026-08-27: latest tag `603.0.0` (2026-06-30), a **library** product `SwiftFormat`, API `SwiftFormatter.format(source:assumingFileURL:selection:to:parsingDiagnosticHandler:)` — with a `Selection` parameter by offset ranges, so even formatting a selection would be free. It depends on `swift-syntax` (≥ 602), `swift-markdown` (already in the project) and `swift-argument-parser` (already resolved).

What it does not do: everything else. It only formats Swift, which is **one** of R11's fourteen grammars, and the author's typical project is in Java, Kotlin or TypeScript. For the other languages, no maintained Swift library exists: what exists are the binaries above, written in Rust, Go, Python or C++. Embedding swift-format would therefore mean **two mechanisms** — a library for Swift, binaries for the rest — and `swift-syntax` as a dependency, the heaviest one to compile in this project.

No other formatting library is proposed here: they do not exist, and `AGENTS.md` forbids citing one from memory.

### The rest

- **Applying the text**: `NSTextView.shouldChangeText(in:replacementString:)` then `replaceCharacters(in:with:)` then `didChangeText()` — the native way to make a modification undoable in one go, with the `NSUndoManager` already enabled (`allowsUndo = true`, `EditorTextView.swift`). Nothing to write.
- **Cursor position**: line and column recorded before, reapplied after with `TextEditing.location(ofLine:in:)` (`Wraith/Editor/TextEditing.swift`, already written for `cmd+l`), clamped to the new text.
- **Tests**: decoding the `formatter` section (the `timeout` key is reserved, unknown extension, badly typed value), choosing the command by extension, deciding whether to apply (code, empty `stdout`, identical text), carrying the cursor position over (line/column, including a line that disappeared and a shortened file), building the invocation. No test launches a formatter (`coding-rules`: hermetic).

## Decisions

See [decisions.md](decisions.md).
