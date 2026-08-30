# Audits

Full reads of the codebase, kept as they were written. An audit is a **record**, not a plan: it is
never edited after the fact, and the numbering it gives its findings (`C1`, `M9a`, `R8`, `W3`…) is
what the fixes cite.

| Date | Audit | Scope | Where the fixes are tracked |
|---|---|---|---|
| 2026-08-30 | [audit-2026-08-30.md](audit-2026-08-30.md) | the whole codebase (~27,000 lines, 209 files) after M16 | [M17](../backlog/m17-audit.md) |

A second review was run on the same prompt the same day. It is not kept here: its central claim —
that `@concurrent` is an invented attribute breaking the build — is false (SE-0461, shipped in
Swift 6.2, used 32 times here), and of its eight points only two survived checking. They are
task 17.14 of M17.

## Working with an audit

- The audit is written first and committed on its own. Nothing else belongs in that commit.
- Its findings become tasks in a backlog milestone, grouped by domain, one task per PR
  (`AGENTS.md`). A finding is never fixed straight off the audit document.
- A fix commit cites its finding id in the body (`audit C3`), so the backlog can be rebuilt from
  the history if it ever drifts.
- A finding the audit got wrong, or that a dated decision already settled, is **closed in the
  backlog with the reason**, not silently dropped.
