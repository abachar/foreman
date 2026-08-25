# git — Étude

## Objectif

Feature `git` (dossier `Git/`) : vue d'ensemble des changements de tous les repos du workspace, stage/unstage/discard, commit, diff inline, historique linéaire, et les opérations courantes (fetch/pull/push, branches, stash) — le tout en appelant le binaire `git` de l'utilisateur, afin d'honorer sa config (hooks, signing, credential helpers, aliases exclus).

Surfaces : panneau gauche `git.changes` (`cmd+shift+g`), panneau bas `git.history` (`cmd+shift+h`), onglet central `git.diff`.

## User stories

- US1 — `cmd+shift+g` : je vois, par repo, ce qui est modifié, stagé, non suivi, en conflit, avec la branche et son avance/retard sur l'upstream.
- US2 — Je stage deux fichiers, j'écris un message, `cmd+enter` : commit fait avec mes hooks et ma signature GPG/SSH habituels.
- US3 — Je clique un fichier modifié : le diff s'ouvre au centre, en aperçu ; je peux stager/discarder un hunk.
- US4 — `cmd+shift+h` : le log de la branche courante ; un clic montre le diff du commit.
- US5 — Je fetch/pull/push depuis la barre du repo ; si git demande une authentification interactive, l'erreur me le dit clairement avec la commande à lancer.
- US6 — Je change de branche, j'en crée une, je stash/unstash sans ouvrir le terminal.
- US7 — Je fais `git commit` au terminal : le panneau se met à jour seul.

## Règles fonctionnelles

### Repos

