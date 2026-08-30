# Specs

The assembly (principles, structure, retained dependencies) is in [`../architecture.md`](../architecture.md); the code style in [`../coding-rules.md`](../coding-rules.md).

One folder per domain, **in implementation order** (each row depends only on the rows above it; this is the milestone order of the [README](../../README.md)):

| # | Folder | Domain | Depends on | Milestone |
|---|---|---|---|---|
| 1 | [product](product/) | vision, target user, non-goals, no free-form shell | — | M0 |
| 2 | [config](config/) | `.foreman/config.json`, `state.json`, Keychain, hot reload | product | M0 |
| 3 | [layout](layout/) | zones, splits, tab groups, PanelManager, ShortcutRegistry, toolbar, home screen | config | M0 |
| 4 | [explorer](explorer/) | file tree, FSEvents, CRUD, git badges | layout | M1 |
| 5 | [editor](editor/) | viewer/editor, `Highlight`, markdown, quick open, search; formatting (`01-study-formatter.md`), folding (`02-study-folding.md`), LSP diagnostics/hover/definition (`03-study-lsp.md`), go to selector (`04-study-selectors.md`) | explorer, `Palette`, `Highlight` | M1, M7, M18 |
| 6 | [terminal](terminal/) | PTY owned by Foreman + SwiftTerm surface, `TerminalService` (one tab = one process, no shell) | layout | M2 |
| 7 | [agents](agents/) | CLI agents (Claude Code, Antigravity, OpenCode): toolbar buttons, one tab per agent | terminal | M2 |
| 8 | [run](run/) | workspace commands → terminal surface, `cmd+r` palette, ▶ Run button | terminal, `Palette` | M3 |
| 9 | [git](git/) | changes, diff, history, remote, branches | explorer, editor (`Editor.open`), `Highlight` | M4 |
| 10 | [postgres](postgres/) | single connection, schema, queries, results | layout, `Highlight` | M5 |
| 11 | [design](design/) | visual identity: `ThemeService` tokens, islands, flat bars, Dark theme (transverse, no feature) | layout, terminal (`ThemeService`) | M8 |
| 12 | [browser](browser/) | one web page per window on `config.browser.url`: `WKWebView`, private session, Web Inspector | layout, config, agents (`cmd+e`) | M11 |

`Palette` and `Highlight` are shared folders (`architecture.md`), both shipped with `editor` (M1: quick open and highlighting). The terminal comes after the editor: the app must already be usable (open, read, edit) before it hosts processes.

The task breakdown and progress are in [`../backlog/`](../backlog/), one file per milestone.

Each folder contains:

| File | Role |
|---|---|
| `NN-study.md` | study or studies, numbered in writing order: goal, user stories, functional rules (R1, R2…), edge cases, out of scope, technical options |
| `decisions.md` | decisions taken (date, choice, rejected alternatives, why) |
| `questions.md` | open questions; an answered question becomes a row in `decisions.md` |
