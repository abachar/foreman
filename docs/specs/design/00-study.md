# design — Étude

## Objectif

Donner à Wraith une identité visuelle **choisie**, au lieu du rendu système par défaut. Le rendu 100 % natif d'aujourd'hui — matériaux translucides (`.bar`), Liquid Glass de macOS 26, chrome système — n'est pas ce que l'auteur veut voir huit heures par jour. La cible est le style **« Islands »** d'IntelliJ en thème **Dark** : un fond uni sombre, des zones (éditeur, panneaux, terminal) posées dessus comme des îlots à coins arrondis séparés par des gouttières, une barre d'outils plate et opaque, des onglets plats, des barres fines, **un seul accent**, et **aucune transparence**.

Domaine **transverse** : il ne livre aucune feature. Il définit les jetons visuels (*tokens*) et dit quelle surface porte lequel. Le code vit dans `Wraith/App/` (extension de `ThemeService`) et dans les vues existantes ; il n'y a pas de dossier `Design/`, pas de second service de thème.

## User stories

- US1 — J'ouvre Wraith : la fenêtre est un aplat sombre, l'éditeur, l'explorer et le terminal sont des blocs arrondis distincts, et rien ne laisse transparaître le bureau ni une fenêtre du dessous.
- US2 — Je change une couleur dans `.wraith/config.json` : elle s'applique sans redémarrer, comme le reste de la config.
- US3 — Le terminal a exactement le même noir que l'îlot qui le contient : je ne vois pas de rectangle plus clair ou plus foncé à l'intérieur du bloc.
- US4 — Je regarde une fenêtre avec quatre onglets et trois panneaux : je vois d'un coup d'œil quel groupe est actif, parce que c'est la seule chose colorée à l'accent.
- US5 — Je lis du texte gris sur fond sombre pendant une heure sans forcer.

## Règles fonctionnelles

### Principes visuels

