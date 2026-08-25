# layout — Étude

## Objectif

Définir la structure d'une fenêtre-workspace : la barre d'outils, les zones, l'arbre de splits de la zone centrale, les groupes d'onglets, la machine à états des panneaux (`PanelManager`) et le registre de raccourcis (`ShortcutRegistry`). Ce domaine ne connaît aucun type d'onglet ni de panneau concret : il héberge ce que les features déclarent en s'enregistrant auprès de `Layout` au démarrage (`architecture`).

## Géométrie

```
│ [Claude] [OpenCode]      TOOLBAR              [▶ Run] │
┌──────────┬──────────────────────────────────┬──────────┐
│          │ ┌────────────────┬─────────────┐ │          │
│  LEFT    │ │ [t1] [t2]      │ [file.md]   │ │  RIGHT   │
│  panel   │ │  groupe A      │  groupe B   │ │  panel   │
│          │ ├────────────────┴─────────────┤ │          │
│          │ │ [t3]        groupe C         │ │          │
│          │ └──────────────────────────────┘ │          │
│          ├──────────────────────────────────┤          │
│          │           BOTTOM panel           │          │
└──────────┴──────────────────────────────────┴──────────┘
```

- La zone centrale (CENTER) est l'arbre de splits entier ; les trois slots de panneaux l'encadrent globalement, jamais par split.
- LEFT et RIGHT occupent toute la hauteur ; BOTTOM occupe la largeur de CENTER uniquement.
- La barre d'outils (TOOLBAR) est la barre native de la fenêtre, au-dessus des quatre zones ; elle ne fait pas partie du layout des zones.

## User stories

- US1 — J'appuie sur le raccourci d'un panneau : il apparaît dans son slot ; j'appuie à nouveau : il disparaît. Le contenu central ne bouge pas de place ni d'état.
- US2 — Deux features déclarent un panneau à gauche ; appeler le second remplace le premier sans le détruire (son état est conservé).
- US3 — Je splitte le groupe actif (vertical ou horizontal) : un nouveau groupe vide apparaît avec l'écran d'accueil, et reçoit le focus ; j'y ouvre un fichier ou un agent.
- US4 — Je navigue entre groupes et onglets entièrement au clavier.
- US5 — Je redimensionne les panneaux à la souris et retrouve leurs tailles à la réouverture.
- US6 — Une feature déclare un raccourci déjà pris : je le sais au démarrage, et je peux le surcharger dans `config.json`.

## Règles fonctionnelles

### Zones et panneaux

- R1 — Une fenêtre a exactement quatre zones : `center` (toujours visible) et trois slots optionnels `left`, `right`, `bottom`, surmontées d'une barre d'outils (R30–R32).
- R2 — Un slot affiche au plus un panneau à la fois. L'état de `PanelManager` est `[PanelSide: PanelID?]` (trois optionnels).
- R3 — Toggle : le raccourci du panneau visible dans son slot le masque ; le raccourci d'un autre panneau du même slot le remplace ; le raccourci d'un panneau masqué l'affiche. Un même raccourci ne pilote jamais deux slots.
- R4 — Les panneaux masqués conservent leur état d'UI (arbre déplié, sélection, scroll) mais ne consomment rien (`architecture` : paresse) : la feature reçoit `deactivate()` et arrête son travail ; `activate()` le relance.
- R5 — Un panneau n'est construit (`makeView`) qu'à sa première activation ; sa vue est ensuite conservée en mémoire tant que la fenêtre vit.
- R6 — Le focus clavier : afficher un panneau lui donne le focus ; le masquer rend le focus au groupe d'onglets actif. `escape` depuis un panneau rend le focus au centre sans masquer le panneau.

### Zone centrale : splits et groupes

