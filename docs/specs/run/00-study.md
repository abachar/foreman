# run — Étude

## Objectif

Feature `run` : lancer les commandes déclarées dans `config.json` (`commands`) sur une surface terminal du workspace, depuis une palette (`cmd+r`) ou le bouton **▶ Run** de la barre d'outils, avec un onglet terminal réutilisé par commande et un indicateur d'état. Pas de panneau. Aucune détection automatique, aucune composition : la config est la seule source. Les agents CLI ne sont pas des commandes `run` : voir [agents](../agents/).

## User stories

- US1 — `cmd+r`, je tape `bt`, `backend › test` remonte, `enter` : un onglet `backend:test` s'ouvre dans le dossier du repo et lance `mvn test`.
- US1b — Je clique ▶ dans la barre d'outils : la liste des commandes par repo s'affiche avec leur état ; un clic lance.
- US2 — Je relance la même commande : le même onglet est réutilisé (le process en cours est arrêté d'abord).
- US3 — Un onglet de commande inactif me montre si ça tourne, si ça a réussi ou échoué.
- US4 — `cmd+.` dans l'onglet d'une commande arrête le process proprement.
- US5 — Je modifie `config.json` : la palette reflète la nouvelle liste immédiatement.

## Règles fonctionnelles

### Config

- R1 — Section `commands` (`config` R3) : `{ "<repo ou .>": { "<nom>": "<commande>" | { "run": "<commande>", "cwd": "<sous-dossier>", "env": { "K": "V" } } } }`. La forme courte est une chaîne ; la forme longue ajoute `cwd` (relatif au repo, défaut le repo) et `env`. Un `env` au niveau du repo (clé réservée `"$env"`) s'applique à toutes ses commandes.
- R2 — Le `<repo>` doit être `.` ou un chemin relatif à la racine, existant sur disque (pas nécessairement un repo git). Absent : la commande est listée grisée avec la raison. `cwd` doit rester sous la racine (`architecture.md`, sécurité).
- R3 — Le nom d'une commande : `[a-z0-9][a-z0-9:_-]*`, unique par repo. Identifiant complet `repo:nom` (`.` devient `root`). Ces ids servent aux raccourcis (`config.shortcuts["run.backend:test"]`, R11).
- R3b — Une seule source : `.wraith/config.json` du workspace (`config` R4, décision config 2026-08-26 : pas de configuration globale). Deux workspaces ne partagent rien.
- R4 — Rechargement à chaud sur `Workspace.configChanges` (`config` R6) : la palette et les raccourcis sont recalculés ; un onglet en cours n'est pas affecté.

### Palette et bouton

- R5 — `cmd+r` ouvre une palette (`Palette`, dossier partagé, la même que le quick open). Entrées `repo › nom` avec la commande en sous-titre ; fuzzy sur `repo nom` ; ordre par défaut : dernières lancées en premier, puis alphabétique.
- R6 — `enter` lance (R7) ; `cmd+enter` lance dans un **nouvel** onglet (sans réutilisation) ; `opt+enter` copie la commande dans le presse-papiers. `escape` ferme.
- R6b — Bouton **▶ Run** (`run.toolbar`, élément de toolbar déclaré à `Layout`, côté `trailing`, de type menu, `layout` R30) : le menu liste les commandes groupées par repo, avec la commande en sous-titre et le badge d'état (R10) de l'onglet correspondant ; un clic lance (R7). Le bouton porte un badge bleu si au moins une commande tourne, rouge si la dernière terminée a échoué (effacé à l'activation de l'onglet). Sans aucune commande configurée, le menu affiche un exemple de config. Ni `commands` ni bouton ne sont touchés par les agents.

### Exécution

- R7 — Lancer `repo:nom` : si un onglet `run.<id>` existe → il est activé ; s'il est `running`, le process reçoit `SIGINT` (R9) et, après `exited`, `TerminalService.relaunch` ; s'il est `idle`/`exited`, `relaunch` direct. Sinon → `TerminalService.spawn(command:, cwd:, env:, kind: "run.<id>", title: "repo:nom")` (`terminal` R16) : le process démarre immédiatement, sans shell ni prompt.
- R8 — La commande est passée **telle quelle** à `$SHELL -l -c` (`terminal` R1) ; les `env` sont injectés dans l'environnement du process (`terminal` R3), jamais préfixés dans la ligne de commande. Rien n'est recomposé (`architecture.md`, sécurité) : la commande est le texte de l'utilisateur.
- R9 — Arrêt : `cmd+.` (portée `terminal`, sans effet hors d'un onglet `run.*`, décision 2026-08-27) envoie `SIGINT` au groupe de process (`terminal` R9) ; un second `cmd+.` dans les 2 s envoie `SIGTERM` ; jamais `SIGKILL` automatique. Relance (R7) = arrêt puis attente d'`exited` (10 s max, puis abandon avec bannière) avant `relaunch`.
- R10 — État par onglet `run` : `idle` / `running` / `succeeded` / `failed(code)`, dérivé de `terminal` R6 (`exited(0)` → `succeeded`, sinon `failed`). Badge sur l'onglet : point bleu (running), vert (0), rouge (≠ 0) ; effacé à l'activation de l'onglet après la fin, ou à la relance.
- R11 — Raccourci par commande : `config.shortcuts["run.<id>"]` (`config` R3) ; aucun défaut. Portée globale.
- R12 — Fermeture d'un onglet `run` en `running` : confirmation (`terminal` R10). Fermeture de la fenêtre : idem, une confirmation par onglet.
- R13 — Les onglets `run` sont restaurés (`layout` R28) en état `idle` au même cwd, titre conservé, surface vide avec *Relancer* ; la commande n'est **pas** relancée.

## Cas limites

- Commande qui lance un shell interactif ou un TUI : fonctionne (c'est une surface terminal) ; la relance passe par `SIGINT` puis `relaunch`, jamais par du texte envoyé.
- `commands` contient un `env` avec un secret : `config` R11 (clé `password`) s'applique ; autres clés acceptées — c'est le choix de l'utilisateur.
- Deux workspaces déclarant la même commande : indépendants (onglets par fenêtre).
- Nom de commande en conflit avec une clé réservée (`$env`) : ignoré avec avertissement dans la palette.

## Hors périmètre v1

- Détection automatique (`package.json`, `Makefile`, `pom.xml`).
- Séquences, dépendances, commandes parallèles, tâches en arrière-plan sans terminal.
- Panneau dédié ; commandes dans le menu de l'app.
- Capture/parsing de la sortie (problèmes, liens vers erreurs de compilation).
- Variables/templating dans les commandes (`${file}`, `${branch}`).

## Options techniques

- **Dossier** : `Run/` (`architecture.md`). `RunFeature` déclare à `Layout` l'élément de toolbar `run.toolbar` et le kind d'onglet `run.<id>`.
- **Palette partagée** : `Palette/` (dossier partagé, livré en M1) : `Palette.present(PaletteSource, over: NSWindow)` ; `PaletteSource(placeholder:, results: (String) async -> Results, select: (PaletteItem, newGroup: Bool) -> Void, secondary: ((PaletteItem) -> Void)?)` — `newGroup` = `cmd+enter` (nouvel onglet, R6), `secondary` = `opt+enter` (copier, R6 ; ajouté en M3) ; items `PaletteItem(id:, title: AttributedString, subtitle:)` ; fuzzy **FuzzyMatch** (`FuzzyMatcher.topMatches`), le même que le quick open (`editor` R17).
- **Signaux / état** : `TerminalService.signal(_:to:)`, `state(of:)`, événements `exited` (`terminal` R16) ; `relaunch` refuse un onglet `running` : la relance R7 (arrêt, attente d'`exited`, `relaunch`) vit dans `Run/`. Badge d'onglet : `Run/` repose le sien (bleu/vert/rouge, R10) à chaque événement de ses onglets, après celui de `TerminalService` (`terminal` R7) ; `ToolbarBadge.BadgeColor` gagne `blue`.
- **Tests** : parsing/validation de `commands` (R1–R3), construction de l'environnement (R8), machine d'états d'un onglet `run` (R7, R9, R10) pilotée par des événements terminal simulés.

## Décisions

Voir [decisions.md](decisions.md).
