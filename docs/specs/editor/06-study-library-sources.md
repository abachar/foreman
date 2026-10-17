# editor — Study: the sources of a library

> The seventh study of the `editor` domain ([00-study.md](00-study.md)), 2026-10-17. It **continues the rule numbering** and starts at **R61** (`R58`–`R60` are in [05-study-semantic-tokens.md](05-study-semantic-tokens.md)). It settles the two questions left open on R44 since 2026-08-31 ([`questions.md`](questions.md)): a definition outside the workspace, and a definition inside a dependency. The decisions and the questions stay in [`decisions.md`](decisions.md) and [`questions.md`](questions.md), shared across the domain.

## Goal

`cmd+click` on a class of a library opens its source — the real one when Maven has it, a decompiled one otherwise — in a tab the user can read but not edit. Today it opens nothing: `jdtls` answers no `Location` for a class in a jar because Foreman never told it the client can show one, and `sourcekit-lsp`'s answer for a type of another module is refused by R44 because it lies outside the workspace root. Both are the common case of a jump, not its edge ([`questions.md`](questions.md), 2026-08-31).

This study is the prerequisite of the `debug` domain ([`../debug/00-study.md`](../debug/00-study.md)): a stack frame inside a library names the same source, through the same URI, and lands in the same tab.

**Nothing of this study is written under the workspace root.** The author will commit `.foreman/` to share the config (2026-10-17), so a cache of decompiled classes cannot live there — it lives where macOS keeps caches.

## User stories

- *I `cmd+click` `ResponseEntity` in a controller and read Spring's source*, line numbers and highlighting included, with a title that says which jar it came from.
- *The jar has no sources*: I read a decompiled class — signatures, bodies, the decompiler's header saying so — rather than nothing.
- *I `cmd+click` a type of the Swift standard library or of a SwiftPM dependency* and read its `.swiftinterface` or its source under `.build/checkouts`, read-only.
- *I cannot type into it by mistake*: the tab is read-only, `cmd+s` does nothing, the formatter is not offered.
- *I close the window and reopen it*: the tab is back, like any other.

## Functional rules

### What the server is told, and what it answers