- R7 — La zone centrale est un arbre binaire : nœud = `split(orientation, first, second)`, feuille = `group(id)`. L'arbre a toujours au moins une feuille.
- R8 — Un split partage l'espace **à parts égales** entre ses deux enfants. Les splits ne sont pas redimensionnables en v1.
- R9 — Splitter le groupe actif crée un frère : `vertical` place le nouveau groupe à droite, `horizontal` en dessous. Le nouveau groupe est **vide** (écran d'accueil, R33) et devient actif.
- R10 — Fermer le dernier onglet d'un groupe ferme le groupe ; le split parent se replie (le frère prend toute la place). Le dernier groupe de l'arbre ne se ferme jamais : fermer son dernier onglet le laisse vide, sur l'écran d'accueil (R33).
- R11 — Navigation entre groupes par direction (`←→↑↓`) : la cible est le groupe voisin dont le rectangle chevauche le plus le groupe actif dans cette direction. Pas de voisin → aucun effet.
- R12 — Déplacer l'onglet actif vers le groupe voisin dans une direction : l'onglet quitte son groupe (R10 s'applique si le groupe se vide) et devient l'onglet actif du groupe cible. Pas de voisin → aucun effet. Pas de drag & drop en v1.

### Groupes d'onglets

- R13 — Un groupe est une liste ordonnée d'onglets + un onglet actif. Chaque onglet a un `id` stable (UUID généré à la création, persisté), un `kind` (id namespacé déclaré par une feature : `editor.file`, `agent.claude`, `run.backend:test`, `git.diff`…), un titre et un état « modifié » (`isDirty`) fournis par son propriétaire.
- R14 — Un nouvel onglet s'insère juste après l'onglet actif et devient actif. Fermer l'onglet actif active son voisin de gauche, ou le premier onglet s'il n'y en a pas.
- R15 — Fermer un onglet `isDirty` demande confirmation (la formulation appartient à la feature propriétaire, le mécanisme au layout). Fermer un groupe ou une fenêtre enchaîne les confirmations une par une.
- R16 — La barre d'onglets est un composant unique (R3 de `product`) : onglets défilables horizontalement si trop nombreux, onglet actif toujours visible, aucun onglet tronqué en dessous d'une largeur minimale.
- R17 — Il existe exactement un **groupe actif** par fenêtre ; cliquer dans un groupe, y naviguer au clavier ou y ouvrir un onglet le rend actif. Toutes les commandes d'onglet (nouveau, fermer, `cmd+1..9`) s'appliquent au groupe actif.

### Redimensionnement et tailles

- R18 — Seuls les panneaux se redimensionnent, à la souris, par leur bord intérieur. Largeur des panneaux latéraux et hauteur du panneau bas sont persistées **par slot** (pas par panneau) dans `state.json`.
- R19 — Tailles par défaut : `left` 260 pt, `right` 320 pt, `bottom` 240 pt. Minimum d'un panneau : 160 pt. La zone centrale garde toujours au moins 400 × 200 pt.
- R20 — Taille minimale de la fenêtre : 800 × 500 pt. Si l'espace manque malgré tout (fenêtre réduite avec trois panneaux ouverts), les panneaux sont **rétrécis jusqu'à leur minimum** dans l'ordre `right`, `left`, `bottom`, puis masqués dans le même ordre ; ils réapparaissent d'eux-mêmes quand la place revient. Leur taille persistée n'est pas modifiée par cet ajustement.
- R21 — Les onglets d'un groupe reçoivent la taille du groupe ; un contenu qui a besoin de connaître sa taille (surface terminal) la reçoit par un callback de redimensionnement, débouncé par le producteur.

### Raccourcis

- R22 — Un raccourci est déclaré, jamais capté ad hoc (`coding-rules`). Le `ShortcutRegistry` est la seule table `raccourci → action`, alimentée par : les actions du layout (ci-dessous), les panneaux et actions des features, puis les surcharges (`config` R4).
- R22b — Chaque action a une **portée** : `global` (défaut), ou `tab(kind)` (active uniquement quand un onglet de ce kind a le focus dans le groupe actif). Deux actions de portées disjointes peuvent partager un raccourci ; une action `tab(kind)` masque une action `global` de même raccourci quand elle est active. Les actions du layout sont globales.
- R23 — Raccourcis par défaut du layout (notation `config`) :

  | Action | Raccourci |
  |---|---|
  | Fermer l'onglet actif | `cmd+w` |
  | Aller à l'onglet N du groupe actif | `cmd+1` … `cmd+9` (`cmd+9` = dernier) |
  | Onglet précédent / suivant | `cmd+shift+[` / `cmd+shift+]` |
  | Split vertical / horizontal | `cmd+d` / `cmd+shift+d` |
  | Focus groupe voisin | `cmd+alt+←` `→` `↑` `↓` |
  | Déplacer l'onglet vers le groupe voisin | `cmd+alt+shift+←` `→` `↑` `↓` |
  | Rendre le focus au centre | `escape` (depuis un panneau uniquement) |
  | Nouvelle fenêtre (ouvrir un dossier) | `cmd+shift+n` |
  | Masquer / afficher la barre d'outils | `cmd+alt+t` |

- R24 — Conflits : deux actions sur le même raccourci **après** application des surcharges → aucune des deux n'est liée, une erreur est affichée au démarrage avec les deux ids. Une feature ne peut pas redéfinir un raccourci du layout ; seul l'utilisateur le peut via `config.json`.
- R25 — Priorité de capture : le registre reçoit l'événement clavier avant le contenu de l'onglet, **sauf** pour une surface terminal (agent, run) qui a le focus : elle reçoit tout ce qui n'est pas un raccourci `cmd+…` (les combinaisons `ctrl`/`alt` seules lui appartiennent). Un raccourci sans `cmd` ne peut donc être déclaré que pour un contexte hors terminal (`escape` en est le seul cas en v1).
- R26 — Les raccourcis sont surchargeables à chaud (`config` R6) : un événement de `Workspace.configChanges` recalcule la table entière et réapplique R24.

### Persistance (`state.json`, cf. `config`)

- R27 — Le layout est propriétaire de la section `layout` de `state.json` : arbre de splits, groupes (onglets ordonnés avec `id`, `kind`, payload opaque de la feature, onglet actif), groupe actif, panneau visible par slot, taille par slot, cadre de la fenêtre.
- R28 — Le payload d'un onglet est une chaîne JSON opaque fournie par la feature propriétaire (`serialize`) et rendue telle quelle à la restauration (`restore`). Un `kind` inconnu à la restauration ou un `restore` qui échoue → l'onglet est ignoré (R10 s'applique). Le layout ne lit jamais le payload.
- R29 — À la restauration, l'ordre est : reconstruire l'arbre et les groupes, restaurer les onglets, appliquer les panneaux visibles, puis donner le focus au groupe actif. Les panneaux restaurés visibles sont activés (R4) après la première frame, pas avant (`architecture` : rien au démarrage qui puisse attendre).

### Barre d'outils

- R30 — La fenêtre a une barre d'outils native (`NSToolbar`). Elle ne contient que des éléments déclarés par les features (`id`, titre, icône, placement, genre) : placement `leading` (agents) ou `trailing` (run) ; genre *action* (clic → callback) ou *menu* (clic → liste d'entrées fournies à la demande, avec sous-titres et badges). Ordre : ordre d'enregistrement des features, `leading` à gauche, `trailing` à droite. Le layout ne déclare aucun élément propre en v1.
- R31 — Un élément peut porter un **badge** (`none` / `dot(color)`) mis à jour par la feature propriétaire (agent en cours, run échoué). Un élément dont l'`id` est déjà pris est refusé et loggé en `fault`. Le clic droit (ou clic long) sur un élément *action* ouvre son menu secondaire s'il en déclare un.
- R32 — `cmd+alt+t` masque/affiche la barre d'outils (persisté dans `state.json`). Les actions des éléments restent accessibles par leurs raccourcis et par la palette.

### Écran d'accueil

- R33 — Un groupe **sans onglet** affiche l'écran d'accueil, dans l'esprit de la zone vide d'IntelliJ : au centre, la liste des actions principales avec leur raccourci (ouvrir un fichier `cmd+p`, lancer une commande `cmd+r`, panneaux `cmd+shift+e/g/h/d/q`, split `cmd+d`), au-dessus les agents disponibles (boutons, `agents` R2) et en dessous les fichiers récents du workspace (`editor` R19). Les entrées sont fournies par les features via le `ShortcutRegistry` et un enregistrement d'entrée d'accueil (`id`, titre, icône, section, action ; mêmes règles que R30) ; le layout n'en connaît aucune en dur.
- R34 — L'écran d'accueil n'est pas un onglet : il n'apparaît pas dans la barre, ne se ferme pas, ne se persiste pas. Ouvrir un onglet dans le groupe le remplace ; fermer le dernier onglet le ramène (R10). Il reçoit le focus clavier du groupe (les raccourcis globaux fonctionnent, `escape` sans effet).

## Cas limites

- Cadre de fenêtre persisté hors des écrans actuels : la fenêtre est recentrée sur l'écran principal avec sa taille persistée (bornée à l'écran).
- Deux features déclarent le même `PanelID` : le second est refusé et loggé en `fault` (invariant de programmation, les features sont compilées ensemble).
- Un panneau change de slot entre deux versions (la feature a modifié son `side`) : l'état `[side: id]` ne le trouve plus dans l'ancien slot → considéré masqué.
- `cmd+N` avec N > nombre d'onglets : aucun effet (sauf `cmd+9` = dernier).
- Split quand la zone centrale ne peut plus garantir 400 × 200 pt par groupe après division : le split est refusé (bip système), rien ne change.
- Fermeture de fenêtre pendant une confirmation R15 : annuler la confirmation annule la fermeture.

## Hors périmètre v1

- Redimensionnement des splits (parts égales fixes).
- Zoom / maximisation temporaire d'un groupe.
- Drag & drop d'onglets (entre groupes ou pour réordonner) ; réordonner au clavier.
- Onglets épinglés, aperçu au survol, fermeture par le bouton du milieu.
- Plusieurs panneaux visibles dans un même slot (empilés ou en onglets).
- Panneaux flottants ou détachés (`product`).
- Splits à plus de deux enfants (l'arbre binaire couvre tous les agencements).

## Options techniques

- **Arbre de splits** : `enum LayoutNode: Codable` indirect (`split`/`group`) dans `Layout/`, manipulé par `LayoutManager` (`@MainActor @Observable`). Les opérations (split, close, neighbor, move) sont des fonctions pures sur l'arbre + la géométrie calculée, testées sans UI (c'est une machine à états).
- **Rendu des panneaux** : `NSSplitView` (`NSSplitViewController` avec trois `NSSplitViewItem` repliables) pour left / center / right, et un second pour center / bottom ; tailles minimales et persistance par slot via les API natives (`holdingPriority`, `collapsed`). Les splits de la zone centrale (parts égales, non redimensionnables) restent en SwiftUI (`HStack`/`VStack`). Pas de layout manuel via `GeometryReader` (`architecture` : utiliser la plateforme).
- **Raccourcis** : `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` au niveau fenêtre, avant SwiftUI ; le registre décide et consomme ou laisse passer (R25). Pas de `.keyboardShortcut` SwiftUI dispersés (R22).
- **Barre d'outils** : `NSToolbar` avec son délégué dans `Layout/` ; la liste des éléments et leurs badges vivent dans `LayoutManager`. SwiftUI `.toolbar` rejeté (ordre et menus secondaires mal contrôlables, R30–R31).
- **Enregistrement des features** : des `struct` internes à `Layout/` — `PanelDescriptor(id, title, side, defaultShortcut, makeView)`, `CenterTabDescriptor(kind, makeView(payload), serialize)`, un élément de toolbar (`id, title, icon, placement, kind`) et une entrée d'accueil (`id, title, icon, section, action`) — passées à `Layout` par chaque feature au démarrage (`GitFeature.register(in:)`). Activation/désactivation d'un panneau et fermeture d'un onglet sont des closures du descripteur, pas des événements diffusés.

## Décisions

Voir [decisions.md](decisions.md).
