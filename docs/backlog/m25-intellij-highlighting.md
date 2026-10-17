# M25 — Highlighting the way IntelliJ reads

Tenth round driven by use (2026-10-17), after [M24](m24-lsp-settings.md). The author reads Java in
IntelliJ all day and Foreman's Java looks wrong to that eye — not the colours, which are already
IntelliJ's (`ThemeService+Tokens.swift`: *Dark* for `dark`, *IntelliJ Light* for `light`), but
**what they land on**:

- tree-sitter-java's own `highlights.scm` captures thirteen shapes of `@type`, so every class name
  is blue; IntelliJ leaves class names in plain text;
- IntelliJ paints every **field** purple (`#C77DBB`), declared or used, and the `static` ones in
  italic; the Java query captures no `field_access` at all, and a bare identifier is a field or a
  local depending on something no grammar knows;
- IntelliJ colours a method's **declaration**, never its calls; Foreman gives both `function`.

Two levers, in order: the query, cheap and immediate, bounded by what a grammar can know; then
the server's **semantic tokens**, which carry exactly the information IntelliJ paints with
(field / parameter / local / method, `static` / `declaration` / `deprecated`), for Java and for
TypeScript alike. The palette is not touched by either.

Domain: [`editor`](../specs/editor/) — `00-study.md` R11, R12 (the grammar and the roles), and a
new study `05-study-semantic-tokens.md` for 25.2 (R58–R60). No new folder; no dependency (the
`LanguageServerProtocol` client already has `semanticTokensFull` / `semanticTokensFullDelta` and
the legend types).

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Tasks

One branch `feat/m25` from `main`, one commit per task. Nothing starts before the author's go.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 25.1 | **Foreman's own Java query**: a `java/highlights.scm` in the app's resources, loaded **instead of** the grammar's by `Language.makeConfiguration` (the way `typeScriptConfiguration` already assembles its own `Data` — a per-language override is the same three lines, generalised to "ours if present, the package's otherwise"), written against IntelliJ's *Java* colour page: `type_identifier` → no capture in a use, `@type` only in a declaration (`class_declaration name:`, `interface_declaration`, `enum_declaration`, `record_declaration`); `method_declaration name:` → `@function.method`, `method_invocation name:` → **no capture** (plain text, like IntelliJ); `field_access field:` and `field_declaration declarator name:` → `@property` (purple); `this`/`super` → `@variable.builtin` mapped to `keyword` (orange, IntelliJ's choice); annotations stay `@attribute`; `@constant` for `static final` fields where the grammar can see it (`field_declaration` with both modifiers). `HighlightRole(capture:)` gains nothing a capture does not already name. Checked **by eye** on `ccoe-backend` (a service with fields, a record, an enum, an annotated controller), against the same file in IntelliJ | editor R11, R12 | tree-sitter query (`.scm`), `SwiftTreeSitter.Query`, the existing `queriesDirectory` lookup | the query compiles against the grammar at test time; the captures on a fixture file (a class with a field, a local, a parameter, a call, an annotation, a nested type) — the ranges and names expected, so a grammar upgrade that renames a node fails here and not on screen | S | 🟢 (2026-10-17; the by-eye check against IntelliJ left to the author) | |
| 25.2 | **Semantic tokens** (`05-study-semantic-tokens.md`, to write first — R58–R60): after `initialize`, a server announcing `semanticTokensProvider` is asked `textDocument/semanticTokens/full` on `didOpen` and, debounced behind R37's `didChange`, `…/full/delta` when it offers it, `full` otherwise; the legend (`tokenTypes`, `tokenModifiers`) decoded once per server, the relative-position array turned into absolute UTF-16 ranges off the main actor (R45). **One layer, not two**: Neon already applies the attributes and re-applies them on every invalidation, so a second pass over the same text would be overwritten — instead the tab's `attributeProvider` consults a per-tab map of semantic tokens (range → type + modifiers) and, where one covers the token Neon is styling, answers with the **semantic role**: `property` for a field, `variable` for a parameter and a local, `function` for a method declaration, plain for a call, `type` for a declaration only; `static` → italic, `deprecated` → strikethrough, `declaration` decides declaration vs use. When a batch arrives, the ranges it changed are invalidated so Neon asks again; tree-sitter keeps giving the instant colour at the keystroke and the server's answer refines it when it comes. A stale batch (version behind the text) is dropped, R40's rule. Nothing new in the theme: the roles are R12's, the two modifiers are font traits. Targets: `jdtls` (full + delta) and `typescript-language-server` (full); `sourcekit-lsp` announces it too | editor R12, R37, R40, R45, new R58 (the request and its cadence), R59 (one layer, the provider answers), R60 (what each token type and modifier becomes) | `LanguageServerProtocol` (`SemanticTokensParams`, `SemanticTokensDeltaParams`, `SemanticTokensLegend`), Neon's `attributeProvider` and `invalidate`, `NSFontDescriptor` traits for italic | decoding the relative array into ranges (one line, several lines, an astral character, an empty answer); applying a delta to a previous array (insert, delete, replace at the start, the middle, the end); the provider's answer with and without a covering token, with each modifier; a stale version dropped; `MockServer` for the request-level tests, no server launched | M | ⚪ | |

## Out of scope

- IntelliJ's *inherited method call*, *unused symbol* and *reassigned variable* colours: the
  first two come from inspections, not tokens; the third needs flow analysis. None reach a client
  through LSP.
- A user-overridable `theme.syntax.*` (R12 says the syntax colours are not overridable): a separate
  question, one hour when asked, independent of both tasks.
- Other languages' queries (Kotlin, TypeScript): 25.1 is Java because that is what the author reads;
  25.2 covers TypeScript by construction.

## Where it stands

Planned on 2026-10-17 with the author, after M24 on `ccoe`. 25.1 built the same day on
`feat/m25`: `Highlight/Queries/java.highlights.scm` (shipped as a resource by the synchronized
group, nothing to add to the project), `Language.ownConfiguration` loading it in place of the
package's, six tests pinning the captures on a fixture. Found on the way: tree-sitter leaves the
`#match?` predicates to the client, so a test that reads `match.captures` without a
`Predicate.Context` sees every identifier as a `constant`. Deviation from IntelliJ kept on purpose:
a declared type name is a `type` (blue), where IntelliJ leaves it plain — to settle by eye. Left:
the author's look at `ccoe-backend` next to IntelliJ, then 25.2.
