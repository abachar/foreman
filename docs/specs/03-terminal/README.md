# terminal

| Fichier | Rôle |
|---|---|
| `00-study.md` | étude : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `01-decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `02-breakdown.md` | découpage en tâches |
| `03-progress.md` | avancement |

## Questions ouvertes

- [ ] Shell : `$SHELL` de l'utilisateur ou `zsh` forcé ? Login shell (`-l`) ou non ?
- [ ] Nouveau terminal : cwd = racine du workspace, ou cwd du terminal actif ?
- [ ] Fermeture : quand le shell se termine (`exit`), l'onglet se ferme seul ou reste avec un message ?
- [ ] Confirmation avant de fermer un onglet dont un process tourne encore (ex. serveur) ?
- [ ] libghostty : quelle version de Ghostty pinner ? Build via `zig` intégré au projet ou binaire pré-compilé vendored ?
- [ ] Fonctionnalités Ghostty à exposer en v1 : recherche, sélection/copie, liens cliquables, thèmes, police ?
- [ ] Terminal ↔ app : notifier quand une commande finit (bell / OSC 133) ? Titre d'onglet dynamique (OSC 0/2) ?
- [ ] Shell integration : injecter celle de Ghostty pour le suivi du cwd et des commandes ?
