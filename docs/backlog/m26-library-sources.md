# M26 — The sources of a library

Eleventh round driven by use (2026-10-17), after [M25](m25-intellij-highlighting.md), and the prerequisite of [M27](m27-debug.md): `cmd+click` on a class of a Maven dependency opens nothing, `cmd+click` on a type of the Swift standard library shows a banner. The two questions left open on `editor` R44 since 2026-08-31 are settled by one tab: a **read-only tab** on a source Foreman did not write — the server's text for a class in a jar (real sources when Maven has them, decompiled otherwise), the file itself for a `file:` definition outside the root.

Domain: [`editor`](../specs/editor/) — [`06-study-library-sources.md`](../specs/editor/06-study-library-sources.md) (R61–R65; R44 and R46 amended). No new folder, no dependency (`ClientRequest.custom` of `LanguageServerProtocol` carries the 3.18 request).

**Nothing is written under the workspace root**: the author will commit `.foreman/` to share the config, so the cache of a decompiled class lives in `~/Library/Caches/Foreman/sources/` (R63), the platform's purgeable cache.

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Tasks

One branch `feat/m26` from `main`, one commit per task. Nothing starts before the author's go.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 26.1 | **The capability and the request**: `extendedClientCapabilities.classFileContentsSupport: true` merged into `initializationOptions` one level under the user's `settings` (R61); the server's `workspace.textDocumentContent.schemes` read off the capabilities (an `LSPAny`, the typed struct predates LSP 3.18); `LSPServers.resolve` keeps a `Location` whose scheme the server provides instead of dropping it (R62, R46 amended) and `LSPServer` asks `workspace/textDocumentContent { uri }` through `ClientRequest.custom`, bounded by `lsp.timeout`, decoding `{ text }`. **No UI**: the log says `jdtls` answered a `jdt://` location for `ResponseEntity` on `ccoe-backend` and its text. `config.md`'s Java example gains `java.maven.downloadSources: true` and `java.eclipse.downloadSources: true` and says `jdtls` 1.61 or later (R65) | editor R61, R62, R65, R57 | `LanguageServerProtocol` (`ClientRequest.custom`, `LSPAny`), `JSONRPCServerConnection` | the merge of Foreman's key into `settings` (absent; with its own `extendedClientCapabilities`; with the key already there); `resolve` on a `jdt://` URI the server provides, on one it does not, on a `file:` URI; the `{ text }` decoding (a text, an empty text, an error); no server launched | S | ⚪ | |
| 26.2 | **The library tab** (R63) **and the out-of-root tab** (R64, R44 amended): a `LibrarySource` value (URI → `<Caches>/Foreman/sources/<16 hex of SHA-256>/<name>`, `<name>` kept to `[A-Za-z0-9._-]`, the jar's name for the title) writes the text without write permission and opens it through the existing `Editor.open(url, preview: true, line:)`; `FileDocument.isReadOnly` holds, so `cmd+s`, the formatter and the edit are already refused; **no `didOpen`** on a tab outside the root (R16's read-only rule), highlighting, folding, sticky lines and guides unchanged; a `file:` definition outside the root opens the same way on the file itself, the R44 banner removed; the title `Foo.java — spring-web-6.1.jar` and the file icon (design R23); restoration through the absolute path `Workspace.url(forPersistedPath:)` already accepts, a purged cache ignored (R4); the explorer's reveal doing nothing for such a tab (`explorer` R14). `questions.md`'s two R44 items closed, `decisions.md` dated | editor R63, R64, R44, R46, R4, R16, R2, design R23 | `FileManager` (`.cachesDirectory`, attributes without write permission), `CryptoKit.SHA256`, the existing `Editor.open`, `FileDocument` | the cache path (two URIs with the same file name differ; a name with `/`, `..`, `(`; an empty name); the title; the read-only document on a file without write permission; `resolve` outside the root now `.found`; a persisted library tab whose file is gone is ignored; no server launched | M | ⚪ | |

## Definition of done

- On `ccoe-backend`, `cmd+click` on `ResponseEntity` opens `ResponseEntity.java — spring-web-<version>.jar`, read-only, highlighted, with Spring's real source once `java.maven.downloadSources` is on, and a decompiled one with the Fernflower header before.
- On Foreman's own repository, `cmd+click` on `String` opens `Swift.swiftinterface` read-only; on `Neon`'s `TextSystemInterface` the source under `.build/checkouts` (through `xcode-build-server`, editor questions 2026-08-31).
- Typing into either tab does nothing; `cmd+s` is refused; closing and reopening the window brings the tab back.
- `git status` of `ccoe` shows nothing new: no file under the root, nothing under `.foreman/`.
- Tests pass; `swift format lint --strict` passes.

## Decisions to take during the milestone

- Whether an out-of-root `file:` tab (R64) should be watched by a second `FolderContentMonitor` on its folder, or stay unwatched (the study says unwatched; to confirm the first time a `.swiftinterface` changes under a session — it should not).

## Out of scope for this milestone

- Hover and `cmd+click` inside a library tab (`editor` questions.md).
- Breakpoints in a library source (M27, `debug` questions.md).
