# run — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-26 | Palette `cmd+r` **et** bouton ▶ Run (menu) dans la barre d'outils ; pas de panneau | Palette seule (décision du 2026-08-25) ; panneau de boutons | Un clic pour le quotidien, la palette pour le clavier ; le panneau coûterait un slot |
| 2026-08-26 | Les agents CLI ne sont pas des commandes `run` | Déclarer `claude` dans `commands` | Un run est défini par l'utilisateur ; un agent est connu de Wraith (`agents`) |
| 2026-08-25 | Un onglet terminal par commande (`repo:nom`), réutilisé ; relance = `ctrl+c` puis renvoi ; `cmd+enter` force un nouvel onglet | Nouvel onglet à chaque fois | Évite l'accumulation ; le cas « je veux garder l'ancien » a son raccourci |
| 2026-08-25 | Config seulement : pas de détection auto, pas de séquences ni dépendances | Détection `package.json`/`Makefile` ; `"deploy": ["build","test"]` | Explicite et prévisible ; `a && b` couvre les séquences |
| 2026-08-26 | `env` par commande ou par repo, injecté dans l'environnement du process (remplace « préfixé `K=V` à la commande » du 2026-08-25) ; la commande elle-même n'est jamais modifiée | Préfixe `K=V` dans la ligne ; templating | Wraith lance le process (`terminal` R3) : plus rien à échapper |
| 2026-08-26 | État running/exit code dérivé de la fin du process (`terminal` R6) (remplace « OSC 133 » du 2026-08-25) | Shell integration ; process hors terminal | Wraith lance le process : fiable quel que soit le shell ; l'environnement du login shell est conservé par `$SHELL -l -c` |
| 2026-08-25 | Arrêt : `cmd+.` → `SIGINT`, second appui → `SIGTERM` ; jamais `SIGKILL` automatique | Kill direct | Laisser le process s'arrêter proprement (serveurs, DB) |
| 2026-08-25 | La palette (fuzzy + UI) est un dossier partagé (`Palette/`), commun au quick open et à `run` | Composant dupliqué dans chaque feature | `architecture.md` : ce dont deux features ont besoin vit dans un dossier partagé |
