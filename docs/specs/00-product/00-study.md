# 00-product — Étude

## Objectif

Wraith est un workspace macOS natif, terminal-first : une fenêtre = un dossier = un workspace (modèle IDE). Le terminal (libghostty) est le cœur ; le reste (explorer, git, éditeur, Postgres, run) sont des plugins qui attachent des panneaux autour.

## Utilisateur cible

- Un seul utilisateur : l'auteur. Pas de publication, pas d'onboarding, pas de compatibilité ascendante à garantir en v1.
- Conséquence : on optimise pour la vitesse d'itération et le confort personnel, pas pour la généralité.

## User stories

- US1 — En tant qu'utilisateur, j'ouvre un dossier (`wraith .` ou via l'app) et j'obtiens une fenêtre-workspace dédiée à ce dossier.
- US2 — Je peux ouvrir plusieurs workspaces en parallèle, chacun dans sa propre fenêtre, sans interférence.
- US3 — Dans la zone centrale, je travaille avec des onglets (terminaux, fichiers…) et je peux splitter horizontalement ou verticalement ; chaque split a sa propre barre d'onglets.
- US4 — Je peux afficher/masquer des panneaux latéraux et bas au clavier, sans jamais perdre la zone centrale.
- US5 — Quand je rouvre un workspace, je retrouve mes onglets, splits et panneaux tels que je les avais laissés.

## Règles fonctionnelles

- R1 — Une fenêtre correspond à exactement un dossier racine (le workspace). Ouvrir un dossier déjà ouvert active la fenêtre existante au lieu d'en créer une nouvelle.
- R2 — Plusieurs fenêtres/workspaces peuvent coexister ; l'état (onglets, panneaux, config) est isolé par workspace.
- R3 — La zone centrale est un arbre de splits (H/V) dont les feuilles sont des **groupes d'onglets**. Le groupe d'onglets est un composant unique, réutilisé pour chaque feuille.
- R4 — Chaque groupe d'onglets accepte tous les types d'onglets (terminal, éditeur, vues plugin). Le terminal est le type par défaut.
- R5 — La zone centrale reste toujours visible ; les panneaux left/right/bottom s'ajoutent autour, un seul panneau visible par slot (détail dans [02-layout](../02-layout/)).
- R6 — L'état du workspace est persisté à la fermeture et restauré à l'ouverture : arbre de splits, onglets (type + cwd/fichier), onglet actif par groupe, panneaux visibles, tailles des zones.
- R7 — Les terminaux restaurés sont **recréés** (nouveau shell dans le même cwd) ; le contenu du scrollback n'est pas restauré en v1.
- R8 — Lancer Wraith sans dossier ouvre un workspace sur `$HOME`, comme un shell. Il n'existe pas de fenêtre sans dossier.
- R9 — Chaque workspace possède un dossier `.wraith/` à sa racine pour la config locale et l'état persisté (détail dans [01-config](../01-config/)).
- R10 — Exécution locale uniquement : pas de signature, notarisation, Homebrew, auto-update ni télémétrie en v1.

## Cas limites

- Dossier supprimé/déplacé entre deux ouvertures : la fenêtre s'ouvre sur une erreur claire, l'état persisté est conservé (pas effacé).
- Fichier d'un onglet éditeur disparu à la restauration : l'onglet est ignoré (ou ouvert vide en lecture seule — à trancher dans 05-editor).
- Fermeture du dernier groupe d'onglets d'un split : le split se replie ; il reste toujours au moins un groupe dans la zone centrale.

## Hors périmètre v1

- Distribution (DMG signé, Homebrew tap, App Store) — cf. M6 du README, reporté.
- Multi-utilisateurs, synchronisation d'état entre machines.
- Fenêtre détachée / onglets flottants.
- Restauration du scrollback des terminaux.
- Plugins dynamiques (chargés à l'exécution).

## Décisions

Voir [decisions.md](01-decisions.md).
