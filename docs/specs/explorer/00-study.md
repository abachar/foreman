# explorer — Étude

## Objectif

Panneau gauche `explorer.tree` : l'arbre de fichiers du workspace, paresseux, rafraîchi par FSEvents, depuis lequel on ouvre des fichiers (aperçu ou fixe) et on fait le CRUD de base. Il affiche les états git fournis par `git`, sans en dépendre.

## User stories

- US1 — `cmd+shift+e` : l'arbre apparaît sur la racine du workspace, dossiers repliés ; je déplie à la demande, sans attendre.
- US2 — Je crée/renomme/supprime un fichier au terminal : l'arbre se met à jour seul en moins d'une seconde.
- US3 — Un clic sur un fichier l'ouvre en aperçu dans le groupe actif ; un double clic le fixe. Cliquer un autre fichier remplace l'aperçu.
- US4 — Quand je change d'onglet, l'arbre déplie et sélectionne le fichier correspondant.
- US5 — Je repère d'un coup d'œil ce qui est modifié (git) et ce qui est ignoré (grisé).
- US6 — Clic droit : nouveau fichier/dossier, renommer, supprimer, révéler dans le Finder, copier le chemin.

## Règles fonctionnelles

### Contenu et filtrage

- R1 — La racine de l'arbre est la racine du workspace ; elle n'est pas affichée comme nœud, ses enfants sont le premier niveau.
- R2 — Tri : dossiers d'abord, puis fichiers, chacun par nom insensible à la casse (ordre `localizedStandardCompare`, donc `file2 < file10`).
- R3 — Tout est visible sauf `.git/` (et `.wraith/state.json`, `.DS_Store`). Les dotfiles sont affichés.
- R4 — Les entrées **ignorées par git** (info reçue de `git`, R14) sont grisées. Les dossiers de la liste d'exclusion commune (`architecture.md` : `node_modules`, `target`, `.build`…) sont grisés même sans info git, et jamais dépliés automatiquement (R11).
- R5 — Un toggle « masquer les fichiers ignorés » (menu du panneau, persisté dans `state.json`) cache les entrées grisées. Défaut : visibles.
- R6 — Liens symboliques : affichés avec une icône dédiée, dépliables si dossier, jamais suivis lors d'une opération récursive (suppression, rafraîchissement).

### Chargement et rafraîchissement

- R7 — Chargement **par niveau** : le contenu d'un dossier est lu à son premier dépliage (paresse, `architecture.md` P4). Aucune lecture récursive, jamais.
- R8 — Le premier niveau est lu à l'activation du panneau (`layout` R4), hors main actor, et rendu dès disponible. Un dossier de plus de 5 000 entrées est affiché tronqué (« … et N autres ») avec un bouton pour tout charger.
- R9 — Rafraîchissement par `FSWatchService` (flux FSEvents unique, `architecture.md`) : à un événement sur un chemin, seul le dossier parent concerné est rechargé (`reloadItem(_:reloadChildren:)`), et seulement s'il est déplié (un dossier replié est relu à son prochain dépliage). L'abonnement est actif uniquement panneau visible ; à la réactivation, les dossiers dépliés sont rechargés une fois.
- R10 — Le rechargement d'un dossier conserve l'état déplié, la sélection et le scroll pour les éléments encore présents ; c'est le comportement de `NSOutlineView` avec des items à identité stable (chemin relatif), rien à fusionner à la main.
- R11 — État déplié persisté dans `state.json` (liste de chemins relatifs) et restauré ; les dossiers grisés (R4) ne sont jamais restaurés dépliés.

### Ouverture

