# Conventions de code

> Comment on écrit le code de Wraith, quel que soit l'agent ou l'humain qui l'écrit. Le *quoi* est dans [`specs/`](specs/), le *avec quoi* et le *comment c'est assemblé* dans [`architecture.md`](architecture.md).

## Langue

| Élément | Langue |
|---|---|
| Identifiants, commentaires, logs, textes UI, commits, PR | anglais |
| `docs/**` | français |

Pas d'accents ni de caractères non ASCII dans les identifiants et noms de fichiers de code.

## Toolchain

- Swift 6, mode langage 6, concurrence stricte. Apple Silicon. Deployment target = **la dernière version stable de macOS** (26 à la création du projet) ; on monte quand la machine de l'auteur monte, jamais de code conditionnel pour une version antérieure.
- Le projet Xcode (`Wraith.xcodeproj`, format 110, créé avec Xcode 27 beta) est la source de vérité du build ; SwiftPM ne sert qu'aux dépendances. Réglages figés dans le projet : Swift 6, strict concurrency `complete`, warnings as errors, approachable concurrency + isolation `MainActor` par défaut, App Sandbox désactivé.
- Avertissements = erreurs. `swift format lint --strict --recursive Wraith WraithTests` doit passer (`.swift-format` à la racine : 4 espaces, largeur 120).

## Fichiers

- Un fichier = un type principal, nommé comme lui. Extensions dans `<Type>+<Sujet>.swift`.
- Ordre dans un fichier : `import`, type principal, extensions, types privés d'appoint.
- `import` : uniquement ce qui est utilisé ; triés système → Apple → tiers → Wraith. Pas d'`@_exported import`, pas d'`@testable` hors tests.
- Pas de code mort : pas de fichier « au cas où », pas de bloc commenté, pas de `#if` hors `#if DEBUG`.

## Nommage

