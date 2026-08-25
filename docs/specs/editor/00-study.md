# editor — Étude

## Objectif

Onglet central `editor.file` : lire et éditer les fichiers texte du workspace avec highlighting tree-sitter, preview markdown, recherche dans le fichier, plus deux points d'entrée : quick open (`cmd+p`, fuzzy sur les chemins) et recherche dans le contenu (`cmd+shift+f`, panneau bas). Éditeur **simple** : ni complétion, ni LSP, ni multi-curseurs.

## User stories

- US1 — Je clique un fichier dans l'explorer : il s'affiche en < 100 ms, coloré, en aperçu ; je tape, l'onglet devient fixe et marqué modifié ; `cmd+s` sauve.
- US2 — `cmd+p`, je tape `usrctrl`, `UserController.java` remonte en tête ; `enter` l'ouvre.
- US3 — `cmd+shift+f`, je tape un terme : les occurrences du workspace s'affichent groupées par fichier ; un clic ouvre le fichier à la ligne.
- US4 — Un build régénère un fichier ouvert non modifié : il se recharge seul. S'il était modifié, on me demande.
- US5 — Un `README.md` s'ouvre en source ; `cmd+shift+v` bascule en preview.
- US6 — J'ouvre par erreur un binaire ou un fichier de 200 Mo : message clair, pas de gel.

## Règles fonctionnelles

### Onglet et cycle de vie

