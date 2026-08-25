# agents — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-26 | Domaine `agents` distinct de `run` : boutons dédiés dans la barre d'outils | Agents déclarés comme commandes `run` | Un run est défini par l'utilisateur ; un agent est un outil connu de Wraith, avec bouton, icône et onglet réutilisé |
| 2026-08-26 | Agents intégrés (Claude Code, Antigravity, OpenCode) détectés dans le PATH + `config.agents` pour ajouter/surcharger/masquer | Config uniquement ; liste fixe sans config | Zéro config dans le cas courant, extensible pour un agent maison ou des options |
| 2026-08-26 | Un onglet par agent, réutilisé : le bouton active l'onglet existant, sinon le crée ; « Nouvelle session » via le menu | Nouvel onglet à chaque clic ; menu de choix du dossier avant chaque lancement | Évite les doublons ; le cas rare a son entrée de menu |
| 2026-08-26 | L'agent vit sur une surface terminal (le seul usage du terminal avec `run`, `product` R4) ; état dérivé de la fin du process (`terminal` R6) ; aucune intégration profonde en v1 | Pont agent ↔ workspace (sélection, diff auto) | Livrer d'abord le lancement ; explorer/git se rafraîchissent déjà par FSEvents |
| 2026-08-26 | Restauration sans relance de la commande | Relance automatique | Même règle que `run` R13 ; une relance implicite peut consommer des sessions/tokens |
