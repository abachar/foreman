# editor — Study: LSP (diagnostics, hover, go-to-definition)

> The fourth study of the `editor` domain ([00-study.md](00-study.md)), 2026-08-31. It **continues the rule numbering** and starts at **R35**: `R1`–`R23` are in the first study, `R24`–`R33` in [01-study-formatter.md](01-study-formatter.md), `R26`–`R28` in [02-study-folding.md](02-study-folding.md) (those three numbers are used twice — a collision recorded in [`questions.md`](questions.md), numbers kept stable), `R34` in the first study. The decisions and the questions stay in [`decisions.md`](decisions.md) and [`questions.md`](questions.md), shared across the domain.

## Goal

Give the editor the three things a language server provides that tree-sitter structurally cannot: **the errors, the types, and where a symbol is defined**. tree-sitter parses one file's syntax (R12) — it knows nothing of types, imports or the other files in the project. Everything semantic comes from a language server.

This study lifts **three items** from 00-study.md's out-of-scope list (R13's neighbours: *LSP, completion, diagnostics, go-to-definition*): diagnostics, hover and go-to-definition. **Completion stays out**, on purpose and for good — see *Out of scope*. Like formatting, this is an extension of the editor, **not a new domain**: no `LSP/` feature folder, no new panel, no new tab kind. The client lives in `Editor/`.

### Why now

The editor was scoped as deliberately simple on 2026-08-25 (`decisions.md`): *"a simple editor: typing, undo, indentation, find/replace, `cmd+s`; no completion and no LSP"*, on the premise that Foreman is where you touch a README or a config and most code is written elsewhere or through an agent. A panel of testers, 2026-08-31, invalidated that premise: they edit code in Foreman and they miss the semantics. The premise changed, so the decision changes; the *shape* of the decision does not — we take the third of LSP that carries the value, not the whole protocol.

## User stories

- US11 — I open a `.swift`, I mistype a name: the line is underlined in red within a second and the message is there when I point at it, without going to build.
- US12 — I point at a symbol I did not write: a popover gives me its signature and its doc comment.
- US13 — `cmd+click` on a function call: its declaration opens in a preview tab, at the right line, in the same group.
- US14 — I have no language server installed for `.kt`: nothing is underlined, nothing is offered, nothing breaks, and Foreman tells me once why.

## Functional rules

### The server

- R35 — Servers are **declared, never detected**, in the `lsp` section of `.foreman/config.json` (`config` R3, R5) — the same policy as `run` R1 and `formatter` R25, and the same decoding shape as `FormatterCatalog`:
  ```json
  {
    "lsp": {
      "timeout": 10,
      "swift": "xcrun sourcekit-lsp",
      "java": "jdtls -data /Users/me/Projects/shop/.foreman/jdtls",
      "ts": "typescript-language-server --stdio",
      "tsx": "typescript-language-server --stdio",
      "js": "typescript-language-server --stdio",
      "html": "ngserver --stdio --ngProbeLocations node_modules --tsProbeLocations node_modules"
    }
  }
  ```
  A value is the command, or `{ "command": …, "cwd": … }` when the server must not run at the root — **amended 2026-08-31**: a repository is not always a project. `typescript-language-server` looks for the `typescript` it needs from its own `cwd`, and a monorepo keeps that under `server/`; the object form is the one `run` R2 already uses. The `cwd` is relative to the workspace root and must stay under it (`architecture.md`, security): a path that escapes, or that is not a folder, disables that entry with a banner naming it.

  The key is an extension, or a whole file name when there is none, matched case-insensitively. `timeout` (R39, seconds, 1…60, default 10) is the section's only reserved key and is never read as an extension. A badly typed value or an empty command drops **that entry** with a warning, never the whole section (`config` R7). An extension with no entry has no language server: no banner, nothing offered, `cmd+click` does nothing.
