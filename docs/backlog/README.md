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
| M7 — Formatting | [m7-formatter.md](m7-formatter.md) | editor (`01-study-formatter.md`) | 🟢 (2026-08-27; `cmd+shift+l` only, formatting on save dropped, no dependency added) |
| M8 — Visual redesign | [m8-design.md](m8-design.md) | design (transverse), `ThemeService`, every view | 🟢 (2026-08-27; option A toolbar with panel toggles, file icons, current line; validated by the author's eye after the batch) |
| M9 — Tabs and home screen | [m9-tabs.md](m9-tabs.md) | layout (R33 amended, R35) | 🟢 (2026-08-28) |
| M10 — Agentic workflow | [m10-agentic.md](m10-agentic.md) | agents (R10–R13), git (R30–R32), run (R14–R16), editor (R26–R28) | 🟢 (2026-08-28; the agent button menu entries — Session Changes, worktrees — checked by tests, not by hand) |
| M11 — Browser | [m11-browser.md](m11-browser.md) | browser (new folder `Browser/`) | 🟢 (2026-08-28; the page itself checked by hand by the author) |
| M12 — SQL grammar | [m12-sql-grammar.md](m12-sql-grammar.md) | editor (R11), postgres (R9) | 🟢 (2026-08-28) |
| M13 — Explorer | [m13-explorer.md](m13-explorer.md) | explorer (R12, R17, R21 amended, R22) | 🟢 (2026-08-28) |
| M14 — Polish, second round | [m14-polish-2.md](m14-polish-2.md) | editor (R14), design (R14, R21) | 🟢 (2026-08-29; inverted ground and config reference added the same day) |

Each file contains: the scope, the task table (rules covered, **library / native component used**, tests, size, status, PR), the definition of done, the decisions to take during the milestone. One task = one PR. The status is updated in the PR that finishes the task.
