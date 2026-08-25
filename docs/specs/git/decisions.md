# git — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Binaire `git` via `Process`, formats machine (`--porcelain=v2 -z`, `--format`) | libgit2 / SwiftGit2 | Hooks, signing, credential helpers, `pull.rebase`… honorés gratuitement ; zéro C à enfermer ; SwiftGit2 peu maintenu |
| 2026-08-25 | Périmètre complet : status, stage/unstage/discard, commit/amend, diff par hunk, log, fetch/pull/push, branches, stash | Lecture seule ; stage+commit seulement | Le terminal reste disponible, mais le quotidien tient dans le panneau |
| 2026-08-25 | Tous les repos empilés en sections repliables | Un repo à la fois | Vue d'ensemble d'un workspace multi-repos (cas d'usage principal) |
| 2026-08-25 | Diff unifié inline dans un onglet central ; log linéaire `--first-parent` en panneau bas | Côte à côte ; graphe de branches | Suffisant pour relire avant commit ; le graphe est un gros chantier de rendu |
| 2026-08-26 | Diff coloré via le dossier partagé `Highlight/` (remplace la décision « sans highlighting » du 2026-08-25) | tree-sitter importé dans `Git/` ; diff +/− seul | Le highlighting est un composant partagé (`architecture.md`) ; `Git/` l'appelle directement |
| 2026-08-26 | `GIT_TERMINAL_PROMPT=0` ; interaction requise → bannière avec la commande à copier, pas de terminal ouvert (remplace « bascule dans un terminal » du 2026-08-25) | Saisie de credentials dans Wraith ; surface terminal éphémère | Aucun secret dans l'app (`architecture.md`, sécurité) ; pas de shell libre (`product` R4) ; le cas est rare avec un helper/agent SSH configuré |
| 2026-08-25 | Discard, drop stash, `-D`, checkout de commit, reset, cherry-pick, revert : confirmés ; `reset --hard` et `push --force` absents de l'UI | Tout accessible ; rien de destructif | Le destructif reste explicite ; l'irréversible reste au terminal |
| 2026-08-25 | Jamais de `fetch` automatique ; rafraîchissement par FSEvents (worktree + `.git/HEAD`, `index`, `refs/`) | Polling ; fetch périodique | Aucun réseau non demandé, pas de polling disque (`architecture.md`) |
| 2026-08-26 | `GitCLI` type concret, pas de protocole `GitService` ni de `FakeGitService` | Protocole + double de test | Une seule implémentation (`architecture.md` P1) ; les parseurs se testent sur fixtures, le panneau sur des `GitStatus` construits à la main |
| 2026-08-25 | Commit via `-F <fichier temporaire>`, sans `--no-verify` ni contournement de config | Message en argument ; option « skip hooks » | Messages multi-lignes sûrs ; les hooks de l'utilisateur sont sa politique, pas la nôtre |
