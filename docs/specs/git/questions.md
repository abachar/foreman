# Open questions

- [x] Ignored files for the explorer (`explorer` R4): settled 2026-08-27 — `status --ignored=matching` on every status (16 ms with or without it on the author's repo; `--ignored` alone 60 ms), see `decisions.md`.
- [ ] Actions on a folder row of the Changes tree (stage / discard everything under it, R6b): left out on 2026-08-30, per-file and per-group actions were enough so far. To revisit once the tree is in use.
