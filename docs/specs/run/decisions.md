# run — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-27 | R3b : une seule source de commandes, `.wraith/config.json` | Précédence global/workspace | Config globale supprimée (config, 2026-08-26) |
| 2026-08-27 | `cmd+.` (`run.stop`) en portée `terminal`, no-op hors onglet `run.*` | Une action `tab(kind: "run.<id>")` par commande | Une action, une ligne de raccourci ; `ShortcutRegistry` n'a pas de désenregistrement |
| 2026-08-27 | Relance d'un onglet `running` (R7) orchestrée dans `Run/` (`SIGINT`, attente d'`exited` 10 s, `relaunch`) ; `TerminalService` inchangé | `relaunch` qui arrête lui-même | M2 : `run` réutilise `TerminalService` tel quel ; l'attente est un besoin de `run` seul |
| 2026-08-27 | Badge d'onglet R10 posé par `Run/` par-dessus celui de `TerminalService` ; `blue` ajouté à `ToolbarBadge` | Couleurs paramétrables dans `TerminalService` | Une ligne dans `Layout/` contre une abstraction pour deux appelants |
| 2026-08-27 | « Dernières lancées en premier » (R5) : liste en mémoire par fenêtre | Champ dans `state.json` | Pas de migration de format pour un confort ; à revoir à l'usage |
| 2026-08-27 | Commande retirée de la config : ses onglets ouverts restent, un onglet persisté n'est pas restauré (kind non enregistré) ; son raccourci `run.<id>` reste enregistré et ne fait rien | Commande dans le payload de l'onglet | Même politique que `agents` ; le layout ignore déjà un kind inconnu |
| 2026-08-26 | Palette `cmd+r` **et** bouton ▶ Run (menu) dans la barre d'outils ; pas de panneau | Palette seule (décision du 2026-08-25) ; panneau de boutons | Un clic pour le quotidien, la palette pour le clavier ; le panneau coûterait un slot |
| 2026-08-26 | Les agents CLI ne sont pas des commandes `run` | Déclarer `claude` dans `commands` | Un run est défini par l'utilisateur ; un agent est connu de Wraith (`agents`) |
| 2026-08-25 | Un onglet terminal par commande (`repo:nom`), réutilisé ; relance = `ctrl+c` puis renvoi ; `cmd+enter` force un nouvel onglet | Nouvel onglet à chaque fois | Évite l'accumulation ; le cas « je veux garder l'ancien » a son raccourci |
| 2026-08-25 | Config seulement : pas de détection auto, pas de séquences ni dépendances | Détection `package.json`/`Makefile` ; `"deploy": ["build","test"]` | Explicite et prévisible ; `a && b` couvre les séquences |
| 2026-08-26 | `env` par commande ou par repo, injecté dans l'environnement du process (remplace « préfixé `K=V` à la commande » du 2026-08-25) ; la commande elle-même n'est jamais modifiée | Préfixe `K=V` dans la ligne ; templating | Wraith lance le process (`terminal` R3) : plus rien à échapper |
| 2026-08-26 | État running/exit code dérivé de la fin du process (`terminal` R6) (remplace « OSC 133 » du 2026-08-25) | Shell integration ; process hors terminal | Wraith lance le process : fiable quel que soit le shell ; l'environnement du login shell est conservé par `$SHELL -l -c` |
| 2026-08-25 | Arrêt : `cmd+.` → `SIGINT`, second appui → `SIGTERM` ; jamais `SIGKILL` automatique | Kill direct | Laisser le process s'arrêter proprement (serveurs, DB) |
| 2026-08-25 | La palette (fuzzy + UI) est un dossier partagé (`Palette/`), commun au quick open et à `run` | Composant dupliqué dans chaque feature | `architecture.md` : ce dont deux features ont besoin vit dans un dossier partagé |
