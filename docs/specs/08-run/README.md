# run

| Fichier | Rôle |
|---|---|
| `00-study.md` | étude : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `01-decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `02-breakdown.md` | découpage en tâches |
| `03-progress.md` | avancement |

## Questions ouvertes

- [ ] Surface : palette de commandes (`cmd+r`) uniquement, ou aussi boutons/panel ?
- [ ] Une commande → un onglet terminal dédié réutilisé (même nom), ou un nouvel onglet à chaque exécution ?
- [ ] Commande longue (serveur) : arrêt via `cmd+.` / SIGINT ? Relance = kill + restart ?
- [ ] Commandes composées / séquentielles (`build` puis `test`) ou dépendances entre commandes ?
- [ ] Variables d'environnement par commande ou par repo dans la config ?
- [ ] Détection auto de commandes (`package.json` scripts, `Makefile`, `pom.xml`) en plus de la config ?
- [ ] Indicateur d'état (running / exit code) sur l'onglet ?
