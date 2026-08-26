# agents — Étude

## Objectif

Feature `agents` : lancer et retrouver les **agents CLI** (Claude Code, Antigravity CLI, OpenCode…) dans un onglet terminal dédié par agent, d'un clic sur un bouton de la barre d'outils (`layout` R30). Les agents intégrés sont connus de Wraith et affichés s'ils sont installés ; `config.agents` en ajoute ou en surcharge.

Ce n'est **pas** du `run` : une commande `run` est définie par l'utilisateur et vit dans la palette ; un agent est un outil connu de Wraith, avec son bouton, son icône et son onglet réutilisé.

## User stories

- US1 — J'ouvre un workspace : les boutons des agents installés sur ma machine apparaissent dans la barre d'outils, rien à configurer.
- US2 — Je clique « Claude » : un onglet `Claude` s'ouvre à la racine du workspace et lance `claude`. Je reclique : l'onglet existant est activé, aucun doublon.
- US3 — Clic droit sur le bouton : « Nouvelle session » ou « Lancer dans `backend` » pour choisir le repo.
- US4 — Je vois d'un coup d'œil si l'agent tourne ou attend (badge sur le bouton et l'onglet).
- US5 — J'ajoute mon agent maison ou je change les options de `claude` dans `config.json` : le bouton suit sans redémarrer.

## Règles fonctionnelles

### Agents intégrés et détection

- R1 — Agents intégrés (id, titre, binaire, commande par défaut) :

  | id | Titre | Binaire | Commande |
  |---|---|---|---|
  | `claude` | Claude Code | `claude` | `claude` |
  | `antigravity` | Antigravity | `antigravity` (à vérifier, voir questions) | `antigravity` |
  | `opencode` | OpenCode | `opencode` | `opencode` |

- R2 — Un agent intégré est **affiché** si son binaire est trouvé dans le `PATH` de l'environnement du login shell (le même que celui des terminaux, `terminal` R3, résolu une fois par `Workspace`). Non trouvé → bouton absent, sans message. La détection est refaite à chaque `Workspace.configChanges` et à l'ouverture de la fenêtre, jamais en polling.
- R3 — `config.agents` (`config` R3) : `{ "<id>": { "title"?, "command"?, "icon"?, "enabled"? } }`. Un id intégré surcharge ses champs (ex. `"claude": { "command": "claude --continue" }`) ; un id inconnu déclare un agent personnalisé (`command` obligatoire, toujours affiché, pas de détection) ; `"enabled": false` masque un intégré. Précédence `config` R4. Id : `[a-z0-9][a-z0-9_-]*`.

### Lancement et onglet

- R4 — Clic sur le bouton : s'il existe un onglet `agent.<id>` dans la fenêtre → il est activé (et son groupe reçoit le focus) ; sinon → `TerminalService.spawn(command:, cwd: racine, kind: "agent.<id>", title:)` dans le groupe actif (`terminal` R16) : le process démarre immédiatement, sans shell. **Un onglet par agent par fenêtre** en usage normal.
- R5 — Menu du bouton (clic droit ou clic long) : *Nouvelle session* (force un nouvel onglet `agent.<id>`, non réutilisé ensuite : seul le premier onglet créé est celui du bouton), *Lancer dans …* pour chaque repo de `config.repos`/auto-détection (cwd = le repo). La commande est passée telle quelle (`architecture.md`, sécurité), sans `env` ni templating.
- R6 — État = celui de l'onglet terminal (`terminal` R6) : `idle` / `running` / `exited(code)`. Badge : point sur le bouton et sur l'onglet quand `running` ; la bell d'un onglet agent inactif marque l'onglet (`terminal` R7) et le bouton. Agent quitté (`exited`) : la surface reste figée avec *Relancer* (`terminal` R8) ; cliquer le bouton de l'agent relance dans ce même onglet.
- R7 — Fermeture : `terminal` R10–R11 (confirmation si l'agent tourne ; arrêt propre).
- R8 — Restauration (`layout` R28) : onglet recréé en état `idle` au même cwd, titre conservé, surface vide avec *Relancer* ; la commande **n'est pas relancée** automatiquement (même choix que `run` R13). Voir question ouverte.
- R9 — Raccourcis : `config.shortcuts["agents.<id>"]`, aucun défaut. Portée globale. `cmd+opt+t` masque la barre d'outils (`layout` R32), les raccourcis restent actifs.

## Cas limites

- Binaire présent mais commande qui échoue (version, login requis) : l'erreur s'affiche dans la surface, état `exited(code)`, pas de bannière.
- Deux fenêtres : un onglet par agent **par fenêtre**, indépendants.
- L'utilisateur quitte l'agent (`/exit`) : `exited(0)`, surface figée ; le bouton de l'agent relance dans le même onglet.
- Agent qui lance des sous-process : ils sont dans le groupe de process du PTY et suivent l'onglet (`terminal` R9, R11).
- `PATH` sans le binaire mais alias/fonction shell : non détecté ; déclarer l'agent dans `config.agents` (pas de détection pour un agent déclaré).

## Hors périmètre v1

- Intégration profonde : envoyer un chemin/une sélection à l'agent, ouvrir automatiquement le diff des fichiers qu'il modifie, lire son état autrement que par le terminal. (Candidats v2 ; le diff git et l'explorer se rafraîchissent déjà par FSEvents.)
- MCP, API, hooks, sessions nommées, historique des sessions.
- Agents non-CLI (extensions, apps).

## Options techniques

- **Dossier** : `Agents/` (`architecture.md`). `AgentsFeature` déclare à `Layout` un élément de toolbar par agent (côté `leading`, `layout` R30) et un kind d'onglet `agent.<id>` dont le payload est `{ "id", "cwd" }` ; la vue de l'onglet est la surface terminal de `TerminalService` (l'onglet `run` fait pareil, `run` R7).
- **Détection** : `Workspace` expose l'environnement du login shell (PATH) ; recherche de l'exécutable par simple parcours des entrées du PATH (`FileManager.isExecutableFile`), hors main actor. Aucun shell lancé pour détecter.
- **Icônes** : SF Symbols (`icon` = nom de symbole) ; les intégrés ont un symbole par défaut.
- **Tests** : parsing/fusion de `config.agents` avec les intégrés (R3), résolution du PATH sur un dossier temporaire (R2), machine d'états d'un bouton/onglet (R4, R6, R8) pilotée par des événements terminal simulés.

## Décisions

Voir [decisions.md](decisions.md).
