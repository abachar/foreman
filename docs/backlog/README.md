# Backlog

Breakdown and progress of the implementation, one file per milestone. The specs say *what* ([`../specs/`](../specs/)), this folder says *in what order and where we stand*.

| Milestone | File | Domains | Status |
|---|---|---|---|
| M0 — Shell | [m0-shell.md](m0-shell.md) | product, config, layout | 🟢 (2026-08-26; CI on Xcode 27 unverified) |
| M1 — Explorer + Editor | [m1-explorer-editor.md](m1-explorer-editor.md) | explorer, editor, Palette, Highlight | 🟢 (2026-08-27; sql in M5, gitignored in M4) |
| M2 — Terminal + Agents | [m2-terminal-agents.md](m2-terminal-agents.md) | terminal, agents, `Terminal/`, ThemeService | 🟢 (2026-08-27; VT validated on Claude Code, OpenCode, Pi, Antigravity) |
| M3 — Run | [m3-run.md](m3-run.md) | run, `Palette/` (`opt+enter`), `blue` badge | 🟢 (2026-08-27; `root` alias for `.`, `configChanges` per consumer) |
| M4 — Git | [m4-git.md](m4-git.md) | git, explorer / editor complements | 🟢 (2026-08-27; per-hunk staging R15 dropped, side-by-side diff added) |
| M5 — Postgres | [m5-postgres.md](m5-postgres.md) | postgres, `Highlight/` (`sql`), `Workspace/` (`SecretStore`) | 🟢 (2026-08-27; query as center tabs, export deferred, `sql` grammar still blocked upstream, verified on PostgreSQL 18.3) |
| M6 — Polish | [m6-polish.md](m6-polish.md) | none of its own: open points from M0–M5 | 🟢 (2026-08-27; budgets measured, three faults fixed on the way: second window, grammar compile on main, quick open; CI tolerated until Xcode 27 reaches the runners) |
| M7 — Formatting | [m7-formatter.md](m7-formatter.md) | editor (`01-study-formatter.md`) | 🟡 |
| M8 — Visual redesign | [m8-design.md](m8-design.md) | design (transverse), `ThemeService`, every view | ⚪ |

Each file contains: the scope, the task table (rules covered, **library / native component used**, tests, size, status, PR), the definition of done, the decisions to take during the milestone. One task = one PR. The status is updated in the PR that finishes the task.