- `UpperCamelCase` types, `lowerCamelCase` le reste. Acronymes traités comme des mots : `urlForFile`, `sqlGrammar`, `PtyHandle`.
- Pas d'abréviation inventée (`cfg`, `mgr`). Consacrées : `cwd`, `pty`, `fs`, `url`, `id`, `sql`, `pg`.
- Suffixes réservés : `…Service` (capacité injectée), `…Manager` (propriétaire d'une machine à états), `…Store` (persistance), `…View` (SwiftUI), `…Error` (erreur typée).
- Pas de `get` en préfixe. Booléens lisibles : `isVisible`, `hasChanges`, `canClose`.
- Un test = un comportement, nommé par le comportement : `hidesPanelWhenSameShortcutPressedTwice`.

## Déclarations

- `let` par défaut. Types valeur par défaut ; `class`/`actor` quand l'identité ou l'isolation est requise. `class` est `final` sauf justification.
- `internal` par défaut, `private` dès que possible. `public`/`open` : inutiles (une seule target).
- Pas de tuple à plus de deux composants dans une signature : une `struct` nommée.
- `switch` sur un `enum` Wraith : pas de `default`. `default` autorisé sur un `enum` tiers.
- `guard` et sortie anticipée ; pas plus de 3 niveaux d'imbrication.

## Commentaires

- Ils expliquent le *pourquoi* ; le *quoi* se lit dans le code.
- `///` sur les types et fonctions non triviaux. `// MARK: -` autorisé, bannières ASCII non.
- `// TODO(<domaine>): …` doit citer une spec ; sans référence, il n'est pas commité.
- Une règle fonctionnelle implémentée est citée : `// layout R10: last group never closes`.

## Erreurs et logs

- Une `enum … : Error` par feature, qui peut envelopper l'erreur tierce (`case underlying(Error)`). Pas de `String` jetée, pas d'`NSError` fabriqué.
- `try!`, `as!`, force unwrap : interdits hors tests et littéraux constants commentés. `fatalError` : invariants de programmation uniquement, jamais sur une donnée externe.
- Pas de `catch {}` silencieux : traiter, remonter, ou logger avec contexte.
- `os.Logger`, un par feature, `subsystem: "dev.crafters.wraith"`. `print` interdit hors du script CLI. Pas de log dans une boucle chaude.
- Jamais de secret, contenu de fichier, SQL complet ou sortie de terminal dans un log. Chemins en `privacy: .private`.

## Concurrence

- Vues, modèles observés, managers de layout : `@MainActor`. IO disque, git, réseau, parsing : `actor` ou tâche hors main actor. Aucun IO bloquant sur le main actor.
- `Sendable` aux frontières d'isolation. `@unchecked Sendable` : uniquement sur un wrapper de handle C, avec le commentaire qui dit ce qui sérialise l'accès.
- Toute tâche longue est retenue et annulée par son propriétaire ; les boucles longues vérifient l'annulation.
- Pas de `DispatchSemaphore`/`NSLock` pour de la logique métier. Pas de `Task { @MainActor in }` pour masquer une erreur d'isolation. Pas d'attente synchrone d'async. Pas de `Task.detached` sans justification.
- Les flux sont des `AsyncStream`, pas des callbacks stockés par le consommateur. Le debounce se fait chez le producteur.

## UI

- SwiftUI par défaut ; AppKit via `NSViewRepresentable` quand le composant natif est meilleur (toolbar, split view, outline view, text view, terminal).
- État via `@Observable`. Flux unidirectionnel : la vue lit l'état et envoie des intentions au manager ; elle ne mute pas l'état d'un autre composant.
- Pas de logique métier, d'IO ni de tri coûteux dans un `body`.
- Identités stables dans les listes (`Identifiable` persistant, pas un index ni un `UUID` recréé).
- Couleurs, polices, métriques : via `ThemeService`, jamais en dur.
- Un raccourci est déclaré au `ShortcutRegistry`, jamais capté ad hoc dans une vue.
- Chaque vue de données traite vide / chargement / erreur / contenu.

## Fichiers et chemins

- Chemins en `URL` ; `String` uniquement à la frontière (affichage, arguments de `Process`).
- Chemins internes relatifs à la racine du workspace, absolus sinon.
- Écriture d'état atomique (temporaire + `replaceItem`), hors main actor.
- JSON : `Codable`, `CodingKeys` explicites si le nom diffère, clés triées, tolérant aux clés inconnues, strict sur les types.

## Tests

- Swift Testing (`@Test`, `#expect`).
- On teste ce qui peut casser : parsers, machines à états, précédence de config, arbre de splits, sérialisation. Pas les vues, pas les libs.
- Hermétiques : pas de réseau, pas de serveur, pas de `$HOME`, disque uniquement dans un temporaire créé et nettoyé par le test.
- Un double n'existe que s'il rend un test possible ; on n'introduit pas un protocole en prod *pour* un test si une closure ou une valeur injectée suffit.
- Un bug corrigé arrive avec son test. Pas de test désactivé commité.

## Git

- Branches `feat/<domaine>-<sujet>`, `fix/…`, `docs/…`, `chore/…` ; `<domaine>` = dossier de spec.
- Commits conventionnels `type(scope): sujet`, impératif, ≤ 72 caractères ; le corps dit *pourquoi* et cite la spec.
- Un commit compile et passe les tests. Pas de « wip » ni de réécriture d'historique sur une branche partagée.
- Jamais commité : `xcuserdata/`, `DerivedData/`, `.build/`, `.DS_Store`, `.wraith/state.json`, secrets. `Package.resolved` (dans le `.xcodeproj`) est commité.
- Un changement de comportement met à jour la spec (règle, décision) dans le même commit.

## Checklist avant de pousser

- [ ] Build sans warning, tests verts, lint propre.
- [ ] Pas de `print`, `try!`, force unwrap, `catch {}` vide, `TODO` sans spec.
- [ ] Pas d'IO sur le main actor, pas de tâche orpheline, pas d'`@unchecked Sendable` injustifié.
- [ ] Pas de protocole, adaptateur ou double sans seconde implémentation réelle ([`architecture.md`](architecture.md)).
- [ ] Tests pour ce qui peut casser ; specs à jour dans le même commit.
