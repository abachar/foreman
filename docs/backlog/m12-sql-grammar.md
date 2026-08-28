# M12 — SQL grammar

M12 = **the `sql` grammar at last** (editor R11, postgres R9; editor and postgres decisions 2026-08-28): tree-sitter-sql resolves and builds under Xcode 27 from its `gh-pages` branch, so `.sql` files and the Postgres query editor are highlighted by the shared `Highlight/` folder and the regex stop-gap goes.

Domains covered: [`editor`](../specs/editor/), [`postgres`](../specs/postgres/).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 12.1 | **`sql` grammar**: the package (`gh-pages`, pinned by `Package.resolved`), `Language.sql` (`.sql`, `.psql`, `--` comments), Neon attached in `SQLEditorView` through the injected `Highlighter`, `SQLHighlighter` and its tests removed; docs (R11, R9, decisions, the closed question, `architecture.md`) | editor R11–R13; postgres R9 | tree-sitter-sql (SPM), Neon `TextViewHighlighter` | `query.sql` → `.sql`; `everyLanguageLoadsItsQueries` covers the new bundle | S | 🟢 (2026-08-28) | |

## Definition of done

- A `.sql` file and a `Query N` tab show keywords, strings, comments and numbers in the theme's colors; `cmd+/` still comments with `--`.
- No `SQLHighlighter` left; the package is the only change to `Package.resolved`.