- R1 — **Aucune transparence et aucun matériau système dans le chrome de l'app.** Ni `.bar`, ni `.regularMaterial`/`.ultraThinMaterial`, ni `NSVisualEffectView`, ni vibrancy, ni Liquid Glass. Chaque surface est un aplat opaque tiré d'un token. Une ombre est autorisée seulement pour la palette, qui flotte au-dessus de la fenêtre.
- R2 — **Îlots.** Le fond de la fenêtre est un aplat sombre uni. Le centre (groupes d'onglets), chaque panneau visible et la palette sont des rectangles à coins arrondis posés dessus, séparés du bord de la fenêtre et les uns des autres par une **gouttière constante**. C'est le fond de fenêtre visible dans la gouttière qui sépare les zones : **aucun trait de séparation** entre deux îlots. À l'intérieur d'un îlot, un séparateur fin est autorisé (barre d'onglets ↔ contenu, en-tête de panneau ↔ liste).
- R3 — **Un seul accent.** Une couleur d'accent, et une seule, marque ce qui a le focus ou la sélection : bordure du groupe actif (`layout` R17), ligne sélectionnée de la palette et des listes, onglet actif, contrôle focalisé. Les seules autres couleurs de l'interface sont les quatre badges d'état déjà définis (`ToolbarBadge.BadgeColor` : vert, orange, rouge, bleu) et les couleurs de highlighting (`editor` R12).
- R4 — **Barres fines et plates.** Barre d'outils, barre d'onglets, en-têtes de panneaux et lignes d'état ont une hauteur fixe, un fond opaque uni, **pas de dégradé, pas d'ombre, pas de bordure** hors du séparateur interne autorisé par R2.
- R5 — **Onglets plats.** Un onglet est un rectangle sans forme ni coin arrondi : actif = fond de l'îlot + un liseré d'accent de 2 pt sur un seul bord, inactif = transparent sur la barre et texte en couleur secondaire. Aucun bouton de fermeture n'apparaît sur un onglet inactif tant que la souris n'est pas dessus.
- R6 — **Typographie.** Deux familles, pas trois : la police système pour l'interface, `ThemeService.editorFont` (la mono de `terminal` R14) pour le code, le terminal, les diffs et le SQL. Trois tailles d'interface seulement (`small`, `body`, `title`) et deux graisses (`regular`, `medium`).
- R7 — **Contraste mesuré.** Texte principal sur son fond : ratio ≥ 4,5:1 ; texte secondaire et icônes : ≥ 3:1 ; accent sur son fond : ≥ 3:1. Le ratio est calculé, pas estimé, et la fonction qui le calcule est testée.

### Tokens

- R8 — **Toutes** les couleurs, tous les rayons, toutes les gouttières et toutes les hauteurs de barre du chrome viennent de tokens exposés par `ThemeService`. Aucune vue ne nomme une couleur système (`.controlBackgroundColor`, `.labelColor`, `Color.accentColor`), un matériau, ni une valeur littérale. C'est déjà la règle (`coding-rules`, UI : « couleurs, polices, métriques : via `ThemeService`, jamais en dur ») ; elle est aujourd'hui violée en treize endroits, listés dans le backlog M8.
- R9 — Les tokens forment quatre familles, et rien d'autre :
  | Famille | Tokens |
  |---|---|
  | Fonds | `windowBackground` (l'aplat sous les îlots), `surface` (fond d'un îlot), `surfaceRaised` (barre d'outils, barre d'onglets, en-tête de panneau), `surfaceSunken` (champ de saisie, ligne de code surlignée) |
  | Texte et traits | `textPrimary`, `textSecondary`, `textDisabled`, `separator`, `border` |
  | Accent et états | `accent`, `accentText` (texte posé sur l'accent), `statusGreen`, `statusOrange`, `statusRed`, `statusBlue` |
  | Métriques | `islandRadius`, `gutter`, `barHeight`, `rowHeight`, `contentInset` |
- R10 — Deux jeux de tokens, `dark` et `light`, de structure identique, choisis par le mode de `terminal` R14 (`light` / `dark` / `system`). **Seul `dark` est dessiné et validé en v1** ; `light` est dérivé mécaniquement et n'est pas un objectif (voir hors périmètre). La palette ANSI 16 couleurs de `terminal` R14 fait désormais partie du jeu de tokens et doit s'accorder avec lui (R13).
- R11 — Les tokens sont surchargeables par la section `theme` de `.wraith/config.json` : `{ "theme": { "accent": "#4C8DF6", "islandRadius": 10 } }`. Clé inconnue → avertissement, ignorée ; valeur mal formée (couleur hors `#rgb`/`#rrggbb`, métrique négative ou hors bornes) → avertissement, valeur par défaut conservée ; la section entière est optionnelle (`config` R2, R5) et rechargée à chaud (`config` R6). Aucun fichier de thème séparé (voir hors périmètre).

### Ce qui reste natif

- R12 — Ces composants ne sont **pas remplacés**, seulement habillés (fond, couleurs, hauteur de ligne, style de séparateur) : `NSSplitViewController` / `NSSplitView` (les zones, `layout`), `NSOutlineView` (l'explorer), `NSTextView` sur TextKit 2 (éditeur, diff, éditeur SQL), la surface SwiftTerm, `NSAlert`, `NSMenu`, `NSSavePanel`, `NSTextFinder`, la barre de recherche native. `architecture.md` P3 tient : on n'en réimplémente aucun pour une question d'apparence.
- R13 — La surface SwiftTerm reçoit `nativeBackgroundColor` = le token `surface` de l'îlot qui la contient, pour qu'il n'y ait aucune démarcation à l'intérieur du bloc (US3) ; sa palette ANSI et son `caretColor`/`selectedTextBackgroundColor` viennent des mêmes tokens (`installColors`, `terminal` R14).

### Ce qui change

- R14 — **Fenêtre** : fond opaque au token `windowBackground` ; la barre de titre ne se distingue pas du reste (`titlebarAppearsTransparent`), les feux tricolores restent ceux du système et à leur place. Le titre textuel de la fenêtre est masqué : le nom du dossier est déjà dans l'interface.
- R15 — **Barre d'outils** : fond `surfaceRaised` opaque, hauteur fixe (R4), boutons plats sans bordure ni fond au repos, fond `surfaceSunken` au survol et à l'appui, badges (`layout` R31) rendus avec les tokens d'état. Deux voies techniques (options ci-dessous), tranchées dans le backlog M8.
- R16 — **Barre d'onglets** (`layout` R16) : `surfaceRaised`, onglets selon R5, marqueur `isDirty` et badge de point conservés, séparateur fin sous la barre uniquement.
- R17 — **Panneaux** : chaque panneau visible est un îlot (R2) avec un en-tête `surfaceRaised` portant son titre et son menu ; les bannières d'erreur existantes (explorer R19, config R7, `git`, `postgres`) prennent le token d'état correspondant au lieu de `.background(.bar)` et de `.red`.
- R18 — **Palette** (`Palette/`) : îlot flottant, `surface`, `islandRadius`, ombre portée (seule exception à R1), champ de saisie `surfaceSunken`, ligne sélectionnée à l'accent, sous-titres en `textSecondary`. Pas de barre de titre, pas de matériau.
- R19 — **Écran d'accueil** (`layout` R33) : mêmes tokens, raccourcis affichés en `textSecondary`, aucune illustration ni dégradé.
- R20 — **Séparateurs de zones** : les diviseurs de `NSSplitView` sont peints à la couleur `windowBackground` et à l'épaisseur `gutter`, ce qui produit la gouttière de R2 sans dessiner de trait.

## Cas limites

- Changement d'apparence macOS en cours de session : `ThemeService` l'observe déjà (`terminal` R14) ; le jeu de tokens bascule et toutes les surfaces se repeignent, y compris les surfaces SwiftTerm ouvertes.
- Fenêtre très petite : la gouttière et le rayon restent constants ; ce sont les îlots qui rétrécissent, jusqu'aux minimums de `layout` R19.
- Plein écran : la gouttière subsiste sur les quatre bords ; c'est voulu, c'est ce qui fait l'îlot.
- Panneau masqué : sa gouttière disparaît avec lui, l'îlot voisin s'étend ; aucune bande vide.
- « Réduire la transparence » et « Augmenter le contraste » (Accessibilité) : il n'y a rien de translucide à réduire (R1) ; l'augmentation du contraste n'est pas gérée en v1 (hors périmètre).
- Un token surchargé qui casse le contraste de R7 : l'avertissement est affiché une fois, la valeur de l'utilisateur est **quand même appliquée** — c'est sa fenêtre.
- Impression, capture d'écran, mode « inverser les couleurs » : rien de particulier, tout est opaque.

## Hors périmètre v1

- **Thème clair dessiné** : `light` existe mécaniquement (R10), il n'est ni travaillé ni validé.
- Fichiers de thème utilisateur, thèmes partagés, sélecteur de thème dans l'interface : la section `theme` de la config suffit (même politique que le reste, `config`, hors périmètre : pas d'éditeur de préférences graphique).
- Jeu d'icônes propre : SF Symbols et les SVG déjà présents restent (`IconImage`).
- Animations, transitions, effets au survol autres qu'un changement de fond.
- Remplacement des feux tricolores ou de la barre de titre par des contrôles maison.
- Accent par panneau, couleur par repo, coloration des onglets par type.
- Support d'« Augmenter le contraste » et des réglages d'accessibilité de couleur.
- Redessin des composants natifs de R12.

## Options techniques

### `ThemeService` étendu, pas un second service

`ThemeService` (`Wraith/App/ThemeService.swift`) porte déjà : la section `terminal` décodée (`Settings`), la police (`editorFont`), le mode (`isDark(systemIsDark:)`), les deux palettes ANSI (`TerminalPalette`) et les couleurs de rôle du highlighting (`color(for: HighlightRole)`). Les tokens de R9 s'ajoutent au même type : une `struct Tokens` par jeu, deux constantes statiques, un décodage de la section `theme` calqué sur `Settings.decode(from:)`. Un `DesignSystem` séparé serait un second propriétaire des mêmes informations, ce que `architecture.md` interdit (services partagés, créés une fois dans `App`).

### La barre d'outils : deux voies

C'est le seul vrai choix technique, parce que `NSToolbar` ne rend pas la main sur son fond.

**Option A — garder `NSToolbar` et l'habiller.** Ce qu'AppKit permet réellement, avec des API de longue date :

- `NSWindow.titlebarAppearsTransparent = true` : la zone de titre ne peint plus son propre fond, c'est le fond de la fenêtre qui apparaît dessous.
- `NSWindow.backgroundColor` : l'aplat opaque, donc le token `windowBackground` ou `surfaceRaised` selon le rendu voulu.
- `NSWindow.titleVisibility = .hidden` : plus de titre textuel (R14).
- `NSWindow.styleMask` avec `.fullSizeContentView` : le contenu passe sous la zone de titre, ce qui permet de contrôler l'espace au-dessus des îlots.
- `NSWindow.toolbarStyle` : `.unified` (l'actuel), `.unifiedCompact` (barre plus fine, ce que veut R4), `.expanded`, `.preference`, `.automatic`.
- `NSToolbarItem.isBordered = false` et un `view` custom par élément : boutons plats dessinés par nous.

Ce que l'option A ne donne pas : `NSToolbar` n'expose aucune propriété de couleur de fond, et la façon dont macOS 26 peint sa zone (matériau, séparateur sous la barre au défilement) n'est pas contractuelle. Le résultat est donc « très proche » et **à vérifier sur la machine** ; il peut changer à une mise à jour de macOS. Coût : faible, quelques lignes dans `WorkspaceToolbar.attach(to:)` et un `view` par élément.

**Option B — retirer `NSToolbar` et dessiner la barre.** `window.toolbar = nil`, `styleMask.insert(.fullSizeContentView)`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, et une vue SwiftUI en haut du contenu qui rend les `ToolbarItemDescriptor` déjà déclarés par les features (`layout` R30). Contrôle total du fond, de la hauteur, des états de survol.

Ce que l'option B coûte : la zone des feux tricolores reste en haut à gauche, donc la barre doit réserver un retrait à gauche (~78 pt, à mesurer, et il change en plein écran) ; le déplacement de la fenêtre par la barre est à rétablir (`NSWindow.isMovableByWindowBackground`, ou une vue qui appelle `performDrag(with:)`) ; le débordement d'éléments, les info-bulles standard et la personnalisation de `NSToolbar` disparaissent — sans conséquence ici, `layout` R30 les interdit déjà. `layout` R30 et `architecture.md` (qui disent « barre d'outils native `NSToolbar` ») devraient être amendés et datés. Coût : moyen, ~150 lignes plus les cas du plein écran.

Les deux options sont mises côte à côte, avec leur coût, dans la section « À trancher » du backlog M8. **Aucune n'est tranchée ici** : le choix se fait après la maquette.

### Le reste

- **Fonds d'îlots** : les vues de contenu prennent leur `surface` et un `clipShape(RoundedRectangle(cornerRadius: islandRadius))` ; c'est le conteneur de zone (`ZonesViewController`) qui pose la gouttière via l'épaisseur et la couleur des diviseurs de `NSSplitView` (`dividerStyle`, `NSSplitView.drawDivider(in:)` dans une sous-classe si la couleur ne suffit pas).
- **Contraste** : le calcul WCAG (luminance relative, ratio) est une fonction pure d'une quinzaine de lignes, testée sur les paires connues ; aucune librairie.
- **Tests** : décodage de la section `theme` (absente, partielle, clé inconnue, couleur mal formée, métrique hors bornes), parsing `#rgb`/`#rrggbb`, ratio de contraste de chaque paire imposée par R7 sur le jeu `dark`, cohérence du jeu de tokens (chaque token défini dans les deux jeux). Le rendu, lui, **se valide à l'œil** : chaque tâche du backlog dit quoi regarder.

## Décisions

Voir [decisions.md](decisions.md).
