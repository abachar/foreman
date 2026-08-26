# Backlog

Découpage et avancement de l'implémentation, un fichier par milestone. Les specs disent *quoi* ([`../specs/`](../specs/)), ce dossier dit *dans quel ordre et où on en est*.

| Milestone | Fichier | Domaines | Statut |
|---|---|---|---|
| M0 — Shell | [m0-shell.md](m0-shell.md) | product, config, layout | 🟢 (2026-08-26 ; CI Xcode 27 non vérifiée) |
| M1 — Explorer + Editor | [m1-explorer-editor.md](m1-explorer-editor.md) | explorer, editor, Palette, Highlight | ⚪ (démarré 2026-08-26) |
| M2 — Terminal + Agents | | terminal, agents | |
| M3 — Run | | run | |
| M4 — Git | | git | |
| M5 — Postgres | | postgres | |
| M6 — Polish | | | |

Chaque fichier contient : le périmètre, le tableau des tâches (règles couvertes, **lib / natif utilisé**, tests, taille, statut, PR), la définition de fini, les décisions à prendre pendant le milestone. Une tâche = une PR. Le statut se met à jour dans la PR qui termine la tâche.
