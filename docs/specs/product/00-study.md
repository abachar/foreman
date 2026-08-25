# product — Étude

## Objectif

Wraith est un environnement de développement macOS natif et **agentic** : une fenêtre = un dossier = un workspace (modèle IDE). Le cœur, ce sont les agents CLI (Claude Code, Antigravity, OpenCode…), chacun dans son onglet sur une surface terminal (SwiftTerm), lancés d'un clic depuis la barre d'outils ([agents](../agents/)). **Il n'y a pas de shell libre** : une surface terminal n'existe que pour héberger un agent ou une commande `run` — pas d'onglet pour taper `cd`, `ls`… Le reste (explorer, éditeur, git, Postgres, run) sont des features qui attachent des panneaux autour (`architecture`).

## Utilisateur cible

- Un seul utilisateur : l'auteur. Pas de publication, pas d'onboarding, pas de compatibilité ascendante à garantir en v1.
- Conséquence : on optimise pour la vitesse d'itération et le confort personnel, pas pour la généralité.

## User stories

- US1 — En tant qu'utilisateur, j'ouvre un dossier (`wraith .` ou via l'app) et j'obtiens une fenêtre-workspace dédiée à ce dossier.
- US2 — Je peux ouvrir plusieurs workspaces en parallèle, chacun dans sa propre fenêtre, sans interférence.
- US3 — Dans la zone centrale, je travaille avec des onglets (agents, fichiers, diffs, runs…) et je peux splitter horizontalement ou verticalement ; chaque split a sa propre barre d'onglets.
- US4 — Je peux afficher/masquer des panneaux latéraux et bas au clavier, sans jamais perdre la zone centrale.
- US5 — Quand je rouvre un workspace, je retrouve mes onglets, splits et panneaux tels que je les avais laissés.
- US6 — D'un clic dans la barre d'outils, je lance (ou retrouve) mon agent CLI dans son onglet, et je lance les commandes de mon projet.

## Règles fonctionnelles

- R1 — Une fenêtre correspond à exactement un dossier racine (le workspace). Ouvrir un dossier déjà ouvert active la fenêtre existante au lieu d'en créer une nouvelle.
- R2 — Plusieurs fenêtres/workspaces peuvent coexister ; l'état (onglets, panneaux, config) est isolé par workspace.
- R3 — La zone centrale est un arbre de splits (H/V) dont les feuilles sont des **groupes d'onglets**. Le groupe d'onglets est un composant unique, réutilisé pour chaque feuille.
- R4 — Chaque groupe d'onglets accepte tous les types d'onglets (agent, run, éditeur, diff…). Il n'y a **pas de type par défaut** ni d'onglet shell libre : un groupe sans onglet affiche l'**écran d'accueil** (`layout` R33).
- R5 — La zone centrale reste toujours visible ; les panneaux left/right/bottom s'ajoutent autour, un seul panneau visible par slot (détail dans [layout](../layout/)).
- R6 — L'état du workspace est persisté à la fermeture et restauré à l'ouverture : arbre de splits, onglets (type + cwd/fichier), onglet actif par groupe, panneaux visibles, tailles des zones.
- R7 — Les onglets agent/run restaurés sont **recréés** (nouvelle surface dans le même cwd, commande non relancée, `agents` R8 / `run` R13) ; le contenu du scrollback n'est pas restauré en v1.
- R8 — Lancer Wraith sans dossier ouvre un workspace sur `$HOME`, comme un shell. Il n'existe pas de fenêtre sans dossier.
- R9 — Chaque workspace possède un dossier `.wraith/` à sa racine pour la config locale et l'état persisté (détail dans [config](../config/)).
- R10 — Exécution locale uniquement : pas de signature, notarisation, Homebrew, auto-update ni télémétrie en v1.
- R11 — Chaque fenêtre a une **barre d'outils** native au-dessus des zones : à gauche les boutons des agents ([agents](../agents/)), à droite le bouton Run ([run](../run/)). Les features y déclarent leurs éléments ; le layout la possède (détail dans [layout](../layout/)).

## Cas limites

- Dossier supprimé/déplacé entre deux ouvertures : la fenêtre s'ouvre sur une erreur claire, l'état persisté est conservé (pas effacé).
- Fichier d'un onglet éditeur disparu à la restauration : l'onglet est ignoré (ou ouvert vide en lecture seule — à trancher dans editor).
- Fermeture du dernier groupe d'onglets d'un split : le split se replie ; il reste toujours au moins un groupe dans la zone centrale.

## Hors périmètre v1

- Distribution (DMG signé, Homebrew tap, App Store) — cf. M6 du README, reporté.
- Multi-utilisateurs, synchronisation d'état entre machines.
- Fenêtre détachée / onglets flottants.
- Restauration du scrollback des terminaux.
- Extensions tierces ou chargées à l'exécution : les features sont compilées dans l'app (`architecture`).

## Décisions

Voir [decisions.md](decisions.md).
