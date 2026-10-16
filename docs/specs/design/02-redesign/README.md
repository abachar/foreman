# UI redesign — reference views (2026-10-16)

Thirteen views of the window, designed with the author on 2026-10-16 from four references (IntelliJ, Xcode, Kiro, Zed) and validated as **the base for the next UI work**. They are mockups: nothing here is implemented yet, and the rules of `design` and `layout` are **not amended yet** — the gaps are listed at the end, each one becomes a dated amendment when its task is planned.

## Editing the views

Each view is one standalone HTML page (inline CSS, inline SVG icons, JetBrains Mono from Google Fonts), drawn at **1440 × 900**. Open it in a browser; edit it in any editor. The sample workspace is a fictitious Spring Boot project, `orders-api`, chosen to show entities next to tables; `[Customer A]`… are placeholders.

The colours are the `dark` tokens of `ThemeService` (R9): ground `#2B2D30`, islands `#1E1F22`, raised `#26282C`, sunken `#151618`, separator `#343638`, text `#DFE1E5` / `#9DA0A8`, accent `#4A86E0`, states `#5FB865` / `#E0A63B` / `#E5534B`, syntax as in `ThemeService+Tokens.swift`. Islands keep the 10 pt radius and the 6 pt gutter of the mockups.

The working copy also lives on the author's private design canvas (claude.ai artifact `EZRY69NLky6vw4MtAD3axp`); when a view changes there, export it again here.

## The views

| File | State shown |
|---|---|
| [`01-home.html`](01-home.html) | Empty group: agents and recent files on the left, shortcuts per feature on the right (`layout` R33) |
| [`02-editor.html`](02-editor.html) | **The base**: gutter/code separator, 120-column print margin, indent guides with the caret's block brightened, matched braces, fold markers, sticky lines (enclosing class and method) |
| [`03-agent.html`](03-agent.html) | Split: code left, Claude Code terminal right; Changes tab listing what the agent touched; OpenCode waiting (orange badge) |
| [`04-changes.html`](04-changes.html) | Changes per repo (staged / changes / untracked), worktrees as child sections (compare, check out), commit area pinned at the bottom; side-by-side diff in the centre |
| [`05-history.html`](05-history.html) | History in the bottom panel, full width: graph, refs, full message, author, date; the selected commit lists its files, the file's diff opens in the centre |
| [`06-database.html`](06-database.html) | Database panel on the right (columns, keys, indexes), SQL query tab: selection run, result grid, timing |
| [`07-search.html`](07-search.html) | Find in project in the bottom panel: case / word / regex / file mask, results grouped by file |
| [`08-run.html`](08-run.html) | ▶ Run menu open (commands of `config.json` with their state); `backend:dev` output in the Run tab of the bottom panel |
| [`09-quick-open.html`](09-quick-open.html) | ⌘P palette floating over the window, fuzzy match in bold |
| [`10-markdown-browser.html`](10-markdown-browser.html) | Split: README preview left, browser tab on `config.browser.url` right; Browser button in the toolbar |
| [`11-branches-menu.html`](11-branches-menu.html) | Branch widget menu: worktrees (with the agent working in each), local and remote branches, fetch / pull / push, stash; a worktree submenu |
| [`12-diagnostics.html`](12-diagnostics.html) | LSP error underlined with its hover, a warning, the active file's counters in the status bar, config error banner |
| [`13-problems.html`](13-problems.html) | Problems tab of the bottom panel, opened from the status bar counters: scope (current file / project), error and warning filters, groups per file, config errors first |

## What the views settle

- **Window**: islands kept; no blue outline around the active group — the active tab's accent underline is enough, grey underline in the other group of a split.
- **Toolbar**: project ▾ and branch / worktrees ▾ on the left; **centre empty for now**; agents with their badges, the Browser button (only when `config.browser.url` is set), then the Run widget (command ▾, ▶, ■) on the right. No panel toggles in the toolbar.
- **Left panel**: one slot, titled by tabs **Project · Changes**.
- **Right panel**: **Database**, to read an entity and its table side by side.
- **Bottom panel**: full width of the centre, tabs **History · Search · Run · Problems** — rows there carry a lot of information.
- **Status bar**: three toggles (left / bottom / right panel), the active file's ⊗ / ⚠ counters (a click opens Problems), then per tab: LSP server, position, language and encoding for a file; size for a terminal; `+n −n` for a diff; host for the browser. The branch is not repeated there.
- **Editor**: as in `02-editor.html`; no path bar under the tabs (the sticky lines give the context).
- **Agents stay terminal surfaces**: no graphical rendering of tool calls (it would need an SDK-driven agent and API pricing).

Rejected on the way, with the reason: tool-window stripes on the window edges (two 40 pt bands for icons the status bar already offers); a central activity viewer (a CLI agent does not expose what it is doing); a Sessions panel (the badges already say which agent waits); an inspector panel; flat panels without islands. A light theme is a separate feature.

## Gaps with the current specs (to amend when the tasks are planned)

- `layout` R30 and `design` R15: the panel toggles leave the toolbar for the status bar; the agents move to the right next to Run.
- `git`: Changes and History are no longer right panels — Changes is a tab of the left panel, History a tab of the bottom panel.
- `editor`: content search stays in the bottom panel, now as one of its tabs; indent guides, print margin, matched braces and sticky lines are new.
- `run` (study: "No panel"): the commands' output moves to the Run tab of the bottom panel.
- `design` R3 / `layout` R17: the active group's accent border is dropped.
- New: the status bar (no rule yet), the Problems tab, the Browser button in the toolbar (`browser` already shows a button; its place changes).
