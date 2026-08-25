# postgres — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-26 | **Une seule connexion par workspace** (`config.postgres` = un objet), pas de sélecteur (remplace « profils nommés » du 2026-08-25) | Profils nommés avec sélecteur | Vision produit : un workspace = une base ; moins d'UI, une seule clé Keychain ; changer de base = éditer la config |
| 2026-08-25 | Mot de passe : Keychain → `~/.pgpass` (0600) → saisie avec enregistrement Keychain | Saisie à chaque fois ; `password` en config | `config` R11 ; `.pgpass` est la convention existante de l'utilisateur |
| 2026-08-25 | Schéma complet par niveau depuis `pg_catalog` (schémas, tables, vues, mat views, fonctions, séquences, types ; colonnes, index, contraintes, FK) | Tables/colonnes seulement ; `information_schema` | Le besoin réel est d'explorer une base inconnue ; `pg_catalog` est rapide et complet |
| 2026-08-25 | Grille lecture seule, autocommit, session `default_transaction_read_only = on` avec toggle d'écriture non persisté | Édition dans la grille ; transactions UI | Outil d'exploration ; l'écriture accidentelle est le vrai risque, l'écriture voulue reste possible |
| 2026-08-25 | Pages de 500 lignes par portal, plafond 50 000 en mémoire, `statement_timeout` 30 s, annulation `cmd+.` | Tout charger ; `LIMIT` injecté dans le SQL de l'utilisateur | `coding-rules` §12.4 (bornée) sans réécrire le SQL de l'utilisateur ; à prototyper |
| 2026-08-25 | Export CSV/JSON du résultat chargé ou re-streamé (plafond 1 M lignes) | Pas d'export | Besoin fréquent, coût faible |
| 2026-08-25 | Historique des requêtes dans `.wraith/postgres-history.json` (500, FIFO, épinglage), jamais versionné | Pas d'historique ; dans `state.json` | Fichier dédié pour ne pas gonfler `state.json` ; règle `.gitignore` alignée |
| 2026-08-26 | Éditeur SQL = zone de texte monospace propre au plugin, colorée via `HighlightService` du noyau (remplace « sans highlighting » du 2026-08-25) | Réutiliser l'onglet éditeur de `editor` | Un plugin n'importe pas un autre plugin (`coding-rules` R4.1) ; le highlighting est une capacité du noyau (R5.10) |
| 2026-08-25 | Exécution : sélection, sinon instruction sous le curseur ; `cmd+shift+enter` = tout | Toujours tout le buffer | Habitudes DataGrip/psql ; évite de rejouer 10 requêtes |
