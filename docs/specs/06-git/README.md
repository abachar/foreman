# git

| Fichier | Rôle |
|---|---|
| `00-study.md` | étude : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `01-decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `02-breakdown.md` | découpage en tâches |
| `03-progress.md` | avancement |

## Questions ouvertes

- [ ] Panel « changes » : un repo à la fois (sélecteur) ou tous les repos empilés ?
- [ ] Actions en v1 : stage/unstage, discard, commit (message + éditeur), ou lecture seule (status + diff) ?
- [ ] Diff : côte à côte et/ou inline ? Diff d'un fichier uniquement, ou du commit entier ?
- [ ] Historique : log linéaire, ou graphe des branches ?
- [ ] Branches : lister/changer de branche, ou laisser ça au terminal ?
- [ ] Implémentation : libgit2 (SwiftGit2) ou appel au binaire `git` (plus simple, fidèle à la config utilisateur) ?
- [ ] Rafraîchissement : FSEvents sur `.git/` (index, HEAD, refs) + fichiers du worktree ?
