# Règles de codage

> Ce fichier dit **comment on écrit le code** de Wraith. Les [`specs/`](specs/) disent **quoi construire**.
> En cas de conflit sur le *quoi*, `specs/` fait foi ; sur le *comment*, ce fichier fait foi.
> Toute exception doit être justifiée en commentaire (`// EXCEPTION(<règle>): <raison>`) ou remontée en décision dans la spec du domaine concerné.

Le projet n'a pas encore de code. Ces règles sont écrites **avant** la première ligne, pour que chaque milestone
(M0 → M6) et chaque dépendance à venir (SwiftTerm, PostgresNIO, tree-sitter…) s'y insèrent sans renégociation.

---

## Table des matières

1. [Principes](#1-principes)
2. [Langue](#2-langue)
3. [Langage et toolchain](#3-langage-et-toolchain)
4. [Structure du dépôt et des targets](#4-structure-du-dépôt-et-des-targets)
5. [Règles d'architecture](#5-règles-darchitecture)
6. [Nommage et style](#6-nommage-et-style)
7. [Concurrence](#7-concurrence)
8. [Erreurs, logs et invariants](#8-erreurs-logs-et-invariants)
9. [État et UI](#9-état-et-ui)
10. [Fichiers, chemins et IO](#10-fichiers-chemins-et-io)
11. [Dépendances : règle générale](#11-dépendances--règle-générale)
12. [Dépendances : règles par librairie](#12-dépendances--règles-par-librairie)
13. [Interop C et code `unsafe`](#13-interop-c-et-code-unsafe)
14. [Tests](#14-tests)
15. [Performance](#15-performance)
16. [Sécurité](#16-sécurité)
17. [Git, commits, branches](#17-git-commits-branches)
18. [Documentation et specs](#18-documentation-et-specs)
19. [Checklist de revue](#19-checklist-de-revue)

---

## 1. Principes

- **P1 — Le noyau ignore les domaines.** `WraithApp` ne sait rien de git, Postgres, markdown ou tree-sitter. Si le noyau doit connaître un domaine, c'est que le contrat de plugin est incomplet : on corrige le contrat, pas le noyau.
- **P2 — Une dépendance externe ne traverse jamais un module.** Chaque librairie tierce est enfermée derrière un protocole exprimé dans le vocabulaire de Wraith (port/adaptateur). Voir [§11](#11-dépendances--règle-générale).
- **P3 — Le plus simple qui marche.** Un seul utilisateur, pas de compatibilité ascendante à garantir en v1 (`product`). On n'écrit pas d'abstraction pour un besoin hypothétique — sauf celles imposées par P2, qui protègent d'un remplacement *déjà prévu* (moteur terminal derrière `TerminalSurface`, libgit2 ↔ binaire `git`).
- **P4 — Paresse par défaut.** Aucun travail (connexion PG, scan git, lecture d'arbre) avant la première utilisation effective du panneau ou de l'onglet.
- **P5 — Rien ne casse l'ouverture d'un workspace.** Config invalide, repo manquant, état illisible, disque en lecture seule : dégradation annoncée, jamais de crash ni d'écran vide.
- **P6 — Testable sans UI.** Toute logique non graphique (PanelManager, parsing de config, arbre de splits, cycle de vie PTY, diff, mapping de raccourcis) vit hors des vues et se teste sans lancer l'app.

---

## 2. Langue

| Élément | Langue |
|---|---|
| Identifiants, types, API publiques | anglais |
| Commentaires et doc-comments dans le code | anglais |
| Messages de log, erreurs techniques | anglais |
| Textes affichés à l'utilisateur | anglais (utilisateur unique, cf. `product`) |
| `docs/specs/**`, ce fichier | français |
| Messages de commit, titres de PR | anglais |

Pas de mélange dans un même fichier. Pas d'accents ni de caractères non ASCII dans les identifiants et les noms de fichiers de code.

---

## 3. Langage et toolchain

- **R3.1** — Swift 6, mode langage 6 (`swiftLanguageModes: [.v6]`), **concurrence stricte activée**, sur toutes les targets. Pas de retour à `.v5` pour faire taire un diagnostic.
- **R3.2** — Cible minimale : `macOS 15`, Apple Silicon uniquement. Pas de code conditionnel pour Intel ni pour des versions antérieures.
- **R3.3** — SwiftPM est la source de vérité du build (`Package.swift`). Un éventuel projet Xcode est généré/annexe : aucun réglage de build ne vit **uniquement** dans le `.xcodeproj`.
- **R3.4** — Les avertissements sont des erreurs en CI (`-warnings-as-errors`). Localement on peut builder avec des warnings, on ne pousse pas avec.
- **R3.5** — Aucun code mort commité : pas de fichier « au cas où », pas de fonction jamais appelée, pas de bloc commenté. Le dépôt git est la mémoire.
- **R3.6** — Formatage : `swift-format` avec la configuration `.swift-format` à la racine. Indentation 4 espaces, largeur 120. `swift format lint --strict --recursive Sources Tests` doit passer.
- **R3.7** — Pas de préprocesseur conditionnel (`#if`) hors `#if DEBUG` et `#if canImport(...)` pour un fallback de dépendance explicitement prévu par une spec.
- **R3.8** — `import` : uniquement ce qui est utilisé, triés (modules système, puis Apple, puis tiers, puis modules Wraith). Pas d'`@_exported import`, pas d'`@testable` hors des tests.

---

## 4. Structure du dépôt et des targets

```
wraith/
├── Package.swift
├── .swift-format
├── Sources/
│   ├── WraithApp/          # exécutable : app, fenêtres, layout, hôte terminal, services
│   ├── WraithKit/          # contrat de plugin + types partagés (aucune dépendance tierce)
│   ├── WraithTerminal/     # PTYSession (POSIX) + adaptateur SwiftTerm (seul module qui l'importe)
│   ├── PluginExplorer/
│   ├── PluginEditor/
│   ├── PluginGit/
│   ├── PluginPostgres/
│   ├── PluginRun/
│   └── PluginAgents/
├── cli/
│   └── wraith              # script shell
├── Tests/
│   ├── WraithAppTests/
│   ├── WraithKitTests/
│   └── Plugin<X>Tests/
└── docs/
```

- **R4.1 — Sens des dépendances** (aucune flèche inverse, aucune exception) :

  ```
  PluginX ──▶ WraithKit ◀── WraithApp ──▶ WraithTerminal ──▶ SwiftTerm (SPM)
  ```

  - Un plugin importe **uniquement** `WraithKit` (+ ses propres dépendances tierces).
  - Un plugin n'importe jamais `WraithApp`, ni un autre plugin. C'est vérifié par les dépendances de target dans `Package.swift` : si le compilateur laisse passer, c'est que `Package.swift` est faux.
  - `WraithKit` n'a **aucune** dépendance tierce, ni sur `WraithApp`.
  - Toute communication inter-plugins passe par l'`EventBus` de `PluginContext`.
- **R4.2** — Un fichier = un type principal, nommé comme lui (`PanelManager.swift`). Les extensions vivent dans `<Type>+<Sujet>.swift`.
- **R4.3** — Arborescence interne d'une target, dans cet ordre de dossiers : `Model/`, `Services/`, `Views/`, `Support/`. Un plugin expose son point d'entrée à la racine (`ExplorerPlugin.swift`).
- **R4.4** — `public` uniquement dans `WraithKit` et sur ce qu'un plugin doit voir. Ailleurs : `internal` par défaut, `private`/`fileprivate` dès que possible. `open` est interdit.
- **R4.5** — Ajouter une target implique de mettre à jour ce fichier et le tableau de `docs/specs/README.md` dans le même commit.

---

## 5. Règles d'architecture

- **R5.1 — Pas de singleton dans les plugins.** Aucun `static let shared`. Tout arrive par `PluginContext` (injection). Dans le noyau, un singleton doit être justifié par une ressource système réellement unique (ex. flux FSEvents) et rester `internal`.
- **R5.2 — Les plugins ne pilotent pas le layout.** Un plugin *déclare* ses `PanelDescriptor` / `CenterTabDescriptor` ; `PanelManager` seul décide de ce qui est visible. Aucune API du type `showPanel()` exposée aux plugins.
- **R5.3 — `makeView` est paresseux** et n'a aucun effet de bord : il construit la vue, il n'ouvre pas de connexion, ne lance pas de scan (P4). Le travail démarre sur l'événement d'activation du panneau, s'arrête sur sa désactivation.
- **R5.4 — Cycle de vie symétrique.** Tout ce qu'`activate(context:)` démarre (tâches, abonnements, watchers, connexions) est arrêté par `deactivate()`. Un abonnement `EventBus` est toujours désabonné.
- **R5.5 — Une seule ressource partagée par système.** Un flux FSEvents pour tout le workspace, multiplexé par l'`FSWatchService` avec filtres de chemin et debounce ~300 ms. Un plugin ne crée jamais son propre watcher, ni son propre timer de polling du disque.
- **R5.6 — Le noyau ne connaît pas les schémas de config des plugins.** Chaque plugin lit sa section via `config.section("<id>")` et la décode lui-même (`config` R5).
- **R5.7 — Les identifiants sont des chaînes namespacées** : `"git.status"`, `"explorer.tree"`, `"postgres.query"`. Préfixe = id du plugin. Un id est stable : il apparaît dans `state.json` et dans les surcharges de raccourcis de l'utilisateur ; le changer est une migration, pas un renommage.
- **R5.8 — Frontière = protocole.** Toute capacité offerte aux plugins (`WorkspaceService`, `TerminalService`, `ThemeService`, `EventBus`, `PaletteService`, `HighlightService`) est un `protocol` dans `WraithKit`, implémenté dans `WraithApp`. Un plugin ne dépend jamais d'un type concret du noyau. Corollaire : chaque protocole a un double de test dans `WraithKit` ou les tests du plugin.
- **R5.9 — Types de données inertes.** Ce qui traverse la frontière (descripteurs, événements, config) est une `struct`/`enum` `Sendable`, sans référence, sans closure retenue, sans type tiers ([§11](#11-dépendances--règle-générale)).
- **R5.10 — Capacités partagées = noyau.** Dès que deux plugins ont besoin du même composant, il devient une capacité du noyau : protocole dans `WraithKit` (R5.8), implémentation **et dépendance tierce** dans `WraithApp` (R11.7 reste vrai : `WraithKit` n'a que le protocole). Jamais un plugin qui en sert un autre. Capacités v1 : `PaletteService` (fuzzy + UI de palette : quick open, run) et `HighlightService` (tree-sitter → `HighlightSpan` : editor, diff git, éditeur SQL). Le composant terminal (`TerminalService`) et la barre d'outils (`ToolbarItemDescriptor`) relèvent de la même règle.

---

## 6. Nommage et style

- **R6.1** — `UpperCamelCase` pour les types, `lowerCamelCase` pour le reste. Acronymes traités comme des mots sauf en tête minuscule : `PTYManager`, `urlForFile`, `sqlGrammar`.
- **R6.2** — Pas d'abréviation inventée (`cfg`, `mgr`, `wsp`). Exceptions consacrées du domaine : `cwd`, `pty`, `fs`, `url`, `id`, `sql`, `pg`.
- **R6.3** — Suffixes réservés à un rôle précis : `…Service` (capacité injectée), `…Manager` (machine à états propriétaire de son état), `…Descriptor` (déclaration inerte), `…Store` (persistance), `…View` (SwiftUI), `…Error` (erreur typée).
- **R6.4** — Pas de `get` en préfixe (`func status()` et non `getStatus()`). Les booléens se lisent : `isVisible`, `hasChanges`, `canClose`.
- **R6.5** — `let` par défaut ; `var` seulement là où la mutation existe. Types valeur par défaut ; `class`/`actor` quand l'identité ou l'isolation est requise. Toute `class` non `final` doit être justifiée.
- **R6.6** — Pas de tuple à plus de deux composants dans une signature publique : une `struct` nommée.
- **R6.7** — Un `enum` sans `default` dans les `switch` du noyau : on veut l'erreur de compilation quand un cas s'ajoute. `default` autorisé uniquement sur les `enum` d'un module tiers.
- **R6.8** — Les commentaires expliquent le *pourquoi*. Le *quoi* se lit dans le code. Doc-comments `///` sur tout ce qui est `public` dans `WraithKit`. Pas de commentaire décoratif (`// MARK: -` autorisé, bannières ASCII non).
- **R6.9** — Un `TODO` doit référencer une spec : `// TODO(editor): reload strategy on external change`. Sans référence, il n'est pas commité.
- **R6.10** — Imbrication maximale conseillée : 3 niveaux. Au-delà, `guard` et sortie anticipée.

---

## 7. Concurrence

- **R7.1** — L'UI et tout ce qui la nourrit est `@MainActor`. Les vues, les modèles `@Observable` observés par les vues, `PanelManager`, `ShortcutRegistry` : `@MainActor`.
- **R7.2** — Le travail hors UI (IO disque, git, réseau PG, lecture PTY, parsing) est isolé dans un `actor` ou exécuté sur une tâche non-MainActor. Aucun IO bloquant sur le main actor.
- **R7.3** — `Sendable` partout où un type traverse une frontière d'isolation. `@unchecked Sendable` est interdit, sauf sur un wrapper de type C dont le commentaire explique la garantie de sûreté (voir [§13](#13-interop-c-et-code-unsafe)).
- **R7.4** — Pas de `Task.detached`, sauf priorité/contexte explicitement voulus et justifiés. Préférer `Task { }` fils, ou un `TaskGroup`.
- **R7.5** — Toute tâche longue est **retenue** (stockée) et **annulée** au `deactivate()` / `deinit` de son propriétaire. Une tâche orpheline est un bug.
- **R7.6** — Toute boucle longue vérifie l'annulation (`try Task.checkCancellation()` ou `Task.isCancelled`) : scan de fichiers, lecture PTY, curseur de résultats SQL.
- **R7.7** — Pas de `DispatchSemaphore`, `objc_sync_enter`, `NSLock` pour synchroniser de la logique métier : `actor`. `NSLock` reste toléré dans un adaptateur C bas niveau, confiné au fichier.
- **R7.8** — Pas de `Task { @MainActor in ... }` pour « corriger » une erreur d'isolation : on corrige le découpage. Pas d'attente synchrone d'une tâche asynchrone.
- **R7.9** — Les flux d'événements (`EventBus`, sorties PTY, FSEvents) sont exposés en `AsyncStream`/`AsyncSequence`, jamais en callbacks stockés par le consommateur.
- **R7.10** — Le debounce/throttle est fait dans le producteur (`FSWatchService`, écriture de `state.json`), pas répliqué dans chaque consommateur.

---

## 8. Erreurs, logs et invariants

- **R8.1** — Une erreur par domaine, `enum` `Error` + `LocalizedError` : `ConfigError`, `TerminalError`, `GitError`, `PostgresError`. Pas d'`NSError` fabriqué à la main, pas de `String` jetée.
- **R8.2** — Une erreur venant d'une librairie tierce est **traduite** à la frontière de l'adaptateur ; un type d'erreur tiers ne fuit jamais vers `WraithKit`, `WraithApp` ou l'UI ([§11](#11-dépendances--règle-générale)).
- **R8.3** — `try!`, `as!`, `!` (force unwrap) sont interdits en dehors des tests. Exception unique : un littéral connu à la compilation (`URL(string: "…")!` d'une constante), avec commentaire.
- **R8.4** — `fatalError` est réservé aux invariants de programmation impossibles à atteindre depuis une entrée utilisateur ou le disque. Une donnée externe (config, `state.json`, sortie de `git`, réponse PG) ne provoque jamais de `fatalError` (P5).
- **R8.5** — Pas de `catch {}` silencieux. On traite, on remonte, ou on logge avec le contexte. Un `catch` qui ignore volontairement doit dire pourquoi.
- **R8.6** — Logs via `os.Logger`, un logger par sous-système : `Logger(subsystem: "dev.crafters.wraith", category: "<module>")`. **`print` est interdit** hors du script CLI.
- **R8.7** — Niveaux : `debug` (diagnostic dev), `info` (cycle de vie : workspace ouvert, plugin activé), `error` (échec visible par l'utilisateur), `fault` (invariant rompu). Pas de log dans une boucle chaude (lecture PTY, frame de rendu).
- **R8.8** — Jamais de secret, de contenu de fichier, de requête SQL complète ni de sortie de terminal dans un log. Chemins : loggés en `privacy: .private` par défaut.
- **R8.9** — Une erreur que l'utilisateur doit connaître se voit dans l'UI (bannière du panneau concerné) : un log seul ne suffit pas. Une erreur de config affiche le fichier, la ligne et le message (`config` R7).

---

## 9. État et UI

- **R9.1** — SwiftUI par défaut. `NSViewRepresentable` uniquement quand AppKit est nécessaire (surface terminal, éditeur de texte) et confiné dans un type dédié.
- **R9.2** — État observable via `@Observable` (Observation). Pas d'`ObservableObject`/`@Published` dans le nouveau code.
- **R9.3** — Flux unidirectionnel : la vue lit l'état et envoie des intentions au manager ; elle ne mute pas l'état d'un autre composant.
- **R9.4** — Aucune logique métier dans un `body` : pas d'IO, pas de calcul coûteux, pas de tri d'une grosse collection. Le `body` lit des valeurs déjà prêtes.
- **R9.5** — Toute liste dynamique utilise des identités stables (`Identifiable` avec un id persistant, pas un index ni un `UUID` recréé à chaque rendu).
- **R9.6** — Les vues ne connaissent aucun type tiers ([§11](#11-dépendances--règle-générale)) : elles affichent des types Wraith.
- **R9.7** — Pas de couleur, police ou métrique en dur dans les vues : tout passe par `ThemeService` / des constantes de design du module.
- **R9.8** — Un raccourci clavier est **déclaré** (`ShortcutRegistry`), jamais capté ad hoc dans une vue. Les conflits sont détectés au démarrage et remontés.
- **R9.9** — Chaque état d'une vue de données est traité explicitement : vide, chargement, erreur, contenu. Un spinner infini est un bug.

---

## 10. Fichiers, chemins et IO

- **R10.1** — Les chemins sont des `URL` (`fileURL`), pas des `String`. Conversion en `String` uniquement à la frontière (affichage, C, shell).
- **R10.2** — Aucun chemin en dur (`~/…`, `/usr/local/…`) hors d'une constante nommée d'un service dédié.
- **R10.3** — La racine du workspace est la seule base : un chemin interne est stocké **relatif** à la racine, absolu sinon (`config` R10). La normalisation est faite par `WorkspaceService`, pas dans chaque plugin.
- **R10.4** — Toute écriture de fichier d'état est **atomique** (écriture dans un temporaire du même volume + `replaceItem`). `state.json` n'est jamais écrit partiellement.
- **R10.5** — Toute lecture/écriture disque est asynchrone et hors du main actor (R7.2). Pas de `Data(contentsOf:)` synchrone dans une vue.
- **R10.6** — Tout parcours de disque exclut par défaut : `.git/objects`, `node_modules`, `target`, `.build`, `.wraith/state.json`. La liste est **une seule** constante partagée, pas recopiée par plugin.
- **R10.7** — L'échec d'une écriture (disque plein, lecture seule) est dégradé et signalé une fois, jamais fatal (`config`, cas limites).
- **R10.8** — JSON : `Codable` avec `CodingKeys` explicites dès qu'un nom diffère. Encodage avec clés triées pour des diffs stables. Décodage tolérant à l'ajout de clés inconnues, strict sur les types.
- **R10.9** — Tout format persisté porte un numéro de version de schéma ; un état de version inconnue est ignoré et sauvegardé en `.bak` (`config` R9).

---

## 11. Dépendances : règle générale

- **R11.1 — Adaptateur obligatoire.** Une librairie tierce est importée dans **un seul module**, l'adaptateur. Le reste du code parle à un protocole Wraith. Concrètement : `import PostgresNIO` n'apparaît que dans `PluginPostgres/Services/`, `import SwiftTreeSitter` que dans le service de highlighting, `import SwiftTerm` que dans `WraithTerminal`.
- **R11.2 — Aucun type tiers dans une signature partagée.** Ni dans `WraithKit`, ni dans une vue, ni dans un modèle persisté. Les types tiers sont convertis en types Wraith (`GitFileStatus`, `QueryResult`, `HighlightSpan`) à la frontière.
- **R11.3 — Critères d'ajout.** Avant d'ajouter une dépendance, répondre dans la spec du domaine : (a) que coûte l'écrire soi-même ? (b) est-elle maintenue et compatible Swift 6 ? (c) quelle est la stratégie de sortie si elle disparaît ? Sans réponse, pas de dépendance.
- **R11.4 — Versions figées.** Toute dépendance SPM est épinglée (`.upToNextMinor` au plus large, exact pour une API instable) et `Package.resolved` est commité. Une dépendance vendorisée est épinglée à un commit noté dans le `README.md` du dossier `Vendor/`.
- **R11.5 — Mise à jour = commit dédié**, avec la raison et ce qui a été retesté. Jamais mélangée à un changement fonctionnel.
- **R11.6 — Pas de dépendance transitive utilisée directement** : si on utilise `X` qui vient avec `Y`, et qu'on veut `Y`, on déclare `Y`.
- **R11.7 — Zéro dépendance dans `WraithKit`** (R4.1) : le contrat de plugin ne doit jamais forcer un plugin à lier une librairie.
- **R11.8 — Fallback documenté.** Pour toute dépendance à risque (API instable, vendorisée, native), le protocole d'adaptation doit rendre possible une implémentation de repli, et cette possibilité est vérifiée par au moins un double de test qui implémente le même protocole.
- **R11.9 — Nouvelle librairie non prévue ici :** on applique R11.1 → R11.8, on ajoute une sous-section à [§12](#12-dépendances--règles-par-librairie) et une ligne de décision dans la spec du domaine, dans le commit qui l'introduit.
- **R11.10 — Pas de dépendance pour du confort** (extensions de convenance, sucre syntaxique, réseau générique) : ce qui se remplace par 30 lignes maison ne justifie pas une dépendance.

---

## 12. Dépendances : règles par librairie

Récapitulatif ; le détail de chaque usage vit dans la spec du domaine.

| Librairie | Rôle | Module adaptateur | Type Wraith exposé | Repli prévu |
|---|---|---|---|---|
| SwiftTerm (SPM) | émulation VT + rendu de la surface | `WraithTerminal` | `TerminalSurface`, `TerminalService` | aucun (le protocole permet d'en changer) |
| PTY (POSIX, possédé par Wraith) | process de l'agent / du run | `WraithTerminal` | `PTYSession` | aucun |
| libgit2 / SwiftGit2 **ou** binaire `git` | status, diff, log | `PluginGit/Services` | `GitStatus`, `GitDiff`, `GitCommit` | l'autre des deux |
| PostgresNIO | client SQL | `PluginPostgres/Services` | `QueryResult`, `SchemaTree` | — |
| SwiftTreeSitter (+ Neon, à évaluer) + grammaires | highlighting (capacité du noyau, R5.10) | `WraithApp/Services/Highlight` | `HighlightService`, `HighlightSpan` | affichage brut sans couleur |
| Lib de fuzzy matching (Ifrit / FuzzyMatcher, à évaluer) | scoring de la palette (R5.10) | `WraithApp/Services/Palette` | `PaletteService`, `PaletteItem` | scoring maison (sous-séquence + bonus frontières) |
| swift-markdown | rendu markdown | `PluginEditor/Services` | `MarkdownDocument` | affichage du texte source |
| Keychain (Security.framework) | secrets | `WraithApp/Services` | `SecretStore` | aucun (obligatoire) |
| FSEvents (CoreServices) | surveillance disque | `WraithApp/Services` | `FSWatchService` | aucun |

### 12.1 SwiftTerm — `terminal`

- `import SwiftTerm` n'existe **que** dans `WraithTerminal`. SwiftTerm fait l'émulation VT et le rendu (`TerminalView`) ; il ne lance **aucun** process (`LocalProcessTerminalView` interdit) : il reçoit les octets du `PTYSession` (`feed`) et renvoie la saisie (`send`).
- L'API exposée est un protocole `TerminalSurface` (feed, resize, focus, thème, sélection, événements bell/titre) : le moteur reste remplaçable (P2), mais aucun repli n'est implémenté ni prévu en v1 (`terminal`, décision du 2026-08-26).
- Version épinglée `.upToNextMinor` ; toute montée est un commit dédié (R11.5) qui rejoue le scénario : lancer Claude Code, redimensionner, souris, coller, `ctrl+c`, fin de process.
- Le cycle de vie d'une surface est possédé par un seul type Swift, avec libération déterministe. Pas de surface créée depuis une vue SwiftUI (R5.3).
- Cadence : ce qui vient du PTY est agrégé par blocs/frame avant de toucher la vue ; pas un événement SwiftUI par octet.

### 12.2 PTY — `terminal`

- **Wraith possède le PTY et le process** : `actor PTYSession` dans `WraithTerminal` (`posix_openpt`/`forkpty`, `execve`, `waitpid`, `killpg`), seule API de création de process terminal. Un onglet = un process (`$SHELL -l -c "<commande>"`), pas de shell interactif (`terminal` R1).
- L'état (pid, `running`/`exited(code)`) vient de `waitpid`, jamais d'un parsing de la sortie ; les signaux vont au groupe de process du PTY.
- Fermeture toujours déterministe : à la fermeture d'un onglet, le groupe reçoit `SIGHUP`, le maître du PTY est fermé, `waitpid` est attendu (5 s, puis `SIGKILL`). Pas de descripteur qui fuit, pas de zombie.
- L'environnement est construit explicitement (`TERM`, `cwd`, variables Wraith, `env` du plugin), jamais hérité tel quel sans revue.
- Aucune commande n'est construite par concaténation de chaîne non échappée ([§16](#16-sécurité)) : la commande est le texte de l'utilisateur/du plugin, passée en un seul argument à `-c`.

### 12.3 git — `git`

- Le choix libgit2 vs binaire `git` est ouvert (`git`) : **le code doit rester indifférent**. Un seul protocole `GitService` ; l'implémentation est un détail interne du plugin.
- Si binaire `git` : exécution via `Process` avec arguments en tableau (jamais via un shell), `--porcelain=v2 -z` pour le status, timeout, stdout/stderr capturés séparément, aucun parsing de sortie destinée à l'humain.
- Si libgit2 : les pointeurs restent dans l'adaptateur, chaque objet libéré (§13), pas d'accès concurrent à un même `git_repository`.
- Aucune écriture destructive (reset, discard, checkout forcé) sans confirmation explicite, et jamais implicite au rafraîchissement.
- Le rafraîchissement est déclenché par l'`FSWatchService` (R5.5), avec debounce ; pas de polling.

### 12.4 PostgresNIO — `postgres`

- Connexion **paresseuse** (P4) : rien avant l'ouverture effective du panneau. Fermeture à la désactivation.
- Aucun mot de passe en config ni en mémoire au-delà du besoin : lecture Keychain à la connexion (`config` R3/R11).
- Toute requête est bornée par défaut (limite de lignes, timeout). Pas de rapatriement d'un résultat non borné en mémoire.
- Les identifiants d'objets (table, colonne) sont échappés côté client ; les valeurs passent **toujours** par des paramètres liés, jamais par interpolation de chaîne.
- Les types PG sont convertis en types Wraith (`QueryValue`) à la frontière : ni `PostgresRow` ni `PostgresError` ne remontent dans l'UI.

### 12.5 tree-sitter — noyau (`HighlightService`), consommé par `editor`, `git`, `postgres`

- Les grammaires sont des dépendances épinglées ; la liste des langages v1 est décidée dans `editor`. Ajouter une grammaire = ajouter une ligne de mapping, pas du code.
- Le parsing tourne hors du main actor et est **annulable** (R7.6) : une frappe qui invalide un parsing en cours l'annule.
- Le highlighting est dégradable : si la grammaire manque ou que le parsing échoue, on affiche le texte brut (R11.8), sans erreur bloquante.
- Fichiers trop gros ou binaires : détectés **avant** le parsing, seuil défini dans `editor`.
- L'éditeur ne raisonne jamais en nœuds tree-sitter : il consomme des `HighlightSpan` (offsets + rôle), ce qui garde le rendu indépendant de la librairie.
- `HighlightService` vit dans `WraithApp` (R5.10) : `highlight(text, language) -> [HighlightSpan]` en une passe, et une session incrémentale (`open(text, language)` / `edit` / `spans`) pour l'éditeur. Les grammaires sont chargées à la demande. `Neon` (ChimeHQ) est le candidat pour l'incrémental et le mapping des queries ; on ne réécrit pas ce qu'il fait (R11.10), on l'évalue au découpage de M1.

### 12.6 swift-markdown — `editor`

- Utilisé pour la preview ; le modèle rendu est un type Wraith, pas l'AST de la librairie.
- Aucun contenu distant n'est chargé au rendu (pas d'image ni de script réseau) — voir [§16](#16-sécurité).

### 12.7 Fuzzy matching — noyau (`PaletteService`)

- Une librairie de scoring (candidates : `Ifrit`, `FuzzyMatcher` ; à évaluer au découpage de M1 (`editor`) selon R11.3) enfermée dans `WraithApp/Services/Palette` ; la palette expose `PaletteItem`/`PaletteService` et jamais un type de la lib (R11.2). Repli : scoring maison (sous-séquence + bonus frontières, ~80 lignes).
- Le scoring tourne hors main actor et est annulable à chaque frappe (R7.6).

### 12.8 Frameworks Apple

- `Security` (Keychain) est enfermé derrière `SecretStore` : le reste du code ne connaît pas les `SecKey*`, ce qui rend les tests possibles avec un double en mémoire.
- `CoreServices`/FSEvents est enfermé derrière `FSWatchService` (R5.5), avec un flux unique multiplexé.
- Pas d'API dépréciée, pas de recours à AppKit quand l'équivalent SwiftUI existe et suffit.

---

## 13. Interop C et code `unsafe`

S'applique aux appels POSIX (`PTYSession`) et à toute librairie C future.

- **R13.1** — Tout le C est confiné dans le module adaptateur, et si possible dans un seul fichier par ressource.
- **R13.2** — Un pointeur C ne sort **jamais** de l'adaptateur, ni dans un retour, ni dans une closure, ni dans un log.
- **R13.3** — La propriété mémoire est écrite en commentaire au-dessus de chaque type qui possède une ressource C : qui alloue, qui libère, quand. La libération se fait dans `deinit` ou une méthode `close()` explicite, jamais « quelque part plus tard ».
- **R13.4** — `withUnsafe*` : la portée du pointeur ne dépasse pas le bloc. Aucune capture, aucune tâche asynchrone lancée à l'intérieur qui utiliserait le pointeur.
- **R13.5** — Tout code d'appel C vérifie le code de retour et le traduit en erreur Swift typée (R8.2). Pas de retour ignoré.
- **R13.6** — `@unchecked Sendable` sur un wrapper de handle C est autorisé **si** l'accès est sérialisé par un `actor` ou une file dédiée, et le commentaire dit laquelle.
- **R13.7** — Les callbacks C sont des fonctions sans capture de contexte Swift, avec un `Unmanaged`/`userInfo` explicite et un désenregistrement garanti avant la libération de l'objet.

---

## 14. Tests

- **R14.1** — Framework : **Swift Testing** (`import Testing`, `@Test`, `#expect`). XCTest seulement si Swift Testing ne couvre pas le besoin.
- **R14.2** — Chaque milestone livre ses tests unitaires sur la logique non-UI (P6) : `PanelManager`, parsing/précédence de config, arbre de splits, sérialisation de `state.json`, mapping des raccourcis, cycle de vie PTY, parsing du status git.
- **R14.3** — Pas de test d'UI automatisé en v1 : on teste les modèles et les managers, pas les vues.
- **R14.4** — Les tests sont **hermétiques** : aucun accès réseau, aucun serveur Postgres requis, aucune dépendance à `$HOME` de l'auteur, aucune dépendance à l'ordre d'exécution. Le disque est autorisé dans un répertoire temporaire créé et nettoyé par le test.
- **R14.5** — On utilise des **doubles simples** implémentant les protocoles (`InMemorySecretStore`, `FakeGitService`), pas de framework de mocking.
- **R14.6** — Nommage : `<Type>Tests` dans `Tests/<Target>Tests/`, un test = un comportement, nom en anglais décrivant le comportement attendu (`hidesPanelWhenSameShortcutPressedTwice`).
- **R14.7** — Chaque règle fonctionnelle testable d'une spec (`R1`, `R2`…) est couverte par au moins un test qui la cite en commentaire.
- **R14.8** — Chaque bug corrigé arrive avec le test qui échouait avant.
- **R14.9** — Pas de test désactivé commité (`.disabled` sans référence). Un test instable est corrigé ou supprimé, jamais ignoré silencieusement.

---

## 15. Performance

- **R15.1 — Budgets** : ouverture d'un workspace < 500 ms jusqu'à la première frame ; ouverture d'un panneau < 100 ms ; saisie au terminal sans latence perceptible (jamais de travail synchrone sur la frappe).
- **R15.2 — Rien au démarrage qui puisse attendre** (P4) : pas de scan git, pas de connexion PG, pas d'indexation à l'ouverture.
- **R15.3 — Le disque se lit paresseusement** : arbre de fichiers par niveau à l'expansion, jamais de parcours récursif complet du workspace.
- **R15.4 — Les rafales sont amorties à la source** : FSEvents ~300 ms, `state.json` ~1 s (`config` R8), sortie PTY par lots.
- **R15.5 — Pas de copie inutile de gros tampons** : le contenu d'un fichier, un scrollback ou un résultat SQL n'est pas dupliqué à chaque étape.
- **R15.6 — Mesurer avant d'optimiser** : une optimisation non triviale est justifiée par un chiffre (Instruments ou mesure reproductible) noté dans le commit.
- **R15.7 — Coût nul quand invisible** : un panneau masqué ne consomme ni CPU ni timer ; l'app au repos, workspace ouvert, ne doit pas réveiller le CPU en continu.

---

## 16. Sécurité

- **R16.1** — Aucun secret dans le dépôt, dans `.wraith/`, dans les logs, dans les messages d'erreur. Les secrets vivent uniquement dans le Keychain (`config`).
- **R16.2** — Une clé `password` détectée dans `config.json` est ignorée avec avertissement (`config` R11) : on ne la lit pas « juste au cas où ».
- **R16.3** — Aucune exécution de commande construite par interpolation dans un shell. `Process` avec `arguments: [String]`, exécutable résolu explicitement. Les commandes de la config (`run`) sont envoyées à un terminal de l'utilisateur, ce qui est leur nature — mais jamais recomposées avec des valeurs venant d'un autre fichier ou d'une sortie de programme.
- **R16.4** — Tout chemin venant de la config, d'un état persisté ou d'un événement est normalisé et vérifié comme étant sous la racine du workspace avant écriture. Pas de `..` qui s'échappe.
- **R16.5** — Aucun accès réseau non demandé par l'utilisateur : pas de télémétrie, pas de check de mise à jour, pas de chargement de ressource distante (`product` R10).
- **R16.6** — Les entitlements sont minimaux et justifiés fichier par fichier. On n'active pas une capacité « pour voir ».
- **R16.7** — Le contenu affiché (fichier, markdown, résultat SQL, sortie de terminal) est traité comme non fiable : pas d'exécution, pas d'interprétation de séquences qui déclencherait une action de l'app sans intention explicite de l'utilisateur.

---

## 17. Git, commits, branches

- **R17.1** — Branches : `feat/<domaine>-<sujet>`, `fix/<domaine>-<sujet>`, `docs/<sujet>`, `chore/<sujet>`. `<domaine>` = nom du dossier de spec (`layout`, `terminal`, `git`…).
- **R17.2** — Commits conventionnels : `type(scope): sujet` en anglais, impératif, ≤ 72 caractères. Types : `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `build`. Scope = domaine de spec ou target.
- **R17.3** — Un commit = un changement cohérent qui compile et dont les tests passent. Pas de commit « wip » sur une branche partagée.
- **R17.4** — Le corps du commit dit **pourquoi** ; le diff dit quoi. On y référence la spec concernée (`docs/specs/layout`).
- **R17.5** — Ne jamais commiter : binaires de build, `.DS_Store`, `.build/`, `.wraith/state.json`, sorties d'outil, secrets. Le `.gitignore` est mis à jour dans le commit qui crée le besoin.
- **R17.6** — `Package.resolved` est commité (R11.4).
- **R17.7** — Pas de réécriture d'historique sur une branche partagée. Sur sa propre branche, avant partage, c'est libre.
- **R17.8** — Un changement de comportement s'accompagne, dans le même commit, de la mise à jour de la spec (règle fonctionnelle, décision) et de ce fichier s'il crée une règle.

---

## 18. Documentation et specs

- **R18.1** — Ordre de travail : **étude → décisions → découpage → code**. On n'écrit pas de code pour un domaine dont `00-study.md` n'existe pas.
- **R18.2** — Une question ouverte tranchée quitte le `questions.md` du domaine et devient une ligne datée dans `decisions.md` (date, décision, alternatives rejetées, raison).
- **R18.3** — Les règles fonctionnelles sont numérotées (`R1`, `R2`…) et référencées depuis le code (`// R6: state restored on open`) et depuis les tests (R14.7).
- **R18.4** — `docs/architecture-draft.md` est un brouillon d'origine : il n'est plus la référence. Toute divergence se règle dans `specs/`, et le brouillon disparaîtra quand tous les domaines auront leur étude.
- **R18.5** — `README.md` reste court : pitch, roadmap, pointeurs. Le détail vit dans `docs/`.
- **R18.6** — Ce fichier évolue par ajout de règle numérotée. On ne renumérote pas ; une règle abandonnée est marquée `(abandonnée le <date> : <raison>)` plutôt que supprimée, tant qu'elle est référencée quelque part.

---

## 19. Checklist de revue

Avant de pousser :

- [ ] `swift build` sans warning, `swift test` vert, `swift format lint --strict` propre.
- [ ] Sens des dépendances respecté : aucun plugin n'importe `WraithApp` ni un autre plugin (R4.1).
- [ ] Aucune librairie tierce hors de son module adaptateur ; aucun type tiers dans une signature partagée (R11.1, R11.2).
- [ ] Concurrence : pas d'`@unchecked Sendable` injustifié, pas de tâche non annulée, pas d'IO sur le main actor (§7).
- [ ] Pas de `print`, `try!`, `as!`, force unwrap, `catch {}` vide, `TODO` sans référence de spec (§6, §8).
- [ ] Le nouveau travail est paresseux et s'arrête à la désactivation (P4, R5.4).
- [ ] Erreurs traduites, visibles par l'utilisateur quand elles le concernent (R8.2, R8.9).
- [ ] Aucun secret, aucun chemin en dur, aucun accès réseau ajouté (§16).
- [ ] Tests ajoutés pour la logique non-UI et pour chaque règle fonctionnelle touchée (R14.2, R14.7).
- [ ] Specs mises à jour (décision, question ouverte fermée, progression) dans le même commit (R17.8).