- R12 — Simple clic sur un fichier : ouverture en onglet **aperçu** dans le groupe actif via `Editor.open(path, preview: true)` ; un seul onglet aperçu par groupe, remplacé par l'aperçu suivant. Double clic, ou toute édition dans l'onglet, le fixe (`editor` définit l'onglet). Clic sur un fichier déjà ouvert : active son onglet.
- R13 — `alt+clic` (ou entrée de menu) : ouvre dans un **nouveau groupe** à droite (`layout` R9) si l'on veut comparer.
- R14 — Suivi de l'onglet actif (`Layout.activeTab`) : quand l'onglet actif change et qu'il correspond à un fichier sous la racine, l'arbre déplie le chemin et sélectionne le fichier (sans le faire défiler si déjà visible). Désactivable par toggle du panneau (persisté). Un fichier hors racine ne déplie rien.
- R15 — Badges git : l'explorer s'abonne à `Git.statusChanges` (`AsyncStream` de `(repo, [path: GitFileStatus])`) ; il colore les fichiers (modifié, ajouté, non suivi, conflit) et propage un point sur les dossiers ancêtres. Hors repo : aucun badge, aucune erreur.

### Opérations

- R16 — Nouveau fichier / nouveau dossier : créés dans le dossier sélectionné (ou le parent du fichier sélectionné, ou la racine), nom saisi en ligne, puis le fichier est ouvert (fixe). Le nom peut contenir des `/` pour créer les dossiers intermédiaires.
- R17 — Renommer : édition en ligne (`enter` sur l'élément ou menu). L'explorer appelle `Editor.fileRenamed(old, new)` pour que les onglets ouverts suivent.
- R18 — Supprimer : vers la **corbeille** (`trashItem`), avec confirmation listant le nombre d'éléments pour un dossier non vide. L'explorer appelle `Editor.fileDeleted(path)`.
- R19 — Toute opération est refusée si le chemin cible n'est pas sous la racine (`architecture.md`, sécurité) ou si le nom est vide, `.`/`..`, ou contient un caractère interdit. Une erreur d'IO (permission, existe déjà) s'affiche en bannière du panneau et ne modifie pas l'arbre.
- R20 — Menu contextuel : Nouveau fichier, Nouveau dossier, Renommer, Supprimer, Révéler dans le Finder, Copier le chemin (relatif à la racine), Copier le chemin absolu. Pas de « terminal ici » (`product` R4), pas de copier/couper/coller de fichiers, pas de drag & drop.
- R21 — Navigation clavier dans l'arbre : `↑↓` déplacent, `→` déplie / `←` replie ou remonte, `enter` renomme, `space` ouvre en aperçu, `cmd+↓` ouvre fixe, `cmd+delete` supprime, `escape` rend le focus au centre (`layout` R6).

## Cas limites

- Dossier non lisible (permissions) : affiché avec icône verrou, dépliage sans effet, pas d'erreur bloquante.
- Rafale d'événements (`git checkout`, `npm install`) : le debounce de `FSWatchService` (~300 ms) coalesce ; l'explorer relit chaque dossier concerné une seule fois par rafale.
- Fichier sélectionné supprimé de l'extérieur : sélection perdue, aucun message.
- Renommage qui ne change que la casse (`Foo` → `foo`) sur APFS insensible à la casse : autorisé, effectué via un nom temporaire.
- Volume réseau ou lent : la lecture hors main actor garantit une UI réactive ; un dossier en cours de lecture affiche un état « chargement ».
- Workspace = `$HOME` : arbre énorme mais paresseux ; `Library` est grisé via la liste d'exclusion commune.

## Hors périmètre v1

- Drag & drop, copier/couper/coller de fichiers, déplacement entre dossiers.
- Recherche dans l'arbre (le quick open `cmd+p` est dans `editor`).
- Icônes par type de fichier (une icône fichier / dossier / lien suffit).
- Multi-sélection et opérations groupées.
- Ouvrir un fichier avec une application externe (hors « révéler dans le Finder »).
- Suivi de fichiers hors de la racine.

## Options techniques

- **Dossier** : `Sources/Wraith/Explorer/`.
- **Vue** : `NSOutlineView` dans un `NSViewRepresentable` (plateforme d'abord, `architecture.md` P3), data source paresseux : `numberOfChildren`/`child(index:)` lisent le niveau au premier dépliage, `reloadItem(_:reloadChildren:)` pour R9. L'identité d'un item est son chemin relatif.
- **Modèle** : `FileNode` (`struct`, `Identifiable` par chemin relatif) : nom, kind (file/dir/symlink), isIgnored, children chargés ou non. `ExplorerModel` (`@MainActor @Observable`) tient la sélection, les badges et les toggles ; la lecture d'un niveau est un simple `FileManager.contentsOfDirectory(resourceKeys: isDirectory, isSymbolicLink, isHidden)` dans une `Task` hors main actor.
- **Opérations** : `FileManager` (`createDirectory`, `moveItem`, `trashItem`), erreurs enveloppées dans `ExplorerError`.
- **Liens avec les autres features** (appels directs, `architecture.md`) : consomme `FSWatchService`, `Layout.activeTab`, `Git.statusChanges` ; appelle `Editor.open(path, preview:, newGroup:)`, `Editor.fileRenamed`, `Editor.fileDeleted`.
- **Tests** : tri (R2), filtrage (R3–R5), validation des noms et chemins (R19), propagation des badges (R15), sur un répertoire temporaire.

## Décisions

Voir [decisions.md](decisions.md).
