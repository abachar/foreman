# Wraith 👻

**An agentic workspace for macOS.**

## About

Wraith is a native macOS app. One window is one folder is one workspace, like an IDE — except the center of it is your CLI agents (Claude Code, Antigravity, OpenCode), each running in its own tab on an embedded terminal surface ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)), one click away in the toolbar. There is no free-form shell: terminal surfaces only exist to host agents and run commands. Everything else (file explorer, git, editor, Postgres browser, run commands) is a plugin that attaches panels around it.

Personal project, Apple Silicon first, local use only for now.

## Contributing and Developing

Specs, studies and decisions live in [`docs/specs/`](docs/specs/), one folder per domain; the implementation backlog and progress per milestone in [`docs/backlog/`](docs/backlog/). How it is assembled — principles, structure, dependencies — is in [`docs/architecture.md`](docs/architecture.md); how the code is written is in [`docs/coding-rules.md`](docs/coding-rules.md). Read all three before touching the code.

```bash
git clone git@github.com:abachar/wraith.git
cd wraith
swift build
```

## Roadmap and Status

| Milestone | Scope | Status |
|---|---|---|
| M0 — Shell | window, layout, panels, shortcuts, toolbar, welcome screen, `wraith` CLI | 🟡 specs |
| M1 — Explorer + Editor | file tree, file tabs, highlighting (`HighlightService`), quick open (`PaletteService`) | ⚪ |
| M2 — Terminal host + Agents | PTY + SwiftTerm surface, `TerminalService`, agent buttons and tabs | ⚪ |
| M3 — Run | workspace commands → terminal, `cmd+r` palette, ▶ Run button | ⚪ |
| M4 — Git | changes, diff, history | ⚪ |
| M5 — Postgres | schema browser, query editor, results | ⚪ |
| M6 — Polish | themes, settings, distribution | ⚪ |

