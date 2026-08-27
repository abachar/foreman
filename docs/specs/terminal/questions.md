# Questions ouvertes

- [x] Version de SwiftTerm : `v1.20.0` (décision 2026-08-27).
- [x] Couverture VT de SwiftTerm 1.20 : validée à l'usage (2026-08-27) sur Claude Code, OpenCode, Pi, Antigravity. Non gérés par SwiftTerm, sans effet visible pour l'instant : `DECSET 2027` (grapheme clustering), `DECSET 2031` (notification de thème), `OSC 66` (kitty text sizing), `OSC 99`, `CSI ? 5 W`. À surveiller.
- [ ] Copier/coller : `cmd+c` copie la sélection, mais un agent peut vouloir `cmd+c` ? Non : `ctrl+c` va au process, `cmd+c` reste à Wraith (`layout` R25). À confirmer à l'usage.
