# design — Prompt de maquette (Nano Banana / Gemini image)

> Prompt **autonome** : il se suffit à lui-même, il n'a besoin ni de cette spec ni du dépôt. À coller tel quel dans Nano Banana (Gemini image). L'image produite est à déposer ici sous le nom `mockup.png` et à citer dans la tâche 8.1 de [`../../backlog/m8-design.md`](../../backlog/m8-design.md).
>
> `mockup.png` **n'existe pas encore** : l'environnement dans lequel cette spec a été écrite ne disposait d'aucun outil de génération d'images. Seul le prompt est livré.

---

Génère une **capture d'écran d'interface, plate et nette**, d'une application de développement pour macOS nommée **Wraith**. Format **1600 × 1000 pixels**, ratio 16:10, rendu net au pixel, sans perspective, sans reflet, sans photo de bureau derrière, sans mockup de MacBook : l'image est la fenêtre elle-même, remplissant tout le cadre.

## Style visuel

Thème **sombre**, inspiré du style « Islands » de l'IDE IntelliJ IDEA en thème Dark. Règles impératives :

- Fond de fenêtre : **aplat sombre uni**, gris-bleuté très foncé (autour de `#1B1D21`). Aucun dégradé, aucune texture, aucun bruit.
- Les zones de travail sont des **îlots** : des rectangles à **coins arrondis** (rayon d'environ 8 px) posés sur ce fond, dans une teinte légèrement plus claire (autour de `#242628`). Entre deux îlots, et entre un îlot et le bord de la fenêtre, une **gouttière régulière de 8 px** laisse voir le fond. **Aucun trait de séparation** entre les îlots : c'est l'espace qui sépare.
- **Aucune transparence, aucun flou, aucun effet de verre, aucun matériau translucide.** Toutes les surfaces sont opaques.
- Barres plates : pas d'ombre, pas de dégradé, pas de relief, pas de bouton en pilule.
- **Une seule couleur d'accent** dans toute l'image : un bleu franc et sobre (autour de `#4C8DF6`). Elle sert uniquement à marquer le focus et la sélection. Le reste de l'interface est en gris.
- Texte : sans-serif système pour l'interface, **police à chasse fixe** pour le code et le terminal. Texte principal gris clair (`#D8DADD`), texte secondaire gris moyen (`#8A8F98`).
- Petites pastilles d'état colorées seulement là où c'est indiqué : vert, orange, rouge, bleu, en points de 6 px.

## Disposition exacte

De haut en bas, la fenêtre contient quatre bandes :

**1. Barre de titre et barre d'outils** (une seule bande fine, environ 44 px de haut, fond opaque, pas de titre textuel)

- À l'extrême gauche : les trois **boutons macOS** rouge, jaune, vert, à leur place habituelle.
- Ensuite, à gauche : quatre **boutons d'agent**, plats, sans bordure, espacés régulièrement, chacun une petite icône monochrome avec son nom sous forme d'info-bulle absente — juste les icônes : `Claude`, `OpenCode`, `Pi`, `Antigravity`. Le premier bouton porte un **point vert** en bas à droite de son icône (l'agent tourne).
- À droite de la barre : un bouton **`▶ Run`** — un triangle « lecture » suivi du mot *Run*, plat, discret, avec un petit chevron de menu et un **point bleu** en coin (une commande tourne).
- Rien d'autre dans cette barre : ni champ de recherche, ni titre, ni onglets.

**2. Corps de la fenêtre**, occupant tout le reste sauf la bande du bas. Il est fait de trois îlots côte à côte :

- **Îlot gauche — Explorer**, largeur environ 260 px. En haut, une barre fine avec le mot **Explorer** en gris et deux petites icônes à droite. En dessous, une **arborescence de fichiers** sur fond d'îlot : dossiers `backend`, `frontend`, `docs`, `.github`, quelques fichiers `README.md`, `package.json`, `Dockerfile`, `UserController.java`. Deux dossiers sont dépliés avec leurs enfants indentés, avec des chevrons de dépliage. Un fichier est **sélectionné** : sa ligne entière porte le bleu d'accent en fond, texte clair par-dessus. Deux entrées (`node_modules`, `target`) sont en gris nettement plus sombre que les autres (elles sont ignorées).
- **Îlot central — Éditeur**, le plus large. En haut, une **barre d'onglets plate** : quatre onglets rectangulaires, sans coins arrondis, sans forme d'onglet — `UserController.java`, `README.md`, `Claude`, `backend:test`. L'onglet actif (`UserController.java`) a le fond de l'îlot et un **liseré bleu de 2 px sur son bord supérieur** ; les autres sont sur le fond de barre, texte gris. L'onglet `README.md` porte un petit point après son nom (non sauvegardé) ; l'onglet `Claude` porte une **pastille verte** ; l'onglet `backend:test` porte une **pastille bleue**. Sous la barre, un trait de séparation très fin, puis du **code Java coloré** en police à chasse fixe : une **gouttière de numéros de ligne** en gris sombre à gauche, une trentaine de lignes de code d'une classe `UserController` avec annotations, méthodes, chaînes de caractères et commentaires colorés sobrement (violet pour les mots-clés, orange pour les nombres, vert-gris pour les commentaires, rouge doux pour les chaînes), un curseur de texte fin, et une ligne surlignée d'un gris à peine plus clair.
- **Îlot droit — Panneau**, largeur environ 300 px. En haut, une barre fine avec le mot **Schema**. En dessous, un arbre de base de données : `public` déplié, puis `Tables` déplié, puis `users`, `orders`, `products`, `invoices`, chacun avec une petite icône de table ; `users` est déplié et montre quatre colonnes avec leur type à droite en gris (`id  bigint`, `email  varchar(255)`, `created_at  timestamptz`, `is_active  boolean`).

**3. Îlot bas — Terminal**, sur toute la largeur sous les trois îlots précédents, hauteur environ 240 px, séparé d'eux par la même gouttière de 8 px.

- En haut, une barre fine avec deux onglets plats : `Claude` (actif, liseré bleu, pastille verte) et `backend:test` (pastille bleue).
- En dessous, un **contenu de terminal en police à chasse fixe** sur le **même fond exactement** que l'îlot qui le contient — aucun rectangle plus sombre ou plus clair à l'intérieur du bloc. Le contenu montre une session d'agent en cours : quelques lignes de sortie, un encadré ASCII simple, une ligne de progression, et un curseur bloc clignotant en bas. Couleurs de terminal sobres, dans la même famille que le reste.

**4. Palette de commandes, ouverte, flottant par-dessus le tout**

- Un panneau **centré horizontalement**, ancré à environ 60 px sous la barre d'outils, largeur environ 620 px, hauteur environ 380 px.
- Coins arrondis (même rayon de 8 px), fond d'îlot **opaque**, et **une ombre portée douce** — c'est le seul élément de l'image qui porte une ombre.
- En haut, un **champ de saisie** sur un fond légèrement plus sombre que le panneau, contenant le texte `usrctrl` avec un curseur.
- En dessous, une **liste de résultats** : six lignes. Chaque ligne a un titre en texte clair et un chemin en gris plus petit à droite ou en dessous — `UserController.java` / `backend/src/main/java/…`, `UserControllerTest.java`, `UserService.java`, `user-controller.ts`, `users.sql`, `UserRepository.java`. Dans les titres, les lettres qui correspondent à la saisie (`u`, `s`, `r`, `c`, `t`, `r`, `l`) sont en **gras plus clair**, le reste normal.
- La **première ligne est sélectionnée** : fond bleu d'accent atténué, coins légèrement arrondis, texte clair par-dessus.
- En bas du panneau, une ligne d'aide très discrète en gris : `↑↓ naviguer · ⏎ ouvrir · ⌘⏎ nouveau groupe · esc fermer`.

## À ne pas faire

- Pas de barre de menus macOS en haut de l'image (la fenêtre seule).
- Pas de barre latérale d'icônes verticale à la VS Code.
- Pas de barre d'état en bas de la fenêtre.
- Pas de logo, pas de mascotte, pas de fantôme, pas d'illustration.
- Pas de texte factice illisible : le code, les noms de fichiers et les lignes de terminal doivent être des mots plausibles et lisibles.
- Pas de couleurs vives autres que l'accent bleu et les quatre pastilles d'état.
- Pas de translucidité, pas de flou d'arrière-plan, pas de dégradé, pas de reflet, pas de coin arrondi sur les onglets.
