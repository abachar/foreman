# postgres — Étude

## Objectif

Feature `postgres` (dossier `Postgres/`) : explorer le schéma d'une base et exécuter des requêtes en lecture, sans quitter le workspace. Panneau droit `postgres.schema` (`cmd+shift+d`), panneau bas `postgres.query` (éditeur SQL + grille de résultats, `cmd+shift+q`). Client : PostgresNIO, connexion paresseuse, secrets dans le Keychain.

## User stories

- US1 — `cmd+shift+d` : je saisis le mot de passe une seule fois, je vois les schémas et leurs tables de la base du workspace.
- US2 — Je déplie une table : colonnes (type, null, défaut), index, contraintes, clés étrangères.
- US3 — `cmd+shift+q`, j'écris une requête, `cmd+enter` : les 500 premières lignes en grille, temps d'exécution, nombre de lignes.
- US4 — Je sélectionne deux lignes de SQL sur cinq : seule la sélection s'exécute ; sans sélection, tout le buffer part.
- US5 — J'exporte le résultat en CSV ou JSON.
- US6 — Je retrouve mes dernières requêtes dans l'historique.
- US7 — Double clic sur une table : `SELECT * FROM schema.table LIMIT 500` s'exécute.

## Règles fonctionnelles

### Connexion

- R1 — Config (`config` R3, section `postgres`) : **un seul objet** = une connexion par workspace ; champs `host` (défaut `localhost`), `port` (5432), `database`, `user`, `sslmode` (`disable` | `prefer` | `require`, défaut `prefer`), `options` (`[String: String]`, ex. `application_name`). Jamais `password` (`config` R11). Précédence globale < workspace (`config` R4) : l'objet du workspace remplace celui de la config globale champ par champ.
- R2 — Pas de sélecteur : l'en-tête des deux panneaux affiche `user@host/database` et l'état (R5). Aucune section `postgres` configurée → panneau avec message et exemple de config. Changer de base = modifier `config.json` (rechargé à chaud, `config` R6 : la connexion précédente est fermée).
- R3 — Mot de passe : cherché dans le Keychain (`config` R3), sinon dans `~/.pgpass` (format et permissions standard, seulement si le fichier est `0600`), sinon demandé (feuille de saisie, option *Enregistrer dans le Keychain* cochée par défaut). Une authentification refusée invalide l'entrée Keychain et redemande. Le mot de passe n'est retenu en mémoire que le temps de la connexion.
- R4 — Connexion **paresseuse** : établie à la première action qui en a besoin (dépliage du schéma, exécution), pas à l'activation du panneau. Une seule connexion par fenêtre ; fermée à la désactivation des **deux** panneaux ou après 10 min d'inactivité ; rouverte à la demande. Timeout de connexion 10 s.
- R5 — État de connexion visible (pastille : déconnecté / connexion / connecté / erreur) ; erreur affichée en bannière avec le message serveur (`PostgresError` de la feature, enveloppant l'erreur NIO).

### Schéma

- R6 — Arbre : schémas (hors `pg_catalog`, `information_schema`, `pg_toast*` ; toggle « schémas système ») → **Tables**, **Vues**, **Vues matérialisées**, **Fonctions**, **Séquences**, **Types** (enums) → objets → pour une table : **Colonnes** (nom, type formaté, `NOT NULL`, défaut, PK), **Index** (nom, définition), **Contraintes** (PK, UNIQUE, CHECK, FK avec cible), **Clés étrangères entrantes**. Une vue affiche ses colonnes et sa définition.
- R7 — Chargement **par niveau** à l'expansion (paresse, `architecture.md`), via requêtes sur `pg_catalog` (pas `information_schema`, trop lent), une requête par niveau, bornée (timeout 10 s). Aucun rafraîchissement automatique : bouton *Rafraîchir* (par nœud ou global).
- R8 — Actions sur un objet : *Copier le nom qualifié*, *SELECT * LIMIT 500* (double clic ou menu, exécuté dans le panneau query), *Insérer le nom dans l'éditeur*, *Voir la DDL* (reconstruite côté client pour tables/vues/fonctions/index — best effort, lecture seule). Recherche/filtre textuel sur les noms chargés.

### Éditeur SQL et exécution

- R9 — Le panneau `postgres.query` est divisé verticalement : éditeur SQL en haut (redimensionnable), résultats en bas. L'éditeur est une zone de texte monospace propre à la feature, colorée via le dossier partagé `Highlight/` (grammaire `sql`), avec undo, indentation, `cmd+/` commentaire `--`. Son contenu est persisté dans `state.json`.
- R10 — Exécution (`cmd+enter`, portée panneau) : la **sélection** si elle existe, sinon **tout le buffer**, envoyé tel quel en une seule `simpleQuery` : Postgres découpe les instructions lui-même, les exécute dans l'ordre et s'arrête à la première erreur (aucun split côté client). Pas de « instruction sous le curseur » (voir décisions).
- R11 — **Autocommit**, session en lecture seule par défaut : la connexion exécute `SET default_transaction_read_only = on` ; un toggle *Autoriser l'écriture* (par session, non persisté, pastille rouge) la lève. Une erreur `read-only transaction` est expliquée par une bannière pointant le toggle.
- R12 — Toute requête est bornée : `statement_timeout` 30 s (réglable dans la config globale `postgres.statementTimeout`). Le SQL **généré par Wraith** (R8) porte un `LIMIT 500`. Le SQL **libre** est lu en **streaming** (lignes consommées au fil de l'eau, jamais tout en mémoire) et s'arrête à **50 000 lignes** : la requête est alors annulée (`Task.cancel`) et la grille affiche un avertissement « résultat tronqué à 50 000 lignes, ajoutez un `LIMIT` ». La grille affiche les lignes par pages de 500 à mesure qu'elles arrivent. Pas de curseur/portal.
- R13 — Annulation : bouton *Stop* / `cmd+.` annule la tâche (`Task.cancel`, PostgresNIO envoie la requête cancel du protocole), puis ferme la connexion si le serveur ne répond pas en 5 s.
- R14 — Une seule exécution à la fois par fenêtre ; `cmd+enter` pendant une exécution est refusé (bip) et non mis en file.
- R15 — Paramètres : pas de paramètres liés dans l'éditeur libre (c'est du SQL tel quel, comme `psql`). En revanche, tout SQL **généré par Wraith** (R8, R7, R12) échappe les identifiants (`quote_ident` côté client) et lie ses valeurs (sécurité, `architecture.md`).

### Résultats

- R16 — Grille lecture seule : en-têtes (nom, type PG), tri **client** par colonne sur la page chargée, largeur de colonne ajustable, sélection de cellules/lignes, `cmd+c` copie en TSV (cellule, lignes, ou tout). Valeurs : `NULL` distingué visuellement, `bytea` en hex tronqué, `json/jsonb` pretty-print sur double clic (popover), dates ISO 8601, tableaux `{…}` texte.
- R17 — Barre d'état : `N lignes (page 1/…) · 42 ms · user@base`. Une instruction sans résultat (`UPDATE`, `CREATE`) affiche `OK · 3 lignes affectées`. Plusieurs instructions dans le buffer (R10) → un onglet de résultat par instruction retournée par le serveur, le dernier actif.
- R18 — Export : *CSV* (RFC 4180, en-têtes, `NULL` vide) et *JSON* (tableau d'objets, types natifs quand possible) du résultat **chargé** ou, sur option, de la requête entière re-exécutée en streaming vers le fichier (plafond 1 000 000 lignes). Destination via `NSSavePanel`.
- R19 — Erreur d'exécution : bannière avec message, `SQLSTATE`, et position → curseur placé sur l'erreur dans l'éditeur.

### Historique

- R20 — Chaque requête exécutée (texte, `user@host/database`, date, durée, nombre de lignes / erreur) est ajoutée à `.wraith/postgres-history.json` (max 500 entrées, FIFO, jamais versionné : recommandé dans `.gitignore` avec `state.json`). Panneau d'historique (bouton ou `cmd+opt+h` en portée panneau) : recherche, clic → recharge dans l'éditeur, *Épingler* (conservée hors FIFO). Rien du résultat n'est persisté.

## Cas limites

- Serveur injoignable : erreur en < 10 s, pas de retry automatique ; le schéma déjà chargé reste affiché (grisé).
- Connexion coupée en cours de requête : erreur, reconnexion à la prochaine action.
- Base avec des milliers de tables : chargement par niveau + filtre ; un niveau > 5 000 objets est tronqué avec bouton.
- Colonne très large (texte de 1 Mo) : cellule tronquée à 1 000 caractères, contenu complet sur double clic.
- Types inconnus/extensions (PostGIS, etc.) : rendus par leur représentation texte.
- `~/.pgpass` avec mauvaises permissions : ignoré avec avertissement (comportement de `libpq`).
- Deux fenêtres, même base : deux connexions distinctes, indépendantes.
- Résultat contenant des `\t`/`\n` : copie TSV les échappe, CSV les quote.

## Hors périmètre v1

- Édition des données dans la grille, génération d'`UPDATE`/`INSERT`.
- Transactions explicites dans l'UI (`BEGIN`/`COMMIT`/`ROLLBACK` restent tapables, mais sans gestion d'état).
- Autocomplétion SQL.
- Diagramme ER, `EXPLAIN` visuel, statistiques, monitoring, gestion des rôles.
- Tunnel SSH, connexion via `DATABASE_URL`, autres SGBD.
- Modification du schéma via l'UI.

## Options techniques

- **Client** : PostgresNIO (SPM, épinglé `.upToNextMinor`) importé dans `Postgres/`, utilisé par un type concret `PostgresClient` (`actor` : `connect`, `query(sql) -> AsyncThrowingStream<QueryEvent>`, `close`). Pas de protocole : une seule implémentation (`architecture.md` P1). Les lignes sont converties en `QueryValue` (`null`, `text`, `int`, `double`, `bool`, `date`, `json`, `bytes`, `raw(String)`) pour la grille et l'export ; `QueryResult { columns: [ColumnInfo], rows: [[QueryValue]] }`.
- **Exécution et bornes** : `simpleQuery` (protocole simple) pour le buffer de l'éditeur — c'est Postgres qui découpe les instructions et renvoie un résultat par instruction ; le SQL généré par Wraith passe par le protocole étendu avec paramètres liés et `LIMIT 500`. Le streaming de lignes de PostgresNIO alimente la grille ; à 50 000 lignes la tâche est annulée (R12). Pas de portal, pas de tokenizer SQL.
- **Annulation** : `Task.cancel` → cancel request du protocole, natif dans PostgresNIO.
- **Secrets** : `SecretStore` (dossier `Workspace/`) avec clé `wraith.postgres.<host>:<port>/<database>/<user>` ; double `InMemorySecretStore` en tests (justifié : le Keychain n'est pas testable hermétiquement).
- **Tests** : formatage des valeurs et export CSV/JSON (R16, R18), fusion globale/workspace de la config (R1), lecture `.pgpass` (R3), FIFO/épinglage de l'historique (R20). La logique des panneaux est testée sur des `QueryResult` construits à la main, sans double de `PostgresClient`.

## Décisions

Voir [decisions.md](decisions.md).
