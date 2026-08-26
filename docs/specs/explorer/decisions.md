# explorer — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Dotfiles visibles ; entrées gitignored et dossiers de la liste d'exclusion grisés ; `.git/` masqué ; toggle pour cacher les grisés | Dotfiles masqués (Finder) ; tout visible sans grisage | On travaille souvent dans `.github`, `.env.example`… ; le grisage donne l'info sans cacher |
| 2026-08-25 | CRUD de base (créer, renommer, supprimer vers la corbeille, révéler, copier chemin), pas de drag & drop (« terminal ici » retiré le 2026-08-26, `product` R4) | Lecture seule ; CRUD + D&D | Le quotidien sans le coût du D&D ; le déplacement se fait par l'agent ou hors Wraith |
| 2026-08-25 | Simple clic = onglet aperçu (remplacé), double clic ou édition = onglet fixe | Simple clic = onglet fixe | Modèle VS Code, évite l'accumulation d'onglets |
| 2026-08-25 | L'arbre suit l'onglet actif (toggle persisté) et affiche les badges git reçus de `Git.statusChanges` | Arbre indépendant ; explorer qui lit git lui-même | Une seule source de statut git ; l'explorer ne lance jamais `git` |
| 2026-08-25 | Chargement par niveau, rechargement ciblé du dossier parent sur FSEvents, jamais de parcours récursif | Index complet du workspace en mémoire | Paresse (`architecture.md` P4) ; workspace `$HOME` possible |
| 2026-08-25 | Suppression vers la corbeille avec confirmation, jamais de suppression définitive | `rm -rf` direct | Réversible ; le terminal est là pour le définitif |
| 2026-08-26 | Vue = `NSOutlineView` avec data source paresseux ; rechargement par `reloadItem(_:reloadChildren:)`, pas de fusion d'arbre maison | `List`/`OutlineGroup` SwiftUI ; modèle d'arbre fusionné à la main | Plateforme d'abord (`architecture.md` P3) : performance sur gros dossiers, préservation d'état gratuite |
| 2026-08-27 | Nouveau fichier / dossier : nom saisi dans une feuille (`NSAlert` + champ) ; renommer reste en ligne dans la cellule | Ligne fantôme éditable dans l'`NSOutlineView` | Une ligne fantôme demande un item factice dans le data source et sa synchronisation ; la feuille fait le travail en 20 lignes |
