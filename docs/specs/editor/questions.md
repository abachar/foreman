# Open questions

- [ ] Formatting (2026-08-27, [01-study-formatter.md](01-study-formatter.md)): should `formatter.timeout` (R30, the 5 s bound) be a config key from v1, or do we wait until a slow `npx` gets cut off? Proposal: the key exists from v1, it costs three lines.
- [ ] Formatting (2026-08-27): should there be visible feedback when the formatter changed nothing (R28) — a brief status message, or nothing at all? To be settled in use.
- [ ] Formatting (2026-08-27, R28): should an entry be able to declare an accepted exit status, for the formatters that exit non-zero on a warning? Only `tidy` is known to need it (`format-all` accepts `(0 1)` for it and for nothing else), and `prettier` covers HTML anyway. Proposal: no — keep "exit `0` or nothing is applied", and revisit only if a second formatter needs it.
