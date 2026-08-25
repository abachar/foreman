# Wraith 👻

**A terminal-first workspace for macOS.**

## About

Wraith is a native macOS app built around an embedded [Ghostty](https://github.com/ghostty-org/ghostty) terminal. One window is one folder is one workspace, like an IDE — except the terminal is the center of it, and everything else (file explorer, git, editor, Postgres browser, run commands) is a plugin that attaches panels around it.

Personal project, Apple Silicon first, local use only for now.

## Contributing and Developing

Specs, studies, decisions and progress live in [`docs/specs/`](docs/specs/), one folder per domain. Read them before touching the code.

```bash
git clone git@github.com:abachar/wraith.git
cd wraith
swift build
```

## Roadmap and Status

| Milestone | Scope | Status |
|---|---|---|
| M0 — Shell | window, layout, panels, shortcuts, `wraith` CLI | 🟡 specs |
| M1 — Terminal | PTY + libghostty rendering, tabs, splits | ⚪ |
| M2 — Explorer + Editor | file tree, file tabs, highlighting, quick open | ⚪ |
| M3 — Git | changes, diff, history | ⚪ |
| M4 — Run | workspace commands → terminal | ⚪ |
| M5 — Postgres | schema browser, query editor, results | ⚪ |
| M6 — Polish | themes, settings, distribution | ⚪ |

---

*Wraith wraps the ghost.* Built on the shoulders of [Ghostty](https://ghostty.org).
