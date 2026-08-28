# Study — code folding

> Feature `editor`, third study (2026-08-28): fold a block from the gutter, driven by tree-sitter. Rules R26–R28; decisions in [`decisions.md`](decisions.md).

## Goal

Long files (a 700-line `views.tsx`) read better with functions and classes collapsed. tree-sitter already parses the file for highlighting (`editor` R12); the same tree gives the block boundaries.

## Functional rules

- R26 — **Foldable region** = a named syntax node spanning at least two lines whose first token is `{`, `[` or `(` (a body, an object, an argument list), from the line of the opening token to the line before the closing one; nested regions are all foldable. Languages without such blocks (yaml, markdown, toml) have no folding in v1. The first line of the region stays visible; the folded state is the gutter's chevron (no inline `…` marker, decision 2026-08-28: the hidden paragraphs keep their characters, so nothing can be appended to the line).
- R27 — **UI**: a chevron in the gutter (`editor` R6's `LineNumberRulerView`) on the first line of each region, shown for every region (no hover-only), on the code side of the numbers and in their color (author, 2026-08-28); a click folds/unfolds; `cmd+opt+[` / `cmd+opt+]` fold/unfold the region containing the cursor (`editor.fold` / `editor.unfold`, scope `tab(editor.file)`; VS Code's keys). A fold containing the selection is not created (the selection is moved to the region's first line first).
- R28 — Folds are **not persisted** (a tab reopens unfolded); editing inside a folded region unfolds it; a fold survives edits elsewhere (the region is tracked by the tree, not by line numbers). Search (`cmd+f`) unfolds the match's region.

## Edge cases

- A one-line block: no chevron.
- A region whose closing token is on the same line as the next region's opening (`} else {`): the fold ends on the line before the closing token, so the `else` line stays visible.
- The grammar failed (`editor` R13): no folding, no error.

## Out of scope

- Folding by indentation for yaml/markdown.
- Fold all / unfold all, fold levels, persisting folds.
- Folding in the diff tab or the SQL editor.

## Technical options

- **Regions**: a `TreeSitterClient` query is not needed: a walk of the tree (`Tree.rootNode`, `Node.namedChildren`) filtering on the first child's type, ~40 lines in `Highlight/` (`Folding.swift`), tested on parsed snippets. The tree comes from Neon's client (`TextViewHighlighter.client`); if it is not exposed, a second `TreeSitterClient` on the same content is the fallback (the parse is incremental and off the main actor).
- **Hiding lines** (as shipped, 2026-08-28): TextKit 2 — `NSTextLayoutManager` has no fold API; `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)` returns, for a hidden paragraph, an `NSTextParagraph` with the same characters and a 0.01 pt line height (Apple's sample uses the same delegate to restyle paragraphs). The storage is untouched (saving, undo and search see the whole text); the gutter skips fragments under 1 pt, so the numbers jump over the fold. An attribute-only `edited` over the text makes the content storage ask again after a toggle. A custom `NSTextLayoutFragment` (the first plan) was not needed.
- Sized **L** and shipped last in M10: the most code of the milestone, and the least reusable.
