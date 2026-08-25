# editor — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Éditeur simple : saisie, undo, indentation, recherche/remplacement dans le fichier, `cmd+s` ; pas de complétion ni LSP | Viewer seul ; éditeur ambitieux (LSP, multi-curseurs) | Éditer un README ou une config sans quitter Wraith ; le gros du code s'édite ailleurs |
| 2026-08-25 | `NSTextView` sur TextKit 2, confiné | Vue custom ; TextKit 1 | Undo/IME/accessibilité gratuits ; attributs par plage adaptés aux `HighlightSpan` ; à valider par prototype |
| 2026-08-25 | Set large de grammaires (java, kotlin, ts/tsx, js, json, yaml, toml, markdown, sql, bash, swift, html, css, dockerfile) | Set minimal (java, ts, markdown, sql) | Ajouter une grammaire = une ligne de mapping ; autant couvrir le quotidien |
| 2026-08-25 | `cmd+s` explicite, pas d'autosave ; reload silencieux si non modifié, bannière de conflit sinon | Autosave ; jamais de reload | Sûr avec les watchers/builds ; comportement VS Code connu |
| 2026-08-25 | Markdown : bascule source/preview dans l'onglet (`cmd+shift+v`) | Preview côte à côte synchronisée | Simplicité ; le split manuel existe si besoin |
| 2026-08-25 | `cmd+p` fuzzy sur les chemins, index construit à la première ouverture ; `cmd+shift+f` recherche contenu via `rg` (repli `grep`) dans un panneau bas | Index au démarrage ; recherche contenu maison ; pas de recherche contenu | `coding-rules` P4/R15.2 ; `rg` est plus rapide et plus juste (gitignore) que tout ce qu'on écrirait |
| 2026-08-26 | Palette et highlighting consommés depuis le noyau (`PaletteService`, `HighlightService`) au lieu d'être implémentés dans le plugin | Fuzzy maison et tree-sitter dans `PluginEditor` | `coding-rules` R5.10 : `run`, `git`, `postgres` en ont besoin aussi ; une lib de fuzzy plutôt que réinventer |
| 2026-08-25 | Binaire refusé (octet nul / extension) ; > 2 Mo lecture seule sans highlighting ; > 50 Mo refusé | Lecture tronquée | Un éditeur simple n'a pas à gérer les gros fichiers ; refuser vaut mieux qu'un affichage faux |
| 2026-08-25 | Fichier disparu à la restauration : onglet ignoré (tranche la question laissée par `product`) | Onglet vide en lecture seule | Rien à afficher ; `layout` R28 le prévoit déjà |
| 2026-08-25 | Raccourcis de l'éditeur à portée « onglet éditeur actif » (le `ShortcutRegistry` supporte une portée par kind d'onglet) | Raccourcis globaux | `cmd+f`/`cmd+s` ne doivent rien voler à un terminal focalisé |
