# Open questions

- [ ] Formatting (2026-08-27, [01-study-formatter.md](01-study-formatter.md)): should `formatter.timeout` (R30, the 5 s bound) be a config key from v1, or do we wait until a slow `npx` gets cut off? Proposal: the key exists from v1, it costs three lines.
- [ ] Formatting (2026-08-27): should there be visible feedback when the formatter changed nothing (R28) — a brief status message, or nothing at all? To be settled in use.
