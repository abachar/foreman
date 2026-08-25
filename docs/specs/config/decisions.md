# config — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Dossier `.wraith/` à la racine du workspace : `config.json` (utilisateur) + `state.json` (app) | Fichier unique `.wraith.json` (README initial) | Séparer ce que l'utilisateur écrit de ce que l'app écrit ; extensible |
| 2026-08-25 | Config globale dans `~/.config/wraith/config.json` | `~/.wraith/`, `~/Library/Application Support` | Convention XDG, éditable à la main, pas de collision avec un workspace `$HOME` |
| 2026-08-25 | Secrets uniquement dans le Keychain | Champ `password` en clair | Sécurité, fichier potentiellement versionné |
| 2026-08-25 | Rechargement à chaud de `config.json`, pas de `state.json` | Redémarrage requis | Confort ; `state.json` n'est écrit que par l'app |
| 2026-08-25 | Raccourcis en chaîne ASCII `"cmd+shift+g"` (modificateurs `cmd`, `shift`, `alt`, `ctrl`, touche en minuscule) | Notation `⌘⇧G` | Lisible, saisissable au clavier, sans ambiguïté d'encodage |
