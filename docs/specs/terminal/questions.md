# Open questions

- [x] SwiftTerm version: `v1.20.0` (decision 2026-08-27).
- [x] VT coverage of SwiftTerm 1.20: validated in use (2026-08-27) on Claude Code, OpenCode, Pi, Antigravity. Not handled by SwiftTerm, with no visible effect so far: `DECSET 2027` (grapheme clustering), `DECSET 2031` (theme notification), `OSC 66` (kitty text sizing), `OSC 99`, `CSI ? 5 W`. To keep an eye on.
- [x] Copy/paste: `cmd+c` copies the selection, `ctrl+c` goes to the process (`layout` R25) — confirmed in use on Claude Code, OpenCode, Pi and Antigravity (decision 2026-08-27, M6 task 6.2).
- [ ] A numbered Dock badge (agents waiting, across every window): deferred on 2026-08-30 with R7's bounce; it needs an owner at app level, which nothing provides today. To revisit if the bounce turns out not to be enough.