- R1 — Un onglet `editor.file` référence un fichier (chemin relatif à la racine, absolu sinon) et possède un état : `preview` / `pinned`, `isDirty`, position du curseur, scroll. Un même fichier n'est ouvert qu'une fois par groupe ; l'ouvrir à nouveau active l'onglet existant.
- R2 — Aperçu (`explorer` R12) : titre en italique ; un seul aperçu par groupe, remplacé par le suivant. Devient fixe (`pinned`) sur double clic, première modification, ou `cmd+k enter` (« keep open »).
- R3 — Ouverture (`Editor.open(path, preview:, newGroup:, line:)`, appelé par l'explorer, git, la palette, la recherche) : lecture hors main actor ; détection d'encodage UTF-8 (BOM toléré), sinon Latin-1 avec avertissement ; fins de ligne détectées (LF/CRLF) et préservées à la sauvegarde ; si `line` est fourni, le curseur y est placé et la ligne centrée.
- R4 — Persistance (`layout` R28) : chemin, `pinned`, curseur, scroll. `isDirty` n'est jamais persisté : à la fermeture de la fenêtre avec un onglet modifié, confirmation (`layout` R15) ; le contenu non sauvé est perdu si l'on confirme. Fichier disparu à la restauration : onglet ignoré (`product` cas limite tranché).
- R5 — Titre : nom du fichier ; si deux onglets du même groupe portent le même nom, le dossier parent est ajouté (`a/index.ts`, `b/index.ts`). Marqueur `●` quand `isDirty`.

### Édition

- R6 — Fonctions v1 : saisie, sélection, undo/redo (`cmd+z`/`cmd+shift+z`), couper/copier/coller, indentation en conservant l'indent de la ligne précédente, `tab` insère selon le fichier (espaces/tabs détectés sur les 100 premières lignes, défaut 4 espaces), `cmd+]`/`cmd+[` indente/désindente la sélection, `cmd+/` commente/décommente la ligne (préfixe fourni par la grammaire), `cmd+d` non (réservé split, `layout`), déplacer une ligne `alt+↑/↓`, aller à la ligne `cmd+l`.
- R7 — Recherche dans le fichier : `cmd+f` (barre en haut de l'onglet, insensible à la casse par défaut, `enter`/`shift+enter` suivant/précédent, occurrences surlignées), `cmd+alt+f` remplacer (un / tous). `escape` ferme la barre.
- R8 — Sauvegarde : `cmd+s` explicite uniquement, **pas d'autosave**. Écriture atomique (`coding-rules`) en conservant encodage et fins de ligne ; nouvelle ligne finale ajoutée si absente (option désactivable dans la config globale, `editor.insertFinalNewline`). `cmd+alt+s` sauve tous les onglets modifiés.
- R9 — Fichier modifié sur disque (via `FSWatchService`) : si l'onglet n'est pas `isDirty` → rechargement silencieux avec curseur et scroll préservés ; si `isDirty` → bannière « modifié sur disque » avec *Garder mes changements* / *Recharger*. Fichier supprimé sur disque : bannière « supprimé » ; l'onglet reste, `cmd+s` le recrée. Fichier renommé (`Editor.fileRenamed`, `explorer` R17) : l'onglet suit.
- R10 — Conflit à la sauvegarde (fichier modifié sur disque depuis la dernière lecture, et l'utilisateur n'a pas tranché la bannière R9) : la sauvegarde est refusée avec *Écraser* / *Annuler*.

### Highlighting

- R11 — Grammaires v1 (mapping par extension et par nom de fichier) : java, kotlin, typescript, tsx, javascript, json, yaml, toml, markdown, sql, bash (`.sh`, `.zsh`, `.zshrc`…), swift, html, css, dockerfile (`Dockerfile*`). Extension inconnue → texte brut.
- R12 — Highlighting fourni par le dossier partagé `Highlight/` (`architecture.md`) : Neon attache un highlighter à l'`NSTextView`, parse hors main actor, de façon incrémentale et annulable à chaque frappe, et applique lui-même les attributs. L'éditeur ne fait que fournir la grammaire (R11) et le thème : les rôles (`keyword`, `string`, `comment`, `type`, `function`, `number`, `variable`, `punctuation`…) sont mappés en couleurs par `ThemeService`.
- R13 — Le highlighting est dégradable : grammaire absente, parsing en erreur ou trop lent (> 200 ms sur le premier parse) → texte brut, log `debug`, aucune bannière.
- R14 — Markdown : l'onglet a deux modes, `source` (défaut) et `preview`, bascule `cmd+shift+v` ; le mode est persisté avec l'onglet. Preview rendue depuis l'AST `swift-markdown` : titres, listes, code (coloré via R11 si le langage est connu), tableaux, liens (ouverts dans le navigateur sur `cmd+clic` ; liens relatifs vers un fichier du workspace ouverts dans Wraith), images locales du workspace uniquement, jamais de ressource distante (`architecture.md`, sécurité).

### Limites de taille et binaires

- R15 — Détection **avant** lecture complète : un fichier est binaire s'il contient un octet nul dans ses 8 premiers Ko ou si son extension est dans une liste connue (images, archives, exécutables…). Un binaire n'est pas ouvert : onglet « fichier binaire — N Ko » avec *Révéler dans le Finder*.
- R16 — Taille : > 2 Mo → ouverture en **lecture seule sans highlighting** avec bannière ; > 50 Mo → refus (message avec taille). Ligne > 10 000 caractères → highlighting désactivé pour le fichier.

### Quick open (`cmd+p`)

- R17 — Palette partagée (`Palette/`, `architecture.md`, aussi utilisée par `run`) ; recherche fuzzy sur les chemins relatifs du workspace, insensible à la casse, scoring par la lib fuzzy retenue (sous-séquence avec bonus sur les frontières `/`, `.`, `_`, `-`, camelCase, et sur le nom de fichier). Les 50 meilleurs résultats sont affichés ; `↑↓` naviguent, `enter` ouvre (fixe), `cmd+enter` ouvre dans un nouveau groupe, `escape` ferme.
- R18 — L'index des chemins est construit **à la première ouverture de la palette**, hors main actor, en parcourant le workspace avec la liste d'exclusion commune (`architecture.md`) plus les entrées gitignored connues (via `Git.statusChanges`, sinon ignorées) ; il est maintenu par `FSWatchService` ensuite. Plafond : 200 000 entrées, au-delà l'index est tronqué avec avertissement dans la palette.
- R19 — Palette vide (aucune saisie) : les fichiers récemment ouverts de ce workspace, les plus récents en premier (liste de 50 persistée dans `state.json`).

### Recherche dans le contenu (`cmd+shift+f`)

- R20 — Panneau **bas** `editor.search` : champ de recherche, options *casse* / *mot entier* / *regex*, filtre d'inclusion (glob, ex. `src/**/*.ts`). Exécution via le binaire `rg` s'il est dans le `PATH`, sinon `grep -rn` (`Process` avec arguments en tableau, jamais un shell — `architecture.md`, sécurité) ; exclusions communes appliquées ; `.gitignore` respecté par `rg` nativement.
- R21 — Résultats groupés par fichier, dépliés, ligne avec la correspondance surlignée ; clic ou `enter` ouvre le fichier à la ligne (aperçu), `cmd+enter` fixe. Plafond 2 000 correspondances (message « résultats tronqués »). Une recherche en cours est annulée par la suivante ou par la fermeture du panneau.
- R22 — Pas de remplacement multi-fichiers en v1 (`sed`/`rg` au terminal).

### Raccourcis

- R23 — Les raccourcis de l'éditeur (`cmd+s`, `cmd+f`, `cmd+z`, `cmd+/`, `cmd+l`, `cmd+shift+v`…) sont déclarés au `ShortcutRegistry` avec la portée **onglet `editor.file` actif** : ils ne capturent rien quand un terminal a le focus (`layout` R25). `cmd+p` et `cmd+shift+f` sont globaux.

## Cas limites

- Fichier sans permission d'écriture : ouvert en lecture seule avec bannière ; `cmd+s` propose *Révéler dans le Finder*.
- Encodage non UTF-8 : lu en Latin-1, bannière ; la sauvegarde ré-écrit en **UTF-8** avec avertissement explicite dans la bannière (pas de conservation d'encodage exotique).
- Fichier en cours d'écriture par un autre process (build) : rafale d'événements coalescée par le debounce ; le rechargement (R9) lit l'état final.
- Grammaire qui crashe sur un fichier pathologique : tree-sitter est robuste ; en cas de timeout, R13.
- Quick open sur `$HOME` : index plafonné (R18), le message invite à ouvrir un sous-dossier.
- `rg` absent et `grep` sur un gros workspace : lent mais annulable ; message suggérant `brew install ripgrep`.

## Hors périmètre v1

- LSP, complétion, diagnostics, go-to-definition, formatage.
- Multi-curseurs, sélection par colonnes, minimap, code folding, bracket matching avancé.
- Remplacement multi-fichiers.
- Preview markdown côte à côte synchronisée.
- Édition de fichiers hors du workspace autrement qu'en ouvrant par chemin absolu (aucun « ouvrir un fichier » système).
- Autosave, historique local des versions.
- Thèmes de couleurs propres à l'éditeur (les rôles sont mappés par `ThemeService` sur le thème du terminal, `terminal` R14).

## Options techniques

- **Dossier** : `Sources/Wraith/Editor/` ; consomme les dossiers partagés `Highlight/` et `Palette/`.
- **Composant texte** : `NSTextView` sur **TextKit 2** (`NSTextLayoutManager`) dans un `NSViewRepresentable` (plateforme d'abord, `architecture.md` P3). Undo, sélection, IME, accessibilité, performance sur gros fichiers gratuits. Vue custom rejetée (coût énorme), TextKit 1 rejeté (déprécié de fait). Risque connu : angles morts de TextKit 2 (retour automatique à TextKit 1 sur certaines API) ; à valider par prototype au découpage de M1.
- **Highlighting** : `Highlight/` = SwiftTreeSitter + Neon utilisés comme conçus (`architecture.md` P2) : `TextViewHighlighter` de Neon attaché à l'`NSTextView`, avec `LanguageConfiguration` par grammaire (queries `highlights.scm` des packages SPM `tree-sitter-*`). Neon gère l'incrémental, l'annulation et l'application des attributs ; l'éditeur ne réécrit aucune session de parsing. `Highlight/` porte le mapping extension → grammaire (R11) et le mapping rôle → couleur via `ThemeService`.
- **Markdown** : `swift-markdown` (AST `Document`) → SwiftUI (`Text` avec `AttributedString` + blocs). Code blocks colorés via `Highlight/`.
- **Fuzzy** : `Palette/` avec la lib fuzzy SPM retenue (`architecture.md`) ; l'éditeur fournit les chemins et reçoit la sélection. Pas de scoring maison.
- **Recherche contenu** : `Process` `rg --json` (parsing JSON par ligne) ou `grep -rnI --null` ; une `Task` annulable produit un `AsyncStream<SearchMatch>`.
- **Tests** (parsers uniquement) : détection binaire/encodage/indent/EOL (R3, R6, R15), parsing sortie `rg`/`grep` (R20), mapping extension → grammaire (R11), titres dédupliqués (R5).

## Décisions

Voir [decisions.md](decisions.md).
