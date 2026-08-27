# Architecture

> Comment Wraith est assemblé : principes, structure, dépendances retenues, règles d'architecture. Le *quoi* est dans [`specs/`](specs/), le style de code dans [`coding-rules.md`](coding-rules.md). Ce fichier change quand une décision d'architecture change ; chaque changement est daté dans le `decisions.md` du domaine concerné.

## Principes

- **P1 — Le plus simple qui marche.** Un utilisateur, pas de compatibilité ascendante, pas de plugins tiers. On écrit le code du besoin d'aujourd'hui ; on abstrait quand il y a **deux** implémentations réelles, pas avant. Pas de protocole, d'adaptateur ni de double « au cas où ».
- **P2 — Utiliser les librairies.** Si une librairie maintenue fait le travail, on l'utilise directement, telle qu'elle est conçue pour l'être. Réécrire ce qu'une lib fait est une faute, pas une prudence.
- **P3 — Utiliser la plateforme.** AppKit/SwiftUI/Foundation d'abord (`NSToolbar`, `NSSplitView`, `NSOutlineView`, `NSTextView`, `FileManager`, `Process`). On n'en réimplémente pas un parce qu'il ne fait pas *exactement* ce qu'on imagine ; on adapte le besoin.
- **P4 — Paresse par défaut.** Aucun travail (connexion, scan, lecture d'arbre) avant la première utilisation effective d'un panneau ou d'un onglet ; un panneau masqué ne consomme rien.
- **P5 — Rien ne casse l'ouverture d'un workspace.** Config invalide, repo manquant, état illisible : dégradation annoncée dans l'UI, jamais de crash ni d'écran vide.

## Vue d'ensemble

Une fenêtre = un dossier = un workspace. Au centre, des groupes d'onglets dans un arbre de splits ; autour, trois slots de panneaux (gauche, droite, bas), un panneau visible par slot ; au-dessus, une barre d'outils native. Il n'y a pas de shell libre : une surface terminal n'existe que pour héberger un agent ou une commande `run`.

```
│ [Claude] [OpenCode]      TOOLBAR              [▶ Run] │
┌──────────┬──────────────────────────────────┬──────────┐
│  LEFT    │        CENTER (splits →          │  RIGHT   │
│  panel   │        groupes d'onglets)        │  panel   │
│          ├──────────────────────────────────┤          │
│          │           BOTTOM panel           │          │
└──────────┴──────────────────────────────────┴──────────┘
```

| Feature | Surfaces | Raccourci par défaut |
|---|---|---|
| Explorer | panneau gauche : arbre de fichiers | `cmd+shift+e` |
| Editor | onglets centraux : fichier / markdown ; panneau bas : recherche contenu | `cmd+p` quick open, `cmd+shift+f` |
| Agents | boutons de toolbar ; un onglet terminal par agent | `config.shortcuts["agents.<id>"]` |
| Run | bouton ▶ Run + palette ; un onglet terminal par commande | `cmd+r` |
| Git | panneau gauche : changes ; panneau bas : historique ; onglet central : diff | `cmd+shift+g` / `cmd+shift+h` |
| Postgres | panneau droit : schéma ; panneau bas : requête + résultats | `cmd+shift+b` / `cmd+shift+q` |

Table complète des raccourcis et leur état : [`shortcuts.md`](shortcuts.md).

## Structure

Un projet Xcode (app macOS SwiftUI, sans App Sandbox : on lit tout le disque et on lance des process), une target app, une target de tests, un dossier par feature. Pas de framework interne, pas de targets « plugin », pas de chargement dynamique.

```
Wraith.xcodeproj
Wraith/
├── App/          # entrée, fenêtres, menus, ThemeService
├── Workspace/    # config.json, state.json, FSWatch, Keychain
├── Layout/       # splits, groupes d'onglets, PanelManager, ShortcutRegistry, toolbar, écran d'accueil
├── Palette/      # palette fuzzy partagée (quick open, run)
├── Highlight/    # tree-sitter → attributs, partagé (editor, diff, sql)
├── Terminal/     # surface SwiftTerm + process, TerminalService
├── Explorer/  Editor/  Agents/  Run/  Git/  Postgres/
WraithTests/         # même découpage
cli/wraith           # script shell : `open -a Wraith "$(pwd)"`
```

- Sens des dépendances, par convention : `App` → features → dossiers partagés (`Layout`, `Palette`, `Highlight`, `Terminal`, `Workspace`). Une feature peut appeler une autre feature directement (`Git` appelle `Editor.open(path)`) ; on évite les cycles, c'est tout.
- Une feature = un dossier avec un point d'entrée (`GitFeature.swift`) qui enregistre ses panneaux, onglets, éléments de toolbar et raccourcis auprès de `Layout` au démarrage.
- Ajouter une feature : un dossier ici, une ligne dans [`specs/README.md`](specs/README.md).

## Règles d'architecture

- **Les features ne pilotent pas le layout.** Une feature *déclare* (panneau, slot, raccourci, `makeView`) ; `PanelManager` décide de ce qui est visible.
- **`makeView` est paresseux** et sans effet de bord ; le travail démarre à l'activation du panneau et s'arrête à sa désactivation (P4). Ce qu'`activate()` démarre, `deactivate()` l'arrête.
- **Services partagés, créés une fois dans `App` et injectés** : `FSWatchService` (un flux FSEvents, multiplexé, debounce ~300 ms), `ThemeService`, `SecretStore`, `TerminalService`, `Palette`, `Highlight`. Pas de `static let shared`. Pas de polling disque.
- **Pas d'`EventBus`.** Une notification entre features est une closure ou un `AsyncStream` exposé par le propriétaire de l'information (`Git` expose `statusChanges`, `Explorer` s'y abonne).
- **Config par section** : chaque feature décode sa propre section de `.wraith/config.json` ; `Workspace` ne connaît pas les schémas.
- **Identifiants namespacés et stables** (`git.status`, `agent.claude`) : ils apparaissent dans `state.json` et les raccourcis ; les changer est une migration.
- **Types tiers près de leur usage.** Une vue ou un modèle persisté ne manipule pas un `PostgresRow` ou un `Node` tree-sitter ; la feature convertit en son propre type là où l'UI ou la persistance en a besoin — et seulement là.
- **Formats persistés versionnés** ; version inconnue → ignoré + `.bak`. Liste d'exclusion disque unique (`.git/objects`, `node_modules`, `target`, `.build`, `.wraith/state.json`).

## Dépendances retenues

On importe là où on utilise. Versions `.upToNextMinor`, `Package.resolved` commité, mise à jour = commit dédié.

| Besoin | Librairie | Note |
|---|---|---|
| Surface terminal + process | **SwiftTerm** | `LocalProcessTerminalView` : PTY, process, vue, exit code via `processTerminated` |
| Git | binaire `git` via `Process` | formats machine (`--porcelain=v2 -z`, `--format`) ; honore hooks, signing, helpers |
| Postgres | **PostgresNIO** | schéma via `pg_catalog` |
| Highlighting | **SwiftTreeSitter + Neon** (ChimeHQ, branche `main`, décision editor 2026-08-26), 14 grammaires SPM (`tree-sitter-*`) | editor, diff git ; sql en M5 |
| Markdown | **swift-markdown** | preview |
| Fuzzy | **FuzzyMatch** (ordo-one) | Smith-Waterman façon fzf : bonus de frontières, ranges pour le surlignage (décision editor 2026-08-26) |
| Recherche contenu | binaire `rg` (repli `grep`) | `cmd+shift+f` |
| Secrets | Security.framework (Keychain) | mot de passe PG |
| Surveillance disque | **AsyncFileMonitor** (CleanCocoa) sur FSEvents | un `FolderContentMonitor` par workspace, multicast ; `FSWatchService` n'ajoute que le filtrage par chemin et les lots débouncés |

Critère d'ajout : la lib fait le travail, est maintenue, compatible Swift 6 → on l'utilise. « Je peux l'écrire moi-même » n'est un argument que sous 50 lignes triviales.

Écartées : libghostty (build zig, API instable, rien de nécessaire au produit), libgit2/SwiftGit2 (contourne la config git de l'utilisateur).

## Sécurité

- Aucun secret dans le dépôt, `.wraith/`, logs ou erreurs. Keychain uniquement ; une clé `password` dans `config.json` est ignorée avec avertissement.
- Pas de commande construite par interpolation avec des valeurs venant d'un autre fichier ou d'une sortie de programme. `Process` avec `arguments: [String]`. Les commandes `run`/`agents` sont le texte de l'utilisateur, passées telles quelles à `$SHELL -l -c`.
- Tout chemin venant de la config, de l'état ou d'un événement est vérifié sous la racine du workspace avant écriture.
- Aucun accès réseau non demandé : pas de télémétrie, pas de mise à jour, pas de ressource distante dans la preview markdown.
- Le contenu affiché (fichiers, markdown, SQL, sortie terminal) est non fiable : aucune séquence n'y déclenche une action de l'app.

## Performance

- Workspace ouvert < 500 ms jusqu'à la première frame ; panneau < 100 ms ; saisie sans travail synchrone.
- Rien au démarrage qui puisse attendre ; disque lu par niveau ; rafales amorties chez le producteur (FSEvents, `state.json`, sortie process).
- Mesurer avant d'optimiser : une optimisation non triviale cite un chiffre.
