# Foreman 👷

**An agentic workspace for macOS.**

## About

Foreman is a native macOS app. One window is one folder is one workspace, like an IDE — except the center of it is your CLI agents (Claude Code, Antigravity, OpenCode), each running in its own tab on an embedded terminal surface ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)), one click away in the toolbar. There is no free-form shell: terminal surfaces only exist to host agents and run commands. Everything else (file explorer, git, editor, Postgres browser, run commands, a browser tab on the page you serve) is a feature that attaches panels and tabs around it.

Personal project, Apple Silicon first, local use only for now.

## Contributing and Developing

Specs, studies and decisions live in [`docs/specs/`](docs/specs/), one folder per domain; the implementation backlog and progress per milestone in [`docs/backlog/`](docs/backlog/). How it is assembled — principles, structure, dependencies — is in [`docs/architecture.md`](docs/architecture.md); how the code is written is in [`docs/coding-rules.md`](docs/coding-rules.md). Read all three before touching the code.

```bash
git clone git@github.com:abachar/foreman.git
cd foreman
open Foreman.xcodeproj   # build & run with Xcode
ln -s "$PWD/cli/foreman" /usr/local/bin/foreman   # then `foreman .` opens a folder in the built app
```

## Installing locally

```bash
cli/release   # Release archive, then /Applications/Foreman.app (unsigned: macOS asks once at first launch)
foreman .      # opens the current folder in the installed app
```

That is the whole distribution of v1 (`product` R10): no signing, notarization, Homebrew tap or auto-update — one user, one machine (decision 2026-08-27).

## Roadmap and Status

| Milestone | Scope | Status |
|---|---|---|
| M0 — Shell | window, layout, panels, shortcuts, toolbar, welcome screen, `foreman` CLI | 🟢 |
| M1 — Explorer + Editor | file tree, file tabs, highlighting (`Highlight/`), quick open (`Palette/`) | 🟢 |
| M2 — Terminal host + Agents | PTY + SwiftTerm surface, `TerminalService`, agent buttons and tabs | 🟢 |
| M3 — Run | workspace commands → terminal, `cmd+r` palette, ▶ Run button | 🟢 |
| M4 — Git | changes, side-by-side diff, history, branches, stash, remote | 🟢 |
| M5 — Postgres | schema browser, query tabs, result grid, history | 🟢 |
| M6 — Polish | open points of M0–M5, shortcuts survey, CI, measured budgets, local release | 🟢 |
| M7 — Formatting | format the active file (`editor`; on save dropped) | 🟢 |
| M8 — Visual redesign | theme tokens, every view (`design`) | 🟢 |
| M9 — Tabs and home screen | tab context menu, two-column home with every shortcut (`layout`) | 🟢 |
| M10 — Agentic workflow | send to agent (`cmd+e`), detected Run commands, session diff, worktrees per agent, code folding | 🟢 |
| M11 — Browser | one web page per window on `config.browser.url`, private session, Web Inspector; agents from the config only | 🟢 |
| M12 — SQL grammar | tree-sitter-sql for `.sql` and the query editor | 🟢 |
| M13 — Explorer | IntelliJ opening (click selects, double click opens, `shift+F6` renames), drag and drop moves | 🟢 |

The up-to-date table, task by task, is [`docs/backlog/README.md`](docs/backlog/README.md).