- R1 — Repos = `config.repos` (`config` R3) sinon auto-détection (`.git/` jusqu'à profondeur 2, exclusions communes). La racine du workspace elle-même, si c'est un repo, est le repo `"."`. Un `.git` fichier (worktree/submodule) est accepté.
- R2 — Chaque repo est une **section** du panneau changes : en-tête (nom, branche courante ou `HEAD détachée @ abc1234`, `↑n ↓m` vs upstream, boutons fetch/pull/push, menu), corps = liste des changements. Section repliée automatiquement si aucun changement ; l'état replié manuel est persisté.
- R3 — Aucun travail avant l'activation du panneau (paresse, `architecture.md`). À l'activation : `status` de chaque repo en parallèle ; le panneau affiche chaque section dès son résultat. Aucun `fetch` automatique, jamais (aucun accès réseau non demandé, `architecture.md`).
- R4 — Rafraîchissement : via `FSWatchService`, sur les chemins du repo **et** sur `.git/HEAD`, `.git/index`, `.git/refs/`, `.git/MERGE_HEAD` ; un événement → `status` du repo concerné, coalescé (une exécution à la fois par repo, la suivante attend). Le panneau masqué n'écoute rien ; réactivation = `status` complet.
- R5 — La feature expose `Git.statusChanges` (`AsyncStream<(repo, [path: GitFileStatus])>`), émis après chaque `status` (consommé par `explorer` R15, `editor` R18). Le statut inclut les fichiers ignorés à la demande (`--ignored` uniquement pour l'arbre visible ; détail au découpage).

### Changes

- R6 — Deux listes par repo : **Staged** et **Changes** (worktree + non suivis), plus **Conflicts** en tête quand il y en a. Chaque ligne : statut (`M A D R C U ?`), chemin relatif au repo (nom en gras, dossier en gris), boutons au survol : stage/unstage, discard, ouvrir le fichier.
- R7 — Actions par fichier : stage (`git add -- <path>`), unstage (`git restore --staged -- <path>`), discard (`git restore -- <path>` ; non suivi → `git clean -f -- <path>`), ouvrir le fichier (`Editor.open(path)`), ouvrir le diff (R12). Actions par section : stage all / unstage all / discard all.
- R8 — **Discard demande toujours confirmation** (fichier ou tout), avec le nombre de fichiers et la mention « irréversible ». Aucune autre action n'est destructive au sens git (tout reste dans le reflog).
- R9 — Conflits : la ligne propose *Marquer comme résolu* (`git add`) et ouvre le fichier avec ses marqueurs ; pas d'outil de merge en v1. Un état `MERGING`/`REBASING`/`CHERRY-PICKING` est affiché dans l'en-tête avec *Abort* et *Continue* (`git merge --abort`, `rebase --continue`, etc.).

### Commit

- R10 — Zone de message en bas de la section (multi-ligne, première ligne = sujet, compteur 72 caractères), bouton *Commit* et `cmd+enter` (portée : champ de message). Commit = `git commit -F <fichier temporaire>` sur l'index tel quel ; rien à stager → bouton désactivé. Option *Amend* (case à cocher, pré-remplit le message de `HEAD`).
- R11 — Le commit passe par les hooks et la signature de l'utilisateur (binaire `git`, config non contournée : jamais `--no-verify`, jamais `-c commit.gpgsign=false`). Échec de hook : sortie affichée dans la bannière de la section, message conservé.
- R12 — Le message non commité est conservé par repo dans `state.json` (pas versionné : `config`), jusqu'au commit.

### Diff

- R13 — Onglet central `git.diff` (aperçu, `explorer` R12 par analogie ; fixé par double clic) : diff **unifié inline**, en-tête par fichier, hunks numérotés, lignes ajoutées/supprimées colorées, numéros de lignes ancien/nouveau, **highlighting syntaxique** via le dossier partagé `Highlight/` (grammaire déduite de l'extension, dégradable en couleurs +/− seules). Lecture seule.
- R14 — Sources : fichier du worktree vs index (`git diff -- <path>`), index vs HEAD (`git diff --cached`), commit entier (`git show <sha>`), fichier d'un commit. Titre : `path (working tree)`, `path (staged)`, `abc1234 sujet`.
- R15 — Par hunk : *Stage hunk* / *Unstage hunk* / *Discard hunk* (patch appliqué via `git apply --cached` / `--reverse` sur un patch temporaire ; discard confirmé, R8). Pas d'édition ligne à ligne.
- R16 — Fichier binaire : « binaire, N Ko → M Ko ». Diff > 5 000 lignes : replié par fichier, dépliage à la demande. Renommages détectés (`-M`).
- R17 — Le diff d'un fichier du worktree se rafraîchit avec R4 (fichier ré-édité) ; le diff d'un commit est immuable.

### Historique

- R18 — Panneau bas `git.history` : sélecteur de repo (celui de la section active du panneau changes par défaut), **log linéaire** de la branche courante (`git log --first-parent`), pagination par 200 commits (« charger plus »), colonnes : sha court, sujet, auteur, date relative, badges refs (branches, tags, `HEAD`). Filtre texte sur sujet/auteur (`--grep`/`--author`).
- R19 — Clic : diff du commit (R14) en aperçu. Menu : copier le sha, *Checkout* (HEAD détachée, confirmé), *Créer une branche ici*, *Cherry-pick* (confirmé), *Revert* (confirmé, crée un commit), *Reset soft/mixed* (confirmé ; `--hard` **absent** de l'UI, terminal uniquement).
- R20 — Historique d'un fichier : depuis le menu d'un fichier (explorer ou changes) → même panneau filtré (`git log --follow -- <path>`).

### Remote, branches, stash

- R21 — Fetch/pull/push (en-tête de section) : `git fetch --prune`, `git pull` (respecte `pull.rebase` de l'utilisateur), `git push` (`-u origin <branche>` si pas d'upstream, après confirmation nommant le remote). Indicateur d'activité dans l'en-tête ; sortie d'erreur dans la bannière. **Une seule opération distante à la fois par repo.**
- R22 — Toute commande est lancée avec `GIT_TERMINAL_PROMPT=0` et sans `SSH_ASKPASS` : si git a besoin d'une interaction (passphrase, credential helper interactif, 2FA), l'échec est détecté et affiché en bannière « authentification requise » avec la commande exacte (`git push`, cwd du repo) et un bouton *Copier la commande* — à lancer via l'agent ou hors Wraith. Pas de surface terminal ouverte par `git` (`product` R4). Aucun secret n'est jamais saisi dans Wraith. Remède durable : un credential helper / agent SSH non interactif.
- R23 — Branches (menu de l'en-tête ou clic sur la branche) : liste locales + distantes avec recherche ; *Checkout* (refusé avec explication si le worktree a des changements en conflit avec la cible — git décide, Wraith affiche), *Nouvelle branche depuis HEAD*, *Renommer*, *Supprimer* (locale uniquement, `-d` ; `-D` demande confirmation avec le nom), *Définir l'upstream*. Pas de suppression de branche distante en v1.
- R24 — Stash : *Stash* (message optionnel, inclut les non suivis via `-u` sur option), liste des stashes de la section (repliée), *Apply* / *Pop* / *Drop* (drop confirmé). Conflit à l'apply : R9 s'applique.
- R25 — Tags : affichés dans le log ; création/suppression hors périmètre (terminal).

### Exécution des commandes git

- R26 — Un seul type `GitCLI` (pas de protocole : une seule implémentation) : `Process` avec `arguments: [String]`, exécutable résolu une fois (`/usr/bin/env git` → chemin réel, ou `git.path` de la config globale), `cwd` = racine du repo, env minimal + `LC_ALL=C`, `GIT_OPTIONAL_LOCKS=0` pour les lectures, stdout/stderr séparés, **timeout** (30 s lecture, 10 min opérations distantes), annulation = `SIGTERM` puis `SIGKILL`.
- R27 — Formats machine uniquement : `status --porcelain=v2 -z --branch`, `log --format=<champs séparés par \x1f> -z`, `diff` avec `--no-color --no-ext-diff -M`, `for-each-ref --format`, `stash list --format`. Jamais de parsing d'une sortie destinée à l'humain ; aucune sortie utilisateur n'est réinjectée dans une commande sauf comme argument après `--`.
- R28 — Erreurs traduites en `GitError` (`notARepo`, `commandFailed(stderr)`, `needsInteraction`, `timeout`, `conflict`, `gitNotFound`) ; `git` introuvable → la feature affiche une bannière unique et reste inerte (rien ne casse l'ouverture, `architecture.md`).
- R29 — La feature **n'écrit jamais** dans `.git/` autrement que par le binaire, et ne modifie jamais la config git de l'utilisateur.

## Cas limites

- Repo déclaré mais absent : ignoré avec avertissement (`config`). Repo sans commit (`HEAD` non né) : section « aucun commit », commit possible.
- Submodules : listés comme repos seulement s'ils sont dans `config.repos` ; sinon apparaissent comme entrée modifiée du parent.
- Repo énorme (status > 30 s) : timeout, bannière proposant de retirer le repo de `config.repos`.
- `git` moderne requis (≥ 2.35 pour `--porcelain=v2` stable et `restore`) : version vérifiée au premier appel, bannière sinon.
- Deux fenêtres sur des workspaces partageant un repo : chacune a sa propre instance de la feature ; l'index lock de git arbitre, l'erreur `index.lock` est retentée une fois après 500 ms.
- Hook lent (tests en pre-commit) : indicateur d'activité, annulable (tue le hook).
- Fichiers avec `\n` ou non-UTF-8 dans le nom : `-z` partout, chemins traités en octets → `URL`.

## Hors périmètre v1

- Outil de merge trois voies, résolution assistée des conflits.
- Graphe des branches, log multi-branches, blame, bisect, rebase interactif.
- Diff côte à côte (éventuel toggle v2).
- Gestion des remotes, tags, branches distantes (suppression), LFS, submodules (init/update).
- `reset --hard`, `push --force` : terminal uniquement, délibérément.
- GitHub/GitLab (PR, issues).

## Options techniques

- **Exécution** : `GitCLI` (type concret, `actor`) dans `Git/`, un par repo, sérialisant les commandes d'écriture, lectures concurrentes autorisées. Parsing dans des fonctions pures (`StatusParser`, `LogParser`, `DiffParser`) → `GitStatus`, `GitCommit`, `GitDiff`, types propres à la feature ; seul `GitFileStatus` sort de `Git/` (R5).
- **Diff** : `git diff` est déjà structuré par hunks (`@@ … @@`) ; un parseur de diff unifié minimal (~150 lignes) suffit pour produire `GitDiff { files: [FileDiff { hunks: [Hunk { lines }] }] }` — on garde le plus simple, pas de librairie. Highlighting : `Highlight.highlight(text, language)` (dossier partagé) appliqué par fichier sur le texte « nouveau » et « ancien » des hunks ; `Git/` n'importe pas tree-sitter.
- **Tests** : parseurs (status v2, log, diff, for-each-ref) sur fixtures réelles ; construction d'arguments (jamais de shell, `--` avant les chemins) ; détection `needsInteraction` sur stderr. La logique du panneau (R6–R9) est testée sur des `GitStatus` construits à la main, sans double de `GitCLI`.

## Décisions

Voir [decisions.md](decisions.md).
