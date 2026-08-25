# terminal — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-26 | **SwiftTerm seul** ; libghostty abandonné (remplace « libghostty embedded » du 2026-08-25) | libghostty principal + SwiftTerm repli ; SwiftTerm principal + libghostty optionnel | Le besoin est d'afficher des TUI d'agents et des sorties de build, pas d'être un émulateur de terminal ; SwiftTerm suffit, sans build zig ni C vendorisé |
| 2026-08-26 | **Wraith possède le PTY et le process** (`PTYSession` maison, `forkpty`) ; SwiftTerm ne fait que VT + rendu | `LocalProcessTerminalView` de SwiftTerm | État (pid, exit code), signaux et fermeture déterministe sont des besoins de `agents`/`run` ; on les tient nous-mêmes |
| 2026-08-26 | Un onglet = **un process** lancé via `$SHELL -l -c "<commande>"`, sans prompt ; process terminé → surface figée + *Relancer* | Shell interactif dans lequel on `send()` la commande ; fermeture auto à la fin | Pas de shell libre (`product` R4) ; l'environnement du login shell est conservé ; la sortie reste lisible après la fin |
| 2026-08-26 | État et cwd via le PTY (`waitpid`, cwd de lancement), **pas de shell integration** OSC 7/133 | Injecter la shell integration | Fiable quel que soit le shell ; plus rien à injecter |
| 2026-08-26 | Titre fixe fourni par le plugin ; OSC 0/2 en sous-titre seulement | Titre dynamique | Les onglets sont `Claude`, `backend:test`… l'identité prime |
| 2026-08-26 | Apparence (police, thème) gérée par Wraith via `ThemeService` + config globale | Config Ghostty de l'utilisateur | Plus de Ghostty ; un thème unique pour toute l'UI |
| 2026-08-25 | `cmd+w` demande confirmation si le process tourne ; `SIGKILL` seulement en fermeture forcée après 5 s | Kill direct ; jamais de confirmation | On évite de tuer un serveur ou un agent par erreur |
| 2026-08-25 | Raccourcis `cmd+…` de Wraith prioritaires sur la surface | Surface gagne | Les onglets/splits sont ceux de Wraith |
