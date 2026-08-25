# explorer — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Dotfiles visibles ; entrées gitignored et dossiers de la liste d'exclusion grisés ; `.git/` masqué ; toggle pour cacher les grisés | Dotfiles masqués (Finder) ; tout visible sans grisage | On travaille souvent dans `.github`, `.env.example`… ; le grisage donne l'info sans cacher |
| 2026-08-25 | CRUD de base (créer, renommer, supprimer vers la corbeille, révéler, copier chemin), pas de drag & drop (« terminal ici » retiré le 2026-08-26, `product` R4) | Lecture seule ; CRUD + D&D | Le quotidien sans le coût du D&D ; le déplacement se fait par l'agent ou hors Wraith |
| 2026-08-25 | Simple clic = onglet aperçu (remplacé), double clic ou édition = onglet fixe | Simple clic = onglet fixe | Modèle VS Code, évite l'accumulation d'onglets |
| 2026-08-25 | L'arbre suit l'onglet actif (toggle persisté) et affiche les badges git reçus via l'`EventBus` | Arbre indépendant ; explorer qui lit git lui-même | Couplage par événements uniquement (`coding-rules` R4.1) : l'explorer ne sait pas ce qu'est git |
| 2026-08-25 | Chargement par niveau, relecture ciblée du dossier parent sur FSEvents, jamais de parcours récursif | Index complet du workspace en mémoire | `coding-rules` R15.3 ; workspace `$HOME` possible |
| 2026-08-25 | Suppression vers la corbeille avec confirmation, jamais de suppression définitive | `rm -rf` direct | Réversible ; le terminal est là pour le définitif |
