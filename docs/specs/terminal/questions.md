# Open questions

- [x] SwiftTerm version: `v1.20.0` (decision 2026-08-27).
- [x] VT coverage of SwiftTerm 1.20: validated in use (2026-08-27) on Claude Code, OpenCode, Pi, Antigravity. Not handled by SwiftTerm, with no visible effect so far: `DECSET 2027` (grapheme clustering), `DECSET 2031` (theme notification), `OSC 66` (kitty text sizing), `OSC 99`, `CSI ? 5 W`. To keep an eye on.
- [ ] Copy/paste: `cmd+c` copies the selection, but might an agent want `cmd+c`? No: `ctrl+c` goes to the process, `cmd+c` stays with Wraith (`layout` R25). To be confirmed in use.
