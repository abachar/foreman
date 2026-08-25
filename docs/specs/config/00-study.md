# config — Étude

## Objectif

Définir où et comment Wraith lit sa configuration et persiste son état, par workspace et globalement.

## Emplacements

| Portée | Chemin | Contenu |
|---|---|---|
| Workspace | `<root>/.wraith/config.json` | config du workspace (repos, commands, postgres, shortcuts…) |
| Workspace | `<root>/.wraith/state.json` | état d'UI persisté (splits, onglets, panneaux, tailles) |
| Global | `~/.config/wraith/config.json` | préférences utilisateur (thème, police, raccourcis par défaut…) |
| Secrets | Keychain macOS | mots de passe Postgres, jamais dans un fichier |

## User stories

- US1 — J'ouvre un dossier sans aucune config : tout fonctionne avec des valeurs par défaut (repos auto-détectés, pas de commandes, pas de Postgres).
- US2 — Je décris mon workspace dans `.wraith/config.json` (repos, commandes, connexion PG, agents) et les features s'en servent.
- US3 — Je modifie `config.json` pendant que Wraith tourne : la config est rechargée sans redémarrer.
- US4 — Je peux surcharger un raccourci par workspace.
- US5 — Je ferme et rouvre le workspace : je retrouve mon état.

## Règles fonctionnelles

- R1 — `.wraith/` est créé à la demande (première écriture de `state.json`), jamais `config.json` : celui-ci est toujours écrit par l'utilisateur.
- R2 — Absence de `config.json` = config vide ; toutes les clés sont optionnelles.
- R3 — Schéma de `config.json` (v1) :
  ```json
  {
    "repos": ["backend", "frontend"],
    "commands": { "backend": { "build": "mvn compile", "test": "mvn test" } },
    "postgres": { "host": "localhost", "port": 5432, "database": "ccoe", "user": "postgres" },
    "agents": { "claude": { "command": "claude --continue" } },
    "shortcuts": { "git.status": "cmd+shift+g" }
  }
  ```
  - `repos` : chemins relatifs à la racine ; absent → scan des `.git/` (profondeur ≤ 2, ignore `node_modules`, `target`, `.build`).
  - `commands` : `<repo ou "."> → <nom> → <commande shell>`, exécutées dans le dossier du repo.
  - `postgres` : **un seul objet** (une connexion par workspace), sans mot de passe ; le mot de passe est lu dans le Keychain (clé `wraith.postgres.<host>:<port>/<database>/<user>`). Détail dans [postgres](../postgres/).
  - `agents` : `<id> → { title, command, icon, enabled }` ; surcharge un agent intégré ou en déclare un nouveau. Détail dans [agents](../agents/).
  - `commands` : forme courte (chaîne) ou longue (`{ "run", "cwd", "env" }`). Détail dans [run](../run/).
  - `shortcuts` : `<panel/action id> → <raccourci>` ; surcharge les défauts déclarés par les features.
- R4 — Précédence : défauts des features < global `~/.config/wraith/config.json` < workspace `.wraith/config.json`.
- R5 — `Workspace` expose la config aux features ; chaque feature décode sa propre section (`config.section("postgres")`), `Workspace` ne connaît pas les schémas des features (`architecture` : config par section).
- R6 — `config.json` est surveillé (via le flux FSEvents unique) ; à chaque changement valide, `Workspace` publie la nouvelle config sur son flux `configChanges` (`AsyncStream`), auquel les features intéressées s'abonnent.
- R7 — Un `config.json` invalide (JSON malformé, type inattendu) n'empêche pas l'ouverture : la dernière config valide reste active et l'erreur est affichée (ligne + message).
- R8 — `state.json` est écrit par Wraith uniquement, de façon débouncée (~1 s après le dernier changement) et à la fermeture. Il n'est jamais surveillé.
- R9 — `state.json` porte un numéro de version de schéma ; un état illisible ou d'une version inconnue est ignoré (démarrage à l'état par défaut) et sauvegardé en `state.json.bak`.
- R10 — Les chemins dans `state.json` (cwd des terminaux, fichiers ouverts) sont relatifs à la racine du workspace quand ils sont à l'intérieur, absolus sinon.
- R11 — Aucun secret n'est jamais écrit dans `.wraith/` ; toute valeur sensible détectée dans `config.json` (clé `password`) déclenche un avertissement et est ignorée.

## Cas limites

- Racine du workspace en lecture seule : `state.json` n'est pas écrit, l'app fonctionne sans persistance et le signale une fois.
- `$HOME` comme workspace : `~/.wraith/` est créé chez l'utilisateur ; acceptable (c'est le comportement d'un shell avec ses dotfiles).
- `.wraith/` versionné ou non : au choix de l'utilisateur ; recommandation `.gitignore` → `.wraith/state.json` et `.wraith/postgres-history.json` (tout fichier écrit par l'app).
- Repo déclaré dans `repos` mais absent sur disque : ignoré avec avertissement.

## Hors périmètre v1

- Config en YAML/TOML, ou en plusieurs fichiers.
- Éditeur de préférences graphique.
- Migration automatique de schéma entre versions.
