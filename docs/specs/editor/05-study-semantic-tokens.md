# editor — Study: semantic tokens

> The sixth study of the `editor` domain ([00-study.md](00-study.md)), 2026-10-17 (M25 25.2). It **continues the rule numbering** and starts at **R58**; R35–R46 and R50–R52 are in [03-study-lsp.md](03-study-lsp.md), R57 too.

## Goal

Colour code the way IntelliJ does where a grammar cannot: a **field** is purple wherever it is written, a **declaration** is coloured and a **use** is not, a **deprecated** symbol is struck through. tree-sitter (R12) sees syntax — it knows an identifier, not whether it names a field, a parameter or a local — and Foreman's own Java query (R12, amended 2026-10-17, M25 25.1) already took that as far as a grammar goes: a field is purple behind a dot, and plain text when written bare in a method body. The language server knows the rest: `textDocument/semanticTokens` gives, for every identifier, its **type** (`property`, `parameter`, `variable`, `method`, `class`…) and its **modifiers** (`declaration`, `static`, `deprecated`…). That is exactly the information IntelliJ paints with.

### Why now

The author reads Java in IntelliJ all day and compared two screenshots of one file (2026-10-17): the palette was already IntelliJ's, the line height and the base text were fixed the same day (25.3), and what remained was the bare field in a method body — the purple that says "this is state, not a local" — which no query can give.

## User stories

- US15 — I open a Java service: its fields are purple in the declarations **and** in the method bodies, its parameters and locals plain, within the second the server takes to answer.
- US16 — I call a method marked `@Deprecated`: the call is struck through, in the same colour it would have had.
- US17 — I type: the colours of tree-sitter follow the keystroke; the server's refinement comes back a moment later and changes only what it disagrees with — nothing flashes.
- US18 — My server does not do semantic tokens (or I have none): the editor looks exactly as it did before this study.

## Functional rules

- R58 — **The request and its cadence.** A server announcing `semanticTokensProvider` in its `initialize` result is asked `textDocument/semanticTokens/full` once the document is open (`didOpen`, R37) and again after every `didChange`, behind R37's debounce — the text and the request go together, so the server answers about the text Foreman sent. When the provider offers `full.delta`, the request after the first is `…/full/delta` with the last `resultId`, and the answer's edits are applied to the previous data (R45: off the main actor); a full answer replaces it. An answer is **dropped when stale** — R40's rule: the document's version moved on while the server worked. Foreman announces `textDocument.semanticTokens` with `requests.full.delta`, the relative format, no overlapping and no multiline tokens (a token that crosses a line is cut at the line's end by the decoder), and the standard type and modifier lists; the server's **legend** names its own types and modifiers, which may exceed the standard ones (jdtls: `annotation`, `annotationMember`, `record`, `recordComponent`, `modifier`), and the decoder reads the legend, not the standard list. No `range` request: the whole file, once per change, is cheaper than tracking the viewport for files of `ccoe`'s sizes (P95 49 KB). A server that does not announce the provider is asked nothing (R39).
- R59 — **One layer, and the provider answers.** Neon already colours every token tree-sitter captures and re-applies its attributes on each invalidation; a second pass over the same text would be overwritten at the next keystroke. So the server's tokens live beside the tab (`SemanticTokenStore`, one per text view) and the tab's **attribute provider** consults them: where a semantic token covers the token Neon is styling, it answers with the semantic role (R60) instead of the capture's; elsewhere the capture's colour stands. When a batch arrives, only the ranges whose token **changed** — added, removed, or another role — are invalidated, so Neon asks again for those and nothing else (US17). A consequence written into the queries: **every identifier must be a tree-sitter token**, captured or not, or Neon never asks about it — Foreman's Java query captures `(identifier)` and `(type_identifier)` as `variable` (the code's own text, R12 / design R9: visually plain) for that reason, and the server's say overrides it. Before the first answer, and for a language with no server, the editor is tree-sitter's alone (US18).
- R60 — **What a token becomes.** The roles are R12's; nothing new in the theme. By type: `property`, `recordComponent`, `annotationMember` → `property`; `enumMember` → `constant`; `variable` and `parameter` → plain (`variable`, the code's text), except a `variable` that is both `static` and `readonly` → `constant` (IntelliJ's static final); `method`, `function`, `macro` → `function` when the token is a `declaration` or a `definition`, plain otherwise (IntelliJ colours the declaration, never the call); `class`, `interface`, `enum`, `struct`, `type`, `typeParameter`, `record` → `type` when declared, plain when used; `annotation` → `attribute`; `namespace` → plain; `keyword`, `modifier` → `keyword`; `string`, `regexp` → `string`; `number` → `number`; `comment` → `comment`; `operator` → `operator`; any other type → **no opinion**, the capture's colour stands. By modifier: `deprecated` → a strikethrough in the token's colour. **Not** done, with its reason: IntelliJ's *italic for `static`* — Neon colours TextKit 2 through **rendering attributes**, which can change a colour, an underline or a strikethrough but not the font (a font change relayouts, rendering attributes by definition do not), and a second font pass would fight R59's one layer. Recorded in [questions.md](questions.md).

## Edge cases

- A server that answers `null` (no tokens yet, jdtls during its import): nothing changes, the next `didChange` asks again.
- A delta whose `previousResultId` the server no longer knows: it answers a full result, which R58 takes as is.
- A token past the end of the text (the server is behind): clamped to the text, a zero-length one dropped.
- A document shown in two groups (R1): one store per text view, both fed by the same answer (the route goes through `tabsShowing`, like diagnostics).
- The `lsp` section changes under an open file (R36): the servers are re-keyed, the documents reopened, the store cleared by the first full answer of the new server — until then the old tokens stand, which is harmless and brief.

## Out of scope

- `semanticTokens/range`, the viewport-sized request: files of `ccoe`'s sizes do not need it.
- `workspace/semanticTokens/refresh`: a server asking every client to refetch; answered (R57's rule: no request left pending) but not acted on in v1 — the next edit refetches anyway.
- Italic for `static` (R60) and any attribute that needs a font: not reachable through rendering attributes.
- IntelliJ's inspection colours (unused symbol, reassigned variable, inherited call): not in the protocol.

## Technical options

- `SemanticTokenDecoder` (`Editor/SemanticTokens.swift`): pure, `nonisolated` — the relative `data` array and a legend into `[SemanticToken]` (an `NSRange` in UTF-16, which is what LSP counts and `NSString` indexes, R38; the role and the traits of R60), and the application of a delta's edits to a previous array, highest `start` first so the offsets hold. Tested on fixtures; ~80 lines.
- `SemanticTokenStore` (`@MainActor`, one per `EditorTextView.Coordinator`): the sorted tokens, a binary search for the one covering a Neon token's start, and the set of ranges that changed between two batches, which is what `TextViewHighlighter.invalidate(.set(…))` takes.
- `LSPServer.semanticTokens(uri:previousResultId:)` bounded by `lsp.timeout` like hover and definition; `legend` and `supportsSemanticDelta` read off the capabilities. `LSPServers` keeps the last `resultId` and `data` on its `Document`, asks after `didOpen` and after each debounced `didChange`, and routes `(URL, [SemanticToken])` like diagnostics; `EditorFeature` hands the batch to every tab showing the file.
- The attribute provider is Neon's `TokenAttributeProvider`, called on the main actor by the styler; the store is read there with `MainActor.assumeIsolated`.

## Decisions

See [decisions.md](decisions.md).
