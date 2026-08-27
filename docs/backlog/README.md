# Backlog

Découpage et avancement de l'implémentation, un fichier par milestone. Les specs disent *quoi* ([`../specs/`](../specs/)), ce dossier dit *dans quel ordre et où on en est*.

| Milestone | Fichier | Domaines | Statut |
|---|---|---|---|
| M0 — Shell | [m0-shell.md](m0-shell.md) | product, config, layout | 🟢 (2026-08-26 ; CI Xcode 27 non vérifiée) |
| M1 — Explorer + Editor | [m1-explorer-editor.md](m1-explorer-editor.md) | explorer, editor, Palette, Highlight | 🟢 (2026-08-27 ; sql en M5, gitignored en M4) |
| M2 — Terminal + Agents | [m2-terminal-agents.md](m2-terminal-agents.md) | terminal, agents, `Terminal/`, ThemeService | 🟢 (2026-08-27 ; VT validé sur Claude Code, OpenCode, Pi, Antigravity) |
| M3 — Run | [m3-run.md](m3-run.md) | run, `Palette/` (`opt+enter`), badge `blue` | 🟢 (2026-08-27 ; `root` alias de `.`, `configChanges` par consommateur) |
| M4 — Git | | git | |
| M5 — Postgres | | postgres | |
| M6 — Polish | | | |

Chaque fichier contient : le périmètre, le tableau des tâches (règles couvertes, **lib / natif utilisé**, tests, taille, statut, PR), la définition de fini, les décisions à prendre pendant le milestone. Une tâche = une PR. Le statut se met à jour dans la PR qui termine la tâche.
