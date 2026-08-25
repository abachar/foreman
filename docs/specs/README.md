# Specs

Les règles de codage transverses (langage, architecture, concurrence, dépendances, tests) sont dans [`../coding-rules.md`](../coding-rules.md).

Un dossier par domaine, dans l'ordre de dépendance. Chaque dossier contient l'étude, les décisions, le découpage et la progression (voir le `README.md` de chaque dossier).

| Dossier | Domaine |
|---|---|
| [00-product](00-product/) | vision, utilisateurs cibles, non-objectifs, distribution |
| [01-config](01-config/) | `.wraith.json`, workspace, secrets |
| [02-layout](02-layout/) | zones, PanelManager, ShortcutRegistry |
| [03-terminal](03-terminal/) | PTY, libghostty, onglets |
| [04-explorer](04-explorer/) | arbre de fichiers, FSEvents |
| [05-editor](05-editor/) | viewer/éditeur, highlighting, markdown, quick open |
| [06-git](06-git/) | changes, diff, historique |
| [07-postgres](07-postgres/) | connexion, schéma, requêtes |
| [08-run](08-run/) | commandes du workspace → terminal |
