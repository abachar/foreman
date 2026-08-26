# config — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Dossier `.wraith/` à la racine du workspace : `config.json` (utilisateur) + `state.json` (app) | Fichier unique `.wraith.json` (README initial) | Séparer ce que l'utilisateur écrit de ce que l'app écrit ; extensible |
| 2026-08-25 | Config globale dans `~/.config/wraith/config.json` | `~/.wraith/`, `~/Library/Application Support` | Convention XDG, éditable à la main, pas de collision avec un workspace `$HOME` |
| 2026-08-25 | Secrets uniquement dans le Keychain | Champ `password` en clair | Sécurité, fichier potentiellement versionné |
| 2026-08-25 | Rechargement à chaud de `config.json`, pas de `state.json` | Redémarrage requis | Confort ; `state.json` n'est écrit que par l'app |
| 2026-08-26 | Changement de config diffusé par un `AsyncStream` de `Workspace`, pas par un bus d'événements | `EventBus` + événement `configChanged` (2026-08-25) | `architecture` : pas d'`EventBus`, le propriétaire de l'information expose un flux |
| 2026-08-25 | Raccourcis en chaîne ASCII `"cmd+shift+g"` (modificateurs `cmd`, `shift`, `alt`, `ctrl`, touche en minuscule) | Notation `⌘⇧G` | Lisible, saisissable au clavier, sans ambiguïté d'encodage |
| 2026-08-26 | Fusion global/workspace : une section objet dans les deux fichiers est fusionnée clé par clé (un niveau, le workspace prime) ; toute autre valeur est remplacée | Remplacement de la section entière ; fusion récursive profonde | Surcharger un seul raccourci ou une seule commande sans recopier les globaux, sans la complexité d'une fusion profonde |
