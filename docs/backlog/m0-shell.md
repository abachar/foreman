# M0 — Shell

M0 = **Shell** : une app qui ouvre un dossier dans une fenêtre, avec ses zones, ses panneaux, ses onglets, ses raccourcis, sa barre d'outils, son écran d'accueil, et qui persiste/restaure son état. Aucune feature métier : le seul contenu est l'écran d'accueil et un onglet de démonstration.

Domaines couverts : [`product`](../specs/product/), [`config`](../specs/config/), [`layout`](../specs/layout/).

Colonne **Lib / natif** obligatoire (`AGENTS.md`) : ce qu'on utilise au lieu d'écrire. Colonne **Tests** : ce qui est testé, rien d'autre.

## Tâches

Chaque tâche ne dépend que des précédentes. Une tâche = une PR.

| # | Tâche | Règles | Lib / natif | Tests | Taille | Statut | PR |
|---|---|---|---|---|---|---|---|
| 0.1 | **Squelette** : projet Xcode créé par l'auteur (app macOS SwiftUI, Swift 6, strict concurrency, target 26, sans sandbox, target de tests Swift Testing), `.gitignore` Xcode, `.swift-format`, arborescence `Wraith/<feature>/`, workflow CI `xcodebuild test` + lint | — | Xcode template | aucun | S | 🟢 | — |
| 0.2 | **Fenêtre = dossier** : ouverture d'un dossier (menu *Open…*, argument CLI, `application(_:open:)`), une fenêtre par dossier, activation si déjà ouvert, `$HOME` par défaut ; script `cli/wraith` | product R1, R2, R8 ; cas limite dossier disparu | SwiftUI `WindowGroup(for: URL.self)` + `openWindow`, `NSOpenPanel`, `NSApplicationDelegateAdaptor` ; CLI = `open -a Wraith "$(pwd)"` | résolution du dossier (arg → URL canonique, `$HOME` par défaut) | S | 🟢 | |
| 0.3 | **`Workspace` : config** : lecture `.wraith/config.json` (pas de config globale, décision 2026-08-26), sections par feature (`config.section("x")` → `Decodable`), erreur avec ligne, clé `password` ignorée avec avertissement, `repos` absents ignorés | config R1–R5, R7, R11 | `JSONSerialization` (parse, `NSJSONSerializationErrorIndex` → ligne), `JSONDecoder` par section | sections exposées ; JSON invalide → dernière config valide + erreur ligne/message ; `password` ignoré ; section absente → vide | M | 🟢 | |
| 0.4 | **`Workspace` : `state.json`** : lecture au démarrage, écriture atomique débouncée ~1 s et à la fermeture, version de schéma, `.bak` si illisible, chemins relatifs/absolus, racine en lecture seule signalée une fois | config R8–R10 ; cas limites | `FileManager.replaceItemAt`, `JSONSerialization` (enveloppe versionnée) + `Codable` par section, `Task` + `Task.sleep` pour le debounce | roundtrip ; version inconnue → défaut + `.bak` ; chemin sous/hors racine ; debounce (deux écritures rapprochées = une seule) | M | 🟢 | |
| 0.5 | **`FSWatchService`** : un flux FSEvents par workspace, filtres de chemin, debounce ~300 ms, `AsyncStream<[URL]>` ; `Workspace.configChanges` branché dessus (config rechargée à chaud) | config R6 ; architecture (une ressource partagée) | **AsyncFileMonitor** (`FolderContentMonitor`, décision 2026-08-26) ; `FSWatchService` = filtrage par préfixe + lots | debounce/coalescence sur un répertoire temporaire ; config modifiée → nouvelle valeur sur `configChanges`, invalide → pas d'émission + erreur | M | 🟢 | |
| 0.6 | **Arbre de splits** : `enum LayoutNode` (`split`/`group`), opérations pures `split(group, orientation)`, `close(group)`, `neighbor(of:direction:)`, `moveTab(direction)`, géométrie à parts égales | layout R7–R12 ; cas limite split refusé < 300×150 | — (pure logique, ~150 lignes) | chaque opération sur des arbres de 1 à 5 groupes ; repli du split ; dernier groupe jamais fermé ; voisin par chevauchement | M | 🟢 | |
| 0.7 | **Groupes d'onglets** : `TabGroup` (liste ordonnée, actif), insertion après l'actif, fermeture → voisin gauche/premier, `isDirty` → confirmation en chaîne, groupe actif unique | layout R13–R15, R17 | — (pure logique) | insertion/fermeture/activation ; chaîne de confirmations (annuler arrête tout) | S | 🟢 | |
| 0.8 | **`PanelManager`** : état `[PanelSide: PanelID?]`, toggle/remplacement, `activate`/`deactivate` sur la feature, `makeView` paresseux et conservé, focus (afficher → panneau, masquer/`escape` → groupe actif) | layout R1–R6 ; cas limites id dupliqué, side changé | — (pure logique) | toggle même raccourci ; remplacement même slot ; `makeView` appelé une fois ; `activate`/`deactivate` symétriques | S | 🟢 | |
| 0.9 | **`ShortcutRegistry`** : parsing `"cmd+shift+g"`, portées `global`/`tab(kind)`, table `raccourci → action`, surcharges `config.shortcuts`, conflits → aucune liée + erreur, recalcul sur `configChanges`, priorité surface terminal (tout sauf `cmd+…`) | layout R22–R26 ; config R4 | `NSEvent.addLocalMonitorForEvents(.keyDown)` | parsing (valide/invalide) ; conflit après surcharge ; portée `tab` masque `global` ; surcharge d'un raccourci layout par l'utilisateur ; feature ne peut pas écraser le layout | M | 🟢 | |
| 0.10 | **Rendu des zones** : `NSSplitViewController` (left / center / right) + second pour center / bottom, items repliables, tailles par défaut/min, persistance par slot, rétrécissement puis masquage automatique si fenêtre trop petite, taille min de fenêtre | layout R18–R21 ; cas limite cadre hors écran | `NSSplitViewController`, `NSSplitViewItem` (`canCollapse`, `minimumThickness`), `NSWindow.minSize` | calcul des tailles (fonction pure : espace disponible → tailles/masquage dans l'ordre right, left, bottom) | L | 🟢 | |
| 0.11 | **Rendu du centre** : arbre de splits → vues (`NSSplitView` non redimensionnable ou `HStack`/`VStack` à parts égales), barre d'onglets unique (défilable, actif visible, largeur min), écran d'accueil pour un groupe vide (actions + raccourcis, agents, récents — sections vides en M0), navigation clavier entre groupes | layout R16, R33–R34 ; product R3, R5 | SwiftUI pour la barre d'onglets et l'accueil | aucun (vues) | L | 🟢 | |
| 0.12 | **Barre d'outils** : `NSToolbar` + délégué dans `Layout/`, enregistrement d'éléments par les features (`id`, titre, icône SF Symbol, placement, action ou menu, badge), `cmd+alt+t` persisté ; en M0 : vide (validée avec un élément de démonstration retiré ensuite) | layout R30–R32 | `NSToolbar`, `NSToolbarItem`, `NSMenu` | id dupliqué refusé ; ordre leading/trailing | M | 🟢 | |
| 0.13 | **Persistance du layout** : section `layout` de `state.json` (arbre, groupes, onglets `id`/`kind`/payload opaque, actif, panneaux visibles, tailles, cadre fenêtre, toolbar), restauration dans l'ordre R29, `kind` inconnu ignoré, panneaux activés après la première frame | layout R27–R29 ; product R6 | `Codable` | roundtrip complet ; `kind` inconnu → onglet ignoré + repli du groupe ; ordre de restauration (activation après frame) | M | 🟢 | |
| 0.14 | **Onglet de démonstration** `demo.hello` : un `CenterTabDescriptor` minimal (vue texte, payload = titre) pour exercer onglets, splits, déplacement, persistance de bout en bout ; supprimé au début de M1 | — | — | aucun | S | ⚪ | |

Taille : S < ½ jour d'agent, M ≈ 1 jour, L ≈ 2 jours. Statut : ⚪ à faire · 🟡 en cours · 🟢 fait (avec le numéro de PR).

## Définition de fini (M0)

- `wraith .` ouvre une fenêtre sur le dossier ; la relancer active la fenêtre existante.
- `cmd+d` / `cmd+shift+d` splittent, `cmd+w` ferme, `cmd+alt+←→↑↓` naviguent, `cmd+alt+shift+←→↑↓` déplacent un onglet `demo.hello`.
- Trois panneaux de démonstration (un par slot, retirés ensuite) se togglent, se remplacent, se redimensionnent, et leurs tailles survivent à la réouverture.
- Un `config.json` invalide affiche l'erreur avec la ligne ; un `shortcuts` surchargé s'applique à chaud ; un conflit affiche les deux ids.
- Fermer et rouvrir restaure splits, onglets, panneaux, tailles, cadre.
- `xcodebuild test` couvre toutes les lignes « Tests » ci-dessus ; lint propre ; une seule dépendance SPM ajoutée (AsyncFileMonitor, décision 2026-08-26).

## À trancher pendant M0 (décisions attendues)

- 0.1 : la CI cible Xcode 27 via `setup-xcode` ; non vérifiée tant que les runners GitHub n'ont pas la 27 — à confirmer au premier push, sinon passer le workflow en `continue-on-error` jusqu'à disponibilité.
- 0.11 : rendu du centre en SwiftUI pur ou `NSSplitView` imbriqués — **tranché (2026-08-26) : SwiftUI pur** (`HStack`/`VStack` à parts égales, `Divider`), les splits n'étant pas redimensionnables.
- 0.11 : `cmd+t` reste libre (retiré avec l'onglet shell) — **tranché (2026-08-26) : libre jusqu'à M1.**
