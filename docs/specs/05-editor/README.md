# editor

| Fichier | Rôle |
|---|---|
| `00-study.md` | étude : objectif, user stories, règles fonctionnelles (R1, R2…), cas limites, hors périmètre, options techniques |
| `01-decisions.md` | décisions prises (date, choix, alternatives rejetées, raison) |
| `02-breakdown.md` | découpage en tâches |
| `03-progress.md` | avancement |

## Questions ouvertes

- [ ] Éditeur réel ou viewer en priorité ? Quel niveau d'édition v1 (saisie, undo, sauvegarde, indentation auto) ?
- [ ] Composant : `NSTextView`, `TextKit 2`, ou vue custom ? (impacte le highlighting tree-sitter)
- [ ] Grammaires tree-sitter v1 : java, typescript, markdown, sql — d'autres (swift, json, yaml, bash) ?
- [ ] Markdown : preview seule, ou côte à côte avec la source ?
- [ ] Quick open `cmd+p` : fuzzy sur les chemins uniquement, ou aussi recherche dans le contenu (`cmd+shift+f`) ?
- [ ] Fichiers binaires / très gros fichiers : refus, ou lecture tronquée ?
- [ ] Sauvegarde : `cmd+s` explicite uniquement, ou autosave ?
- [ ] Rechargement si le fichier change sur disque (FSEvents) : automatique si non modifié, conflit sinon ?
