# Raccourcis

> Table unique des raccourcis par défaut, toutes features confondues, et leur état d'implémentation. La règle source est dans la spec citée ; la tâche qui livre un raccourci met à jour sa ligne. Notation `config` (`cmd`, `shift`, `opt` = Option ⌥, `ctrl`, `+` ; `alt` accepté en alias). Tout raccourci est surchargeable via `config.shortcuts["<id>"]` (`config` R4).

Portée : `global`, `tab(kind)` (onglet de ce kind actif, `layout` R22b), `panel` (composant du panneau focalisé, hors registre : géré par la vue native), `menu` (menu SwiftUI de l'app). Statut : 🟢 implémenté · ⚪ à faire.

## Layout (`layout` R23)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+w` | `layout.tab.close` | Fermer l'onglet actif | global | 🟢 |
| `cmd+1` … `cmd+9` | `layout.tab.N` | Onglet N (9 = dernier) | global | 🟢 |
| `cmd+shift+[` / `cmd+shift+]` | `layout.tab.previous` / `.next` | Onglet précédent / suivant | global | 🟢 |
| `cmd+d` / `cmd+shift+d` | `layout.split.vertical` / `.horizontal` | Split à droite / en bas | global | 🟢 |
| `cmd+opt+←→↑↓` | `layout.focus.*` | Focus sur le groupe voisin | global | 🟢 |
| `cmd+opt+shift+←→↑↓` | `layout.move.*` | Déplacer l'onglet actif vers le groupe voisin | global | 🟢 |
| `escape` | `layout.focus.center` | Rendre le focus au centre | global | 🟢 |
| `cmd+shift+n` | `layout.window.new` | Nouvelle fenêtre (ouvrir un dossier) | global | 🟢 |
| `cmd+opt+t` | `layout.toolbar.toggle` | Masquer / afficher la barre d'outils | global | 🟢 |
| `cmd+o` | — | *File ▸ Open…* | menu | 🟢 |

## Explorer (`explorer` R21)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+shift+e` | `explorer.tree` | Afficher / masquer l'arbre | global | 🟢 |
| `↑↓` `←` `→` | — | Naviguer, replier, déplier | panel | 🟢 (natif `NSOutlineView`) |
| `space` | — | Ouvrir en aperçu | panel | 🟢 |
| `cmd+↓` | — | Ouvrir fixe | panel | 🟢 |
| `enter` | — | Renommer | panel | ⚪ (1.15) |
| `cmd+delete` | — | Supprimer (corbeille) | panel | ⚪ (1.15) |

## Editor (`editor` R6–R8, R14, R17, R23)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+p` | `editor.quickOpen` | Quick open | global | ⚪ (1.13) |
| `cmd+shift+f` | `editor.search` | Recherche dans le contenu (panneau bas) | global | ⚪ (1.14) |
| `cmd+s` / `cmd+opt+s` | `editor.save` / `.saveAll` | Sauver / tout sauver | tab(editor.file) | 🟢 |
| `cmd+z` / `cmd+shift+z` | — | Undo / redo | tab(editor.file) | 🟢 (natif `NSTextView`, menu Edit) |
| `cmd+]` / `cmd+[` | `editor.indent` / `.outdent` | Indenter / désindenter | tab(editor.file) | 🟢 |
| `cmd+/` | `editor.comment` | Commenter / décommenter | tab(editor.file) | 🟢 |
| `opt+↑` / `opt+↓` | `editor.moveLine.*` | Déplacer la ligne | tab(editor.file) | 🟢 |
| `cmd+l` | `editor.goToLine` | Aller à la ligne | tab(editor.file) | 🟢 |
| `cmd+k` | `editor.keepOpen` | Fixer l'onglet aperçu (pas de chord, décision 2026-08-26) | tab(editor.file) | 🟢 |
| `cmd+f` / `cmd+opt+f` | `editor.find` / `.replace` | Chercher / remplacer dans le fichier (`NSTextFinder`) ; `escape` (`editor.escape`) ferme la barre | tab(editor.file) | 🟢 |
| `cmd+shift+v` | `editor.togglePreview` | Source / preview markdown | tab(editor.file) | ⚪ (1.12) |
| `enter` / `cmd+enter` / `escape` | — | Palette : ouvrir / nouveau groupe / fermer | panel | ⚪ (1.13) |

## Agents (`agents` R9)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| *(aucun défaut)* | `agents.<id>` | Ouvrir / activer l'onglet de l'agent | global | ⚪ (M2) |

## Run (`run` R5, R6, R9)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+r` | `run.palette` | Palette des commandes | global | ⚪ (M3) |
| `enter` / `cmd+enter` / `opt+enter` / `escape` | — | Palette : lancer / nouvel onglet / copier / fermer | panel | ⚪ (M3) |
| `cmd+.` | `run.stop` | Arrêter le process | tab(run) | ⚪ (M3) |

## Git (`git`)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+shift+g` | `git.changes` | Panneau changes | global | ⚪ (M4) |
| `cmd+shift+h` | `git.history` | Panneau historique | global | ⚪ (M4) |
| `cmd+enter` | — | Commit (champ de message) | panel | ⚪ (M4) |

## Postgres (`postgres`)

| Raccourci | Id | Action | Portée | Statut |
|---|---|---|---|---|
| `cmd+shift+d` | `postgres.schema` | Panneau schéma — **conflit avec `layout.split.horizontal`** (`layout` R24 : sera délié avec erreur), voir `postgres/questions.md` | global | ⚪ (M5) |
| `cmd+shift+q` | `postgres.query` | Panneau requête | global | ⚪ (M5) |
| `cmd+enter` / `cmd+.` | — | Exécuter / annuler | panel | ⚪ (M5) |
| `cmd+c` | — | Copier la sélection de la grille (TSV) | panel | ⚪ (M5) |

## Libres

`cmd+t` (pas de shell, `product` R4), `cmd+n`, `cmd+shift+1…9`, `cmd+e`, `cmd+g`, `cmd+shift+o`.

## Points ouverts

- Plusieurs défauts entrent en conflit avec des raccourcis système macOS de l'auteur (relevé 2026-08-26, liste à établir) ; à traiter en M6 (polish) — en attendant, surcharge par `config.shortcuts`.
