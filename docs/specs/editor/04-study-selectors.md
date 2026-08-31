# editor — Study: go to selector

> The fifth study of the `editor` domain ([00-study.md](00-study.md)), 2026-08-31. Rules **R47–R49**, continuing the numbering (R1–R23 and R34 in the first study, R24–R33 in [01-study-formatter.md](01-study-formatter.md), R26–R28 in [02-study-folding.md](02-study-folding.md) — collision recorded in [`questions.md`](questions.md) —, R35–R46 in [03-study-lsp.md](03-study-lsp.md)). Decisions and questions stay in [`decisions.md`](decisions.md) and [`questions.md`](questions.md).

## Goal

`cmd+click` on a class or an id in an HTML file (or an Angular template) opens the CSS rule that defines it.

**This is deliberately not LSP**, and that is the reason it has its own study rather than a paragraph in `03-study-lsp.md`. No language server does it: `vscode-css-language-server` works on one CSS file at a time (properties, validation) and knows nothing of HTML; `vscode-html-language-server` does not make the jump either. In VS Code the feature comes from extensions — [CSS Peek](https://github.com/pranaygp/vscode-css-peek) and [vscode-html-css](https://github.com/ecmel/vscode-html-css) — which build their own index of the workspace's selectors. That is the prior art, and that is what is written here: an editor feature over tree-sitter and a file walk, no server to install, no dependency added.

Both halves already exist in Foreman. tree-sitter parses CSS and HTML (R11), and `QuickOpenIndex` (R18) is a workspace walk built lazily off the main actor — the model to copy, not to abstract over.

## User story

- US15 — I am in a `.html`, I `cmd+click` on `class="card-title"`: the `.css` that defines `.card-title` opens in a preview tab, on the rule's line.

## Functional rules

- R47 — **The selector index**: class and id selectors → (file, line) — the grammar calls a pseudo-class's name a `class_name` too, so `:hover` and `::before` are skipped by their parent node (found in task 18.5; without it `class="hover"` jumped to a `:hover` rule) —, built the **first time a resolution needs it** (P4 — never at startup, never on opening a tab), off the main actor, by walking the workspace's `.css` files under the single disk exclusion list (`architecture.md`) and reading the selectors off the tree-sitter `css` tree — not with a regular expression. A compound selector (`.card .title`, `a.btn:hover`) registers **each** class and id it names. The index is invalidated for a file when `FSWatchService` reports it changed (debounced like the rest), and dropped with the window.
- R48 — **Trigger and resolution**: `cmd+click` on the value of a `class` or `id` attribute in an `.html` tab — the attribute and the word under the pointer are found on the `html` tree, not by scanning text — and `ctrl+cmd+j` on the same position — **amended 2026-08-31, task 18.5**: the study called for an `editor.goToSelector` action of its own, and the existing `editor.goToDefinition` dispatches on the file instead. In an HTML file "go to the definition" means the CSS rule, and a second shortcut for it would be a distinction only the implementation cares about. A class list (`class="btn btn-primary"`) resolves the **name under the pointer**, not the first. One match → the existing `Editor.open(path, preview:, newGroup:, line:)` (R3), the same call go-to-definition uses (R43). Several matches → the first in workspace order, no picker (R43's policy). No match → **nothing happens, silently** (see R49).
- R49 — **Scope and degradation.** `.css` only in v1: `.scss` and `.less` have no grammar (R11) and are not walked. A class written in a `.ts`/`.tsx` string is not resolved — that is `cssmodules-language-server`'s job and it is declarable in the `lsp` section (`03-study-lsp.md` R35), not something to reimplement. No reverse direction (a CSS rule to its uses). And the silence of R48 is a rule, not an omission: with Tailwind or any utility framework almost no class is defined in a local `.css`, so an unresolved `cmd+click` must cost nothing and say nothing — a banner here would fire on nearly every click.

## Edge cases

- **A Tailwind project**: the index is built once, finds almost nothing, and every `cmd+click` falls through in silence (R49). The walk still has to be cheap enough that this is not felt.
- **The same selector defined in several files** (a base sheet and an override): the first in workspace order, and the author decides from use whether that needs a picker (`questions.md`).
- **An Angular template**: it is an `.html` file, so it works with no special case — but a class coming from a component's `styleUrls` is found only because the file is in the workspace, not because Angular was understood.
- **A `cmd+click` in an `.html` outside a `class`/`id` attribute** (on a tag, an `href`): nothing, and no conflict with R43 — an `.html` has no LSP definition provider unless `ngserver` is declared, and the two triggers are told apart by what the tree says is under the pointer.
- **A very large stylesheet or a generated one** (`.min.css`): walked like the others; if it turns out to hurt, the exclusion is a config line, not code.
- **A `.css` open and modified but not saved**: the index reads the disk, so a selector just typed is not found until `cmd+s`. Acceptable in v1; the alternative is to index the view's text, which R37's document sync does for LSP and this feature does not need.

## Out of scope

- `.scss`, `.less`, `.styl`; CSS-in-JS; the reverse direction; renaming a selector across files; completing a class name inside `class="…"` (that is completion — AI's job, `03-study-lsp.md`).

## Technical options

Nothing to add and nothing to install. The `css` and `html` grammars are already loaded by `Highlight/` (R11), `QuickOpenIndex` (R18) is the pattern for a lazy off-main-actor walk with its exclusion list, `FSWatchService` already reports file changes to whoever subscribes, and `Editor.open(…, line:)` is the arrival. The index is a dictionary; the resolution is a tree query and a lookup.

Tests, hermetic: selectors read off a CSS tree (simple, compound, id, pseudo-class, media block), the word under a position in a `class` list, resolution with zero / one / several matches, invalidation on a file change.

## Decisions

See [decisions.md](decisions.md).
