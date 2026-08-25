# layout — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Les panneaux left/right/bottom encadrent l'arbre de splits entier | Panneaux par split | Modèle IDE classique, un seul état `[side: id?]`, prévisible |
| 2026-08-25 | Raccourcis iTerm-like : `cmd+w`/`cmd+1..9` onglets, `cmd+d`/`cmd+shift+d` splits, `cmd+alt+flèches` focus groupe (`cmd+t` retiré le 2026-08-26 : plus d'onglet par défaut) | Jeu VS Code (`cmd+\`, `cmd+N` = groupe) | Habitudes de l'auteur ; iTerm est la référence |
| 2026-08-26 | Pas de type d'onglet par défaut : split et dernier onglet fermé donnent un groupe vide avec écran d'accueil (style IntelliJ), alimenté par les plugins | `cmd+t` = nouveau shell ; groupe vide gris ; `cmd+t` = quick open | `product` : pas de shell libre ; l'accueil rappelle les raccourcis et donne accès aux agents |
| 2026-08-25 | Déplacement d'onglet entre groupes au clavier seulement (`cmd+alt+shift+flèches`) | Drag & drop en v1 ; aucun déplacement | Couvre le besoin réel ; le D&D SwiftUI inter-groupes coûte cher à faire bien — reporté |
| 2026-08-25 | Pas de zoom/maximisation de groupe en v1 | `cmd+shift+return` maximise le groupe actif | Non demandé ; masquer les panneaux suffit |
| 2026-08-25 | Seuls les panneaux se redimensionnent (souris) ; les splits sont à parts égales fixes | Splits redimensionnables ; resize clavier | Simplicité : pas de ratios à persister ni de poignées dans l'arbre |
| 2026-08-25 | Arbre binaire `split/group`, opérations pures testées sans UI | Grille N enfants par split | Un arbre binaire exprime tous les agencements ; replier un split = remplacer par le frère |
| 2026-08-25 | Tailles de panneaux persistées **par slot**, pas par panneau | Taille par panneau | Un slot a une seule largeur visible ; remplacer un panneau ne doit pas faire sauter le layout |
| 2026-08-25 | Payload d'onglet opaque (chaîne JSON) sérialisé/restauré par le plugin propriétaire | Le layout connaît les types d'onglets | `coding-rules` P1/R5.6 : le noyau ignore les domaines |
| 2026-08-25 | Un conflit de raccourci désactive les deux actions et affiche une erreur ; un plugin ne peut pas écraser un raccourci du layout | Premier arrivé gagne ; dernier gagne | Un conflit silencieux est pire qu'un raccourci absent ; l'utilisateur tranche dans `config.json` |
| 2026-08-25 | Un terminal focalisé reçoit toutes les touches sauf les raccourcis `cmd+…` | Raccourcis `ctrl`/`alt` globaux | `ctrl`/`alt` appartiennent aux programmes du terminal (vim, tmux, readline) |
| 2026-08-26 | Barre d'outils native (`NSToolbar`) possédée par le layout ; les plugins déclarent des `ToolbarItemDescriptor` (`leading`/`trailing`, action ou menu, badge) ; masquable `cmd+alt+t` | Barre custom SwiftUI ; boutons dans les panneaux ; pas de toolbar | `product` R11 : agents et Run méritent un clic ; le natif donne le style macOS gratuitement |
| 2026-08-25 | Fenêtre trop petite : les panneaux se rétrécissent puis se masquent (`right`, `left`, `bottom`) et reviennent seuls ; la taille persistée n'est pas touchée | Refuser la réduction de fenêtre ; écraser les tailles | La zone centrale prime (`product` R5) sans perdre les préférences |
