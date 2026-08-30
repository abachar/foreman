# Backlog

Breakdown and progress of the implementation, one file per milestone. The specs say *what* ([`../specs/`](../specs/)), this folder says *in what order and where we stand*.

**M0–M14 built v1, finished on 2026-08-29.** From M15 on, a milestone is no longer a step in a plan: it is a batch of improvements coming from **use** — a friction met while working in Foreman, a rule written but never made visible. The numbering carries on because the specs and the decisions cite it.

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
| M14 — Polish, second round | [m14-polish-2.md](m14-polish-2.md) | editor (R14), design (R2, R6, R14, R21), layout (R36), git, postgres, run | 🟢 (2026-08-29; inverted ground, config reference and preview reading size and conditional features added the same day) |
| M15 — Usage, first round | [m15-usage.md](m15-usage.md) | terminal (R7), git (R6b), explorer (R23), layout (R24, R37), config (R4), product (R8) | 🟢 (2026-08-30) |
| M16 — New file, and the markdown viewer against GitHub | [m16-new-file-markdown.md](m16-new-file-markdown.md) | editor (R1, R8 amended, new R34), explorer (R3), layout (new R38), design (R6 amended) | 🟢 (2026-08-30) |
| M17 — Audit follow-up | [m17-audit.md](m17-audit.md) | every domain: the findings of [`audit-2026-08-30.md`](../audits/audit-2026-08-30.md) | 🟢 (2026-08-30; M15a left open with its reason, R4–R6, R8, W4, T6, L6 closed without a change, E8 sent to `questions.md`) |

Each file contains: the scope, the task table (rules covered, **library / native component used**, tests, size, status, PR), the definition of done, the decisions to take during the milestone. One task = one PR. The status is updated in the PR that finishes the task.