- R36 — **One server process per (command × `cwd` × workspace root)**, so two extensions naming the same command (`ts`, `tsx`) share one process — and two projects of one repository naming the same binary in two folders (`server/`, `client/`) get two, each resolving its own dependencies (amended 2026-08-31, R35's `cwd`). The process runs in that `cwd`, and it is what `rootUri` announces. It is started **lazily**, at the first `editor.file` tab whose extension resolves to it (P4 — nothing costs anything before it is used), and stopped when the last such tab closes or the window closes. Startup is `initialize` (with `rootUri` = the workspace root and the capabilities of R38–R39) then `initialized`; shutdown is the `shutdown` request, then the `exit` notification, then `SIGTERM` past `lsp.timeout` and `SIGKILL` one second later — `formatter` R30's ladder, which is already written in `FormatterLaunch`.
- R37 — **Document synchronisation is `full`**: every change sends the whole text, debounced ~150 ms, never a delta (decision 2026-08-31 — see the technical options). The truth is the text **of the view**, never the file on disk (`formatter` R27's rule): `didOpen` with version 1 when the tab opens, `didChange` with version + 1 on each debounced change, `didClose` when it closes, `didSave` on `cmd+s` only if the server asked for it in its sync options. Formatting (R29), folding (R26–R28) and a reload from disk (R9) are ordinary changes and go through the same path — nothing in them knows about LSP.
- R38 — **Positions are UTF-16.** That is LSP's default and Foreman announces nothing at all — **amended 2026-08-31, task 18.1**: the study said the client would send `general.positionEncodings: ["utf-16"]`, but `LanguageServerProtocol` models no such capability, and the specification is explicit that a client silent on it is a UTF-16 client. Announcing nothing is therefore the same contract with less code. Either way the unit is convenient rather than costly: UTF-16 code units are exactly what `NSString` and `NSRange` count. The conversion is a pure pair of functions living beside `TextEditing.position(at:in:)` / `location(ofLine:in:)`, and nothing in the feature ever holds a `String.Index`.
- R39 — **Nothing is offered that the server did not announce**, and every failure degrades — R13's policy, applied to a process instead of a grammar. The UI reads the `initialize` result: no `hoverProvider`, no popover; no `definitionProvider`, no `cmd+click`. Binary missing from the `PATH` (checked with `FormatterCatalog.isBinaryAvailable`, which is already `static` and pure), a server that fails to start, that crashes, or that does not answer `initialize` within `lsp.timeout` → the three features are simply absent, one message in the tab's banner (`EditorTab.message`), a `debug` log, no modal and no crash (P5). The banner **closes by hand** (amended 2026-08-31): the formatter's verdict goes at the next keystroke (R28), a server's refusal has no keystroke to wait for. **Amended 2026-08-31**: the banner carries the server's own words — its last line of `stderr`, or, when it wrote none, the message it answered `initialize` with. A server that refuses on purpose says so **in the protocol**, not on `stderr`: `typescript-language-server` answers *"Could not find a valid TypeScript installation"* and exits, and swallowing that with a `try?` cost two rounds of guessing. `stderr` wins when there is any, a dying process throwing a transport error that says nothing useful. A server that cannot start almost always says why in one line — a missing flag, a bad node version, a project it cannot read — and that line is worth more than anything Foreman can infer from the outside; `typescript-language-server` without `--stdio` exits at once with the exact reason, and "stopped twice" was what the author saw instead. A server that crashes is restarted **once**; a second crash leaves that language without LSP until the window is reopened — **and the banner says so** (amended 2026-08-31): the login environment is resolved once per window too (`terminal` R3), so a user who has just fixed their `PATH` sees no change until they reopen it, and there is no way to guess that from "no LSP for this language".

### Diagnostics

- R40 — Diagnostics **arrive unasked**: `textDocument/publishDiagnostics` is a notification the server sends when it decides to, sometimes several times per keystroke, sometimes seconds after the last one. A batch is dropped when its `version` is not the tab's current version, and when its URI has no open tab. Nothing is ever requested; nothing waits for them.
- R41 — Rendering, three surfaces and no fourth: a **wavy underline** on the range, coloured by severity (`error` / `warning` / `information` / `hint` → `statusRed`, `statusOrange`, `statusBlue`, `textSecondary` — **amended 2026-08-31, task 18.3**: the study called for four new `ThemeService` roles, and the status colours the app already defines say exactly these four things, `design` R6); a **dot in the gutter** on each line carrying one, drawn by `LineNumberRulerView`, which already draws the line numbers (R6) and the folding chevrons (R27); and the **message in the popover of R42** when the pointer is on the range. No diagnostics panel, no problem list, no count in the tab title, no *next error* navigation in v1 — to be reconsidered from use (`questions.md`).

### Hover

- R42 — `textDocument/hover` at the pointer's position after **~300 ms without movement**, cancelled by any movement, keystroke or scroll, at most one request in flight per tab. The response's `contents` is markdown and is rendered by what already renders markdown — `MarkdownBlocks.make` and the preview views (R14) — including its rule about the network: **nothing is fetched**, no remote resource, ever (`architecture.md`, security). One popover component, two sources: a diagnostic's message when the pointer is on a diagnostic range, the hover otherwise; when both apply, the diagnostic comes first in the same popover.

### Go-to-definition

- R43 — `textDocument/definition` from **`cmd+click`** on a symbol and from the `editor.goToDefinition` action (default `ctrl+cmd+j`, Xcode's key, free in `shortcuts.md`; scope `tab(editor.file)` like the editor's other actions, R23). The request is bounded by `lsp.timeout` like the handshake — **amended 2026-08-31, task 18.1**: the study bounded only `initialize`, but a server that never answers would otherwise leave a request pending for the session; `cmd+click` does nothing instead. The result is opened through the **existing** `Editor.open(path, preview:, newGroup:, line:)` (R3), the same call the git diff already uses to land on a line — so the arrival costs nothing new. Several results (`Location[]` / `LocationLink[]`) → the first one, in the order the server gave; no picker in v1. Underlining the symbol under `cmd`-hover is out of scope.
- R44 — A definition **outside the workspace root** (an SDK header, a `.swiftinterface` under `DerivedData`, something in `node_modules`) is **not opened** in v1: the banner says where it is and nothing else happens. This is a product choice, not a constraint — `architecture.md`'s path rule guards *writes*, not reads — and it is the choice with the smallest blast radius: a tab on a path outside the root would have to be handled by restoration (R4), the disk watch (R9) and the explorer, none of which expect it. To be revisited if it turns out to be the common case for Swift (`questions.md`).

### Transverse

- R45 — **Typing does no synchronous work** — `architecture.md`'s budget is unchanged. Encoding, decoding, the debounce and every range computation happen off the main actor; attributes are applied in one batch on the main actor, as Neon already does (R12). Every request is cancellable and its answer dropped when the text has moved on: a slow server can make a feature late, never the keystroke.
- R46 — **Security.** The command is the user's text, run by `$SHELL -l -c "<command>"` with the login environment (`Workspace.loginEnvironment()`) and `cwd` = the workspace root, nothing interpolated — `formatter` R26 word for word, and the same policy as `run` and `agents`. What a server sends back is **untrusted displayed content** (`architecture.md`): hover markdown renders as text and triggers nothing, and a `Location`'s URI is validated as a `file:` URL before anything is opened.

## Edge cases

- **A server that never answers `initialize`** (a `jdtls` indexing a large project, a `gopls` downloading modules): R39's `lsp.timeout` cuts it off, and the banner offers to raise it — the same remedy as the formatter's slow first call.
- **The file is `isDirty` and the server indexes from disk.** Under R37 the server's copy is the view's text, so diagnostics match what is on screen; but a server that reads *other* files from disk (all of them do) will report on the saved versions of the neighbours. Nothing to do about it, and it is what every editor does.
- **Two tabs on the same file in two groups**: impossible within a group (R1), so two groups mean two `didOpen` on one URI. The client keeps **one** open document per URI with a reference count, and the text is the one of the tab that last changed — the two views hold the same text anyway (R1's per-group independence only matters once one of them is edited, and then the diagnostics follow the last edit).
- **A file above the read-only threshold** (R16, 2 MB) or a binary (R15): no `didOpen`, no server, like highlighting.
- **A markdown tab in `preview` mode** (R14): there is no text view to underline; `didOpen` still happens if a server is declared for `.md`, and the features reappear in `source` mode.
- **A scratch / untitled tab** (R34): its path is real (`<root>/.foreman/scratches/Untitled`), so a server starts if the extension matches — it will have little to say about a file with no extension, which is the normal case.
- **A file outside the workspace root** opened by an absolute path (R1): its URI is outside `rootUri`; the server is free to refuse it, and R39's degradation covers the refusal.
- **`git` diff tabs and the `postgres` query editor**: no LSP. They are not `editor.file` tabs, and the diff is read-only (`git` R13).
- **Line endings and encoding**: the view's text is always LF (R3) and is sent as UTF-8; the server never sees the CRLFs that saving restores (R8).
- **A server that needs per-project state on its command line.** `jdtls` (Java) requires `-data <dir>`, and two projects sharing one data directory corrupt each other. R35 forbids interpolation, so Foreman cannot fill that path in — and does not have to: `.foreman/config.json` is **already per workspace** (`config` R1), so the absolute path is written once, by hand, in the config of the project it belongs to. The rule holds with no exception; this is a consequence of config-per-workspace that the section's design did not have to plan for.
- **A language wanting two servers at once.** An Angular project is the case: `typescript-language-server` for the TypeScript of a `.ts`, and `ngserver` for the Angular semantics of the same `.ts` (inline templates, bindings) — both, in every editor that supports Angular properly. R35 maps one extension to **one** command, so v1 cannot do it: the workaround is `typescript-language-server` on `.ts`/`.tsx`/`.js` and `ngserver` on `.html`, which keeps the template diagnostics and loses only the Angular part of the inline templates. Accepting an array of commands later is backwards compatible (a string stays a valid value), so nothing is painted into a corner — see `questions.md`.
- **The server writes to `stderr`** (most do, copiously): read and dropped into a `debug` log, never the banner. Only R39's lifecycle failures reach the user.

## Out of scope for v1

- **Completion** — `textDocument/completion` and `completionItem/resolve` are not implemented and not requested. This is the deliberate core of the study: completion is the heaviest part of a client (deferred resolution, snippets with placeholders, client-side filtering and ranking, re-triggering on characters, `isIncomplete` round trips) and the author wants completion to come **from the AI**, as ghost text, in its own study (decision 2026-08-31). The two do not collide: LSP owns the underline, the gutter and the popover; the AI owns the inline grey text and `tab`. Feeding one with the other (hover's real types as context for the model) is a v2 idea, deliberately not designed here.
- **A server for `json`, `yaml`, `toml`, `sql` and `css`** (author's call, 2026-08-31 — `decisions.md`): no LSP on data and config files. `sql` is refused on its own merits (`postgres` already reads the schema through `pg_catalog`), `taplo`'s LSP ships neither in its default builds nor in its npm install, and `css` is refused because the thing actually wanted — `cmd+click` on a class reaching its rule — **is not LSP at all**: it is [04-study-selectors.md](04-study-selectors.md).
- Rename, find references, code actions / quick fixes, formatting through `textDocument/formatting` (M7 already formats, through binaries, `01-study-formatter.md`), signature help, document symbols / outline, semantic tokens (tree-sitter already colours, R12), inlay hints, call hierarchy, workspace symbols.
- Multi-root workspaces, `workspace/didChangeWatchedFiles` (Foreman has its own watch, `FSWatchService`), progress reporting, `window/showMessageRequest`.
- Automatic discovery of a project's language server (`package.json`, `Package.swift`, a `.lsp` file): declared in the config, full stop — `run` R1's policy.
- A diagnostics panel, an error count in the tab bar, *next / previous error* navigation (R41).
- LSP in the git diff and in the Postgres SQL editor.

## Technical options

The framing (`Content-Length` headers over stdio), the sixty-odd message types and the lifecycle are three separable problems, and the answer is different for each.

### The dependency — what to take from ChimeHQ

Three packages by the same author as **SwiftTreeSitter** and **Neon**, both already retained (`architecture.md`). Read on the upstream repositories on **2026-08-31**:

| Package | Latest release | Dependencies | Manifest |
|---|---|---|---|
| `JSONRPC` | — | **none** | `swift-tools-version: 5.8`, `StrictConcurrency` experimental |
| `LanguageServerProtocol` | `0.14.1` (2026-04-29) | `JSONRPC` only | `swift-tools-version: 5.8`, `StrictConcurrency` experimental |
| `LanguageClient` | `0.8.2` (2025-06-04), last commit 2025-06-04 | `LanguageServerProtocol`, `JSONRPC`, `FSEventsWrapper`, `swift-glob`, `ProcessEnv`, `Semaphore`, `Queue` | `swift-tools-version: 5.9`, `StrictConcurrency` experimental |

**Retained: `LanguageServerProtocol` (which pulls `JSONRPC`), not `LanguageClient`.** The first two are exactly the part that would be foolish to write — the framing, the ~60 typed messages, `Snippet`, `MockServer` for the tests — and they cost **two** dependencies with no transitive fan-out. `LanguageClient` adds `InitializingServer` (the `initialize` handshake) and `RestartingServer` (restart after a crash), which is R36 plus R39's single restart, perhaps 120 lines here; it charges **five more dependencies** for them, one of which (`FSEventsWrapper`) is a second FSEvents wrapper next to the `AsyncFileMonitor` already retained, and its last commit is fifteen months old while `LanguageServerProtocol` shipped four months ago. That is the case `AGENTS.md` describes: use the library for what it does well, do not take a wrapper whose cost is larger than what it wraps.

One consequence to plan for: both packages are Swift 5 modules with strict concurrency *enabled experimentally*, not Swift 6 language mode. Their types cross into a Swift 6 app with `Sendable` gaps at the boundary — which is precisely why `architecture.md` already says third-party types stay near their use: the client converts LSP types to Foreman's own at the edge of `Editor/`, and no view or persisted model ever holds a `Diagnostic` or a `Location`.

### The process

New ground: a **long-lived** child process with pipes, where `FormatterLaunch` runs one-shot commands and `TerminalLaunch` hands a PTY to SwiftTerm. Neither fits, and neither should be bent to fit — `Process` with two `Pipe`s, an `AsyncStream` over stdout feeding `JSONRPC`'s `DataChannel`, and the shutdown ladder of R36. About 80 lines, off the main actor.

The rest is reuse, and that is the point of the shape chosen: `FormatterCatalog` for the config section, `FormatterCatalog.isBinaryAvailable` for the PATH check, `Workspace.loginEnvironment()` for the environment, `LineNumberRulerView` for the gutter, `MarkdownBlocks` for the hover body, `Editor.open(…, line:)` for the jump, `EditorTab.message` for the banner, `TextEditing`'s line/column helpers for R38.

### The four servers targeted first (author, 2026-08-31)

The author's projects today are **Java, React, Angular and Swift**; those four are what the milestone is built and checked against. Nothing in the code knows this list — the section takes any command (R35) — but it is what the recommendations and M18's manual checks use. Read on the upstream repositories and on npm on **2026-08-31**:

| Language | Server | Command | Installation | State |
|---|---|---|---|---|
| Swift | **sourcekit-lsp** (swiftlang) | `xcrun sourcekit-lsp` | **nothing to install** | ships inside the selected Xcode 27 — verified on this machine, `xcrun --find` resolves it in the toolchain. `xcrun` is the right prefix precisely because it follows the selected Xcode (`AGENTS.md`) |
| React (TS/TSX/JS) | **typescript-language-server** | `typescript-language-server --stdio` | `npm i -g typescript-language-server typescript` | standard, no special case; `.tsx` is native |
| Angular | **@angular/language-server** (`22.1.4`), binary `ngserver` | `ngserver --stdio --ngProbeLocations <dir> --tsProbeLocations <dir>` | `npm i -g @angular/language-server` | `--ngProbeLocations` and `--tsProbeLocations` are **required** (the paths of `@angular/language-service` and of `typescript`, normally `node_modules`); the exact transport flag is `vscode-languageserver`'s, to confirm with `ngserver --help` when the task is done. Gives the templates, which `typescript-language-server` does not — and wants to run **beside** it, not instead of it (see the edge cases and `questions.md`) |
| Java | **eclipse.jdt.ls**, wrapper `jdtls` | `jdtls -data <dir per project>` | a Java **21** runtime minimum; the wrapper avoids a twelve-flag `java -Declipse.application=…` line | mature, and the slowest to start: the `lsp.timeout` of R39 will be met here first. Maven and Gradle |

Also present on this machine and useful as a **second opinion** during development: `rust-analyzer` (`~/.cargo/bin`). It is fast and implements everything, so it catches a client coded against one server's quirks. Not part of the targeted four.

### Order of implementation

`server + sync` → `go-to-definition` → `diagnostics` → `hover`, each a commit that builds, developed against **sourcekit-lsp** — it needs no installation, it is always there, and Foreman is itself a Swift project, so the client is exercised on the code being written. Definition first although it is the least valuable: it exercises the whole chain end to end with the least new UI, and a position bug is visible immediately — you land on the wrong line. Diagnostics second, being the reason the testers asked. Rough sizes: the server and the sync ~350–450 lines plus the config section, definition ~100, diagnostics ~200, hover ~150.

### Tests

Hermetic (`coding-rules`): **no test launches a language server**. Decoding the `lsp` section (reserved `timeout`, unknown extension, badly typed value, two extensions sharing a command); the `NSRange` ↔ `Position` conversion both ways, including astral characters, an empty last line and an out-of-range position; the version filter on a diagnostics batch; the capability gate (a server announcing nothing offers nothing); the open-document reference count across two groups; building the invocation. `LanguageServerProtocol` ships a `MockServer` for the request-level tests.

## Decisions

See [decisions.md](decisions.md).
