# postgres

| Fichier | Rôle |
|---|---|
| `00-study.md` | étude : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `01-decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `02-breakdown.md` | découpage en tâches |
| `03-progress.md` | avancement |

## Questions ouvertes

- [ ] Une seule connexion (celle de la config) ou plusieurs profils nommés ?
- [ ] Schéma : tables, vues, colonnes, index, contraintes, fonctions ? Jusqu'où descendre en v1 ?
- [ ] Éditeur SQL : réutilise 05-editor avec grammaire SQL ; exécution de la sélection ou de la requête courante ?
- [ ] Résultats : grille paginée ? Limite par défaut (ex. 500 lignes) ? Export CSV/JSON ?
- [ ] Édition des données dans la grille, ou lecture seule ?
- [ ] Transactions : autocommit, ou begin/commit/rollback explicites ?
- [ ] Historique des requêtes persisté (`.wraith/`) ?
- [ ] Mot de passe : saisie au premier usage puis Keychain ; support de `~/.pgpass` ?