- R61 — Foreman declares to every language server, in `initializationOptions`, `extendedClientCapabilities: { classFileContentsSupport: true }` — the key `jdtls` reads before it produces a `jdt://` `Location` for a class file (`JDTUtils.toUri`, verified 2026-10-17 on the upstream source; without it the server answers `null`, which is what the author sees today). The key is added to the user's `settings` object of R57, which stays verbatim otherwise: Foreman's key is merged one level under `extendedClientCapabilities`, the user's own keys there kept. Every other server ignores it — the name is `jdtls`'s, no other reads `initializationOptions.extendedClientCapabilities`.
- R62 — A definition whose URI is not a `file:` URL is no longer dropped (R46 amended): when its scheme is one the server **announced it provides content for** — the server capability `workspace.textDocumentContent.schemes` of LSP 3.18, `["jdt"]` for `jdtls` 1.61 and later, which announces it precisely when the client declares no dynamic registration for it, as Foreman does not — Foreman asks `workspace/textDocumentContent { uri }` and receives `{ text }`. The request is bounded by `lsp.timeout` like the others (R43). Any other scheme stays dropped in silence, R46's rule. `jdtls` before 1.61 only knows the custom `java/classFileContents`; it is not supported — the brew formula is at 1.62 — and `config.md` says so.
- R63 — **The library tab.** The text is written to a cache file and opened as an ordinary `editor.file` tab, **read-only**:
  - the path is `<Caches>/Foreman/sources/<key>/<name>`, `<Caches>` being `FileManager.urls(for: .cachesDirectory, in: .userDomainMask)` (the platform's purgeable cache, never the workspace, never `.foreman/`), `<key>` the first sixteen hex digits of the SHA-256 of the URI, `<name>` the URI's last path component kept to `[A-Za-z0-9._-]` (`Foo.java`; the key carries the jar and the package, so two `Foo.java` never collide and no path component comes from the server's text);
  - the tab is `FileDocument.isReadOnly` from the start: no edit, no `cmd+s`, no formatter (R25's existing read-only refusal), no "modified on disk" since nothing watches the cache;
  - highlighting, folding, sticky lines, indent guides and the print margin work as on any file — they read the extension and the text;
  - **no `didOpen`, no language server** on the tab (R16's rule for a read-only file, applied here): a cache file is not part of the project, and a server told about it would answer with loose-file diagnostics. What a library tab loses — hover and `cmd+click` inside the library — is an open question (`questions.md`);
  - the title is the file name, with the jar's name after it (`Foo.java — spring-web-6.1.jar`), the file icon of design R23, and the tab is a preview (R2) like every definition;
  - persisted like any tab (R4): an absolute path is accepted by `Workspace.url(forPersistedPath:)` already; a cache purged by macOS makes the tab vanish at restoration, R4's "file gone" case — the next `cmd+click` writes it again.
- R64 — **A `file:` definition outside the workspace root opens too** (R44 amended, 2026-10-17): a `.swiftinterface` of the SDK, a source under `.build/checkouts` or `node_modules`, a JDK source attached by `jdtls`. The same read-only tab, on the file itself, no copy. The banner of R44 goes. The security rule of `architecture.md` guards *writes* and is untouched: such a tab never writes. The disk watch covers the root only, so a change on such a file is not seen — acceptable for a file nobody edits from Foreman (edge cases).
- R65 — **The sources themselves come from the server, never from Foreman.** `jdtls` downloads a Maven dependency's sources jar when `java.maven.downloadSources` is `true` (default `false`) and decompiles with the engine it ships (`java-decompiler-engine` from IntelliJ, Fernflower, the default since `jdtls` 1.25) otherwise; the decompiled text begins with the decompiler's own header. Foreman runs no `mvn`, bundles no decompiler, and the `config.md` example for Java gains the two keys (`java.maven.downloadSources`, `java.eclipse.downloadSources`) the user writes verbatim in `settings` (R57).

## Edge cases

- The server answers `{ text: "" }` or an error: the banner says `No source for <name>` and nothing opens.
- The same class clicked twice: the cache file is rewritten and the existing tab, if any, is shown rather than opened a second time (`Editor.open` already reuses a tab on the same path).
- A library tab in `state.json` whose cache file macOS purged: ignored at restoration (R4), no banner.
- An out-of-root file (R64) deleted since the tab was persisted: ignored at restoration, like any file gone.
- The explorer's *Reveal* on a library tab or an out-of-root tab (`explorer` R14): nothing to select, the action does nothing; the Finder reveal keeps working.
- A worktree's file outside the root (`git` R40) falls under R63's gate too: no `didOpen`, no reveal. The server runs at the root and saw such a file as a loose one already; the tree has no row for it. Accepted on 2026-10-17 (26.2) rather than a second rule for one case.
- `jdtls` names a class file `Foo.class` when no source name is attached: the cache name takes `.java` instead, so the tab is highlighted as Java (26.2).
- A `jdt://` definition while the server is restarting (R39): no server, no request, silence — the same as a definition today.
- The URI's last path component is empty or has no extension: `<name>` falls back to `Class.java`; highlighting follows the extension, so a fallback without one is plain text.

## Out of scope for v1

- `hover` and `cmd+click` **inside** a library tab (`questions.md`: `jdtls` accepts `didOpen` on a `jdt://` URI, which is how VS Code navigates from one library class to another).
- Breakpoints in a library source (`debug` R4 says so from its side).
- A picker between a sources jar and the decompiled text; `java.contentProvider.preferred` is the user's setting, verbatim.
- Asking the server to attach sources (`java/resolveSourceAttachment` and friends).
- Refreshing a library tab on `workspace/textDocumentContent/refresh`: the text of a jar does not change under the session.
- TypeScript's `.d.ts` under `node_modules` is covered by R64 without anything more; a definition into a bundled, minified file is a long line, R16's 10 000-character rule applies.

## Technical options

- **The request**: `LanguageServerProtocol` 0.14.1 has no `workspace/textDocumentContent` (it is LSP 3.18), but `ClientRequest.custom(method, LSPAny, handler)` sends any method with any params through the same `JSONRPCServerConnection`; the answer is decoded from `LSPAny` (`{ text }`). No dependency change, ~20 lines in `LSPServer`, next to `definition`. The server capability is read off `ServerCapabilities` as an `LSPAny` too (the typed struct predates the field).
- **The capability**: one line in `initializeParams` (`LSPServer`), merging Foreman's key into the user's `settings` — a pure function with a test (settings absent; settings with their own `extendedClientCapabilities`; settings with the key already set).
- **The tab**: `Editor.open(url, preview: true, line:)` as it is, after a `FileDocument` gains an explicit read-only mode (today it derives `isReadOnly` from the file's permissions and R16's size); the cache file can equally be written without write permission, which costs nothing and needs no new mode. `LSPServers.resolve` gains two cases next to `.found` and `.refused`: `.content(uri, scheme)` for R62 and `.found` outside the root for R64, and `EditorFeature+LSP.goToDefinition` fetches, writes, opens. ~120 lines with the tests.
- **The cache path**: `CryptoKit.SHA256`, `FileManager`, nothing else. The feature's one new type, `LibrarySource` (URI → cache URL, name, title), is a value with a static function, ~40 lines.
- **Rejected**: materialising under `.foreman/sources/` with its own `.gitignore` as the scratches do (decision 2026-08-30) — the author will commit `.foreman/`, and a decompiled jar has no business in a team's repository even ignored; a virtual tab kind holding the text without a file — a second text tab beside the editor, re-implementing restoration, highlighting and the gutter for one case the file tab already serves.

## Implementation order

One milestone, [M26](../../backlog/m26-library-sources.md): the capability and the request first (`jdtls` on `ccoe-backend` answers a `jdt://` location and its text, checked in the log), then the tab (R63, R64) — Swift's `.swiftinterface` through `sourcekit-lsp` on Foreman's own repository is the second check, it needs no install.
