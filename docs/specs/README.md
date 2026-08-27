# Specs

L'assemblage (principes, structure, dépendances retenues) est dans [`../architecture.md`](../architecture.md) ; le style de code dans [`../coding-rules.md`](../coding-rules.md).

Un dossier par domaine, **dans l'ordre d'implémentation** (chaque ligne ne dépend que des lignes au-dessus ; c'est l'ordre des milestones du [README](../../README.md)) :

| # | Dossier | Domaine | Dépend de | Milestone |
|---|---|---|---|---|
| 1 | [product](product/) | vision, utilisateur cible, non-objectifs, pas de shell libre | — | M0 |
| 2 | [config](config/) | `.wraith/config.json`, `state.json`, Keychain, rechargement à chaud | product | M0 |
| 3 | [layout](layout/) | zones, splits, groupes d'onglets, PanelManager, ShortcutRegistry, barre d'outils, écran d'accueil | config | M0 |
| 4 | [explorer](explorer/) | arbre de fichiers, FSEvents, CRUD, badges git | layout | M1 |
| 5 | [editor](editor/) | viewer/éditeur, `Highlight`, markdown, quick open, recherche ; formatage (`01-study-formatter.md`) | explorer, `Palette`, `Highlight` | M1, M7 |
| 6 | [terminal](terminal/) | PTY possédé par Wraith + surface SwiftTerm, `TerminalService` (un onglet = un process, pas de shell) | layout | M2 |
| 7 | [agents](agents/) | agents CLI (Claude Code, Antigravity, OpenCode) : boutons de la barre d'outils, onglet par agent | terminal | M2 |
| 8 | [run](run/) | commandes du workspace → surface terminal, palette `cmd+r`, bouton ▶ Run | terminal, `Palette` | M3 |
| 9 | [git](git/) | changes, diff, historique, remote, branches | explorer, editor (`Editor.open`), `Highlight` | M4 |
| 10 | [postgres](postgres/) | connexion unique, schéma, requêtes, résultats | layout, `Highlight` | M5 |
| 11 | [design](design/) | identité visuelle : tokens de `ThemeService`, îlots, barres plates, thème Dark (transverse, aucune feature) | layout, terminal (`ThemeService`) | M8 |

`Palette` et `Highlight` sont des dossiers partagés (`architecture.md`), livrés tous deux avec `editor` (M1 : quick open et highlighting). Le terminal vient après l'éditeur : l'app doit déjà être utilisable (ouvrir, lire, éditer) avant d'héberger des process.

Le découpage en tâches et l'avancement sont dans [`../backlog/`](../backlog/), un fichier par milestone.

Chaque dossier contient :

| Fichier | Rôle |
|---|---|
| `NN-study.md` | étude(s), numérotée(s) dans l'ordre d'écriture : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `questions.md` | questions ouvertes ; une question tranchée devient une ligne de `decisions.md` |
