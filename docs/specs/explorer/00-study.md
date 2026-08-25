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
- R4 — Les entrées **ignorées par git** (info reçue de `git`, R14) sont grisées. Les dossiers de la liste d'exclusion commune (`coding-rules` R10.6 : `node_modules`, `target`, `.build`…) sont grisés même sans info git, et jamais dépliés automatiquement (R11).
- R5 — Un toggle « masquer les fichiers ignorés » (menu du panneau, persisté dans `state.json`) cache les entrées grisées. Défaut : visibles.
- R6 — Liens symboliques : affichés avec une icône dédiée, dépliables si dossier, jamais suivis lors d'une opération récursive (suppression, rafraîchissement).

### Chargement et rafraîchissement

- R7 — Chargement **par niveau** : le contenu d'un dossier est lu à son premier dépliage (`coding-rules` R15.3). Aucune lecture récursive, jamais.
- R8 — Le premier niveau est lu à l'activation du panneau (`layout` R4), hors main actor, et rendu dès disponible. Un dossier de plus de 5 000 entrées est affiché tronqué (« … et N autres ») avec un bouton pour tout charger.
- R9 — Rafraîchissement par `FSWatchService` (`coding-rules` R5.5) : à un événement sur un chemin, seul le dossier parent concerné est relu, et seulement s'il est déplié (sinon marqué « stale » et relu au prochain dépliage). L'abonnement est actif uniquement panneau visible ; à la réactivation, les dossiers dépliés sont relus une fois.
- R10 — La relecture d'un dossier préserve : l'état déplié des sous-dossiers encore présents, la sélection (si l'élément existe encore), le scroll.
- R11 — État déplié persisté dans `state.json` (liste de chemins relatifs) et restauré ; les dossiers grisés (R4) ne sont jamais restaurés dépliés.

### Ouverture

- R12 — Simple clic sur un fichier : ouverture en onglet **aperçu** dans le groupe actif via l'`EventBus` (`openFile(path, preview: true)`) ; un seul onglet aperçu par groupe, remplacé par l'aperçu suivant. Double clic, ou toute édition dans l'onglet, le fixe (`editor` définit l'onglet). Clic sur un fichier déjà ouvert : active son onglet.
- R13 — `alt+clic` (ou entrée de menu) : ouvre dans un **nouveau groupe** à droite (`layout` R9) si l'on veut comparer.
- R14 — Suivi de l'onglet actif : quand l'onglet actif change et qu'il correspond à un fichier sous la racine, l'arbre déplie le chemin et sélectionne le fichier (sans le faire défiler si déjà visible). Désactivable par toggle du panneau (persisté). Un fichier hors racine ne déplie rien.
- R15 — Badges git : `git` publie `gitStatusChanged(repo, [path: GitFileStatus])` ; l'explorer colore les fichiers (modifié, ajouté, non suivi, conflit) et propage un point sur les dossiers ancêtres. Sans plugin git ou hors repo : aucun badge, aucune erreur.

### Opérations

- R16 — Nouveau fichier / nouveau dossier : créés dans le dossier sélectionné (ou le parent du fichier sélectionné, ou la racine), nom saisi en ligne, puis le fichier est ouvert (fixe). Le nom peut contenir des `/` pour créer les dossiers intermédiaires.
- R17 — Renommer : édition en ligne (`enter` sur l'élément ou menu). Les onglets ouverts sur ce chemin sont notifiés (`fileRenamed(old, new)`) ; `editor` les suit.
- R18 — Supprimer : vers la **corbeille** (`trashItem`), avec confirmation listant le nombre d'éléments pour un dossier non vide. Onglets ouverts notifiés (`fileDeleted`).
- R19 — Toute opération est refusée si le chemin cible n'est pas sous la racine (`coding-rules` R16.4) ou si le nom est vide, `.`/`..`, ou contient un caractère interdit. Une erreur d'IO (permission, existe déjà) s'affiche en bannière du panneau (`coding-rules` R8.9) et ne modifie pas l'arbre.
- R20 — Menu contextuel : Nouveau fichier, Nouveau dossier, Renommer, Supprimer, Révéler dans le Finder, Copier le chemin (relatif à la racine), Copier le chemin absolu. Pas de « terminal ici » (`product` R4), pas de copier/couper/coller de fichiers, pas de drag & drop.
- R21 — Navigation clavier dans l'arbre : `↑↓` déplacent, `→` déplie / `←` replie ou remonte, `enter` renomme, `space` ouvre en aperçu, `cmd+↓` ouvre fixe, `cmd+delete` supprime, `escape` rend le focus au centre (`layout` R6).

## Cas limites

- Dossier non lisible (permissions) : affiché avec icône verrou, dépliage sans effet, pas d'erreur bloquante.
- Rafale d'événements (`git checkout`, `npm install`) : le debounce de `FSWatchService` (~300 ms) coalesce ; l'explorer relit chaque dossier concerné une seule fois par rafale.
- Fichier sélectionné supprimé de l'extérieur : sélection perdue, aucun message.
- Renommage qui ne change que la casse (`Foo` → `foo`) sur APFS insensible à la casse : autorisé, effectué via un nom temporaire.
- Volume réseau ou lent : la lecture hors main actor garantit une UI réactive ; un dossier en cours de lecture affiche un état « chargement » (`coding-rules` R9.9).
- Workspace = `$HOME` : arbre énorme mais paresseux ; `Library` est grisé via la liste d'exclusion commune.

## Hors périmètre v1

- Drag & drop, copier/couper/coller de fichiers, déplacement entre dossiers.
- Recherche dans l'arbre (le quick open `cmd+p` est dans `editor`).
- Icônes par type de fichier (une icône fichier / dossier / lien suffit).
- Multi-sélection et opérations groupées.
- Ouvrir un fichier avec une application externe (hors « révéler dans le Finder »).
- Suivi de fichiers hors de la racine.

## Options techniques

- **Modèle** : `FileNode` (`struct`, `Identifiable` par chemin relatif, `Sendable`) : nom, kind (file/dir/symlink), isIgnored, isLoaded, children. `ExplorerModel` (`@MainActor @Observable`) tient l'arbre déplié, la sélection, les badges ; `FileSystemReader` (`actor`) lit un niveau (`FileManager.contentsOfDirectory` avec `resourceKeys` `isDirectory`, `isSymbolicLink`, `isHidden`) hors main actor.
- **Vue** : `List` avec `OutlineGroup` ou `DisclosureGroup` SwiftUI ; si les performances sur > 1 000 lignes visibles déçoivent, `NSOutlineView` confiné (`coding-rules` R9.1). À trancher sur prototype.
- **Opérations** : `FileManager` (`createDirectory`, `moveItem`, `trashItem`), dans l'actor, erreurs traduites en `ExplorerError`.
- **Événements EventBus** (types dans `WraithKit`) : consommés `fsChanged(paths)`, `activeTabChanged(tab)`, `gitStatusChanged(repo, statuses)` ; émis `openFile(path, preview, newGroup)`, `fileRenamed(old, new)`, `fileDeleted(path)`.
- **Tests** : tri (R2), filtrage (R3–R5), fusion d'une relecture avec préservation (R10), validation des noms et chemins (R19), propagation des badges (R15), sur un répertoire temporaire (`coding-rules` R14.4).

## Décisions

Voir [decisions.md](decisions.md).
