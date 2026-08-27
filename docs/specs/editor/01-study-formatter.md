# editor — Étude : formatage

> Deuxième étude du domaine `editor` ([00-study.md](00-study.md)). Elle **continue la numérotation** des règles : `R1`–`R23` sont dans la première étude, celle-ci commence à `R24`. Les décisions et les questions restent dans [`decisions.md`](decisions.md) et [`questions.md`](questions.md), communs au domaine.

## Objectif

Formater le fichier de l'onglet actif avec le formateur que l'utilisateur emploie déjà pour ce projet, sans quitter Wraith et sans que Wraith ait d'opinion sur le style. Deux déclencheurs : une action explicite (`cmd+shift+l`) et, en option, la sauvegarde (`formatter.onSave`). C'est une extension de l'éditeur, **pas un nouveau domaine** : pas de dossier `Formatter/`, pas de nouvelle feature, pas de nouveau panneau.

Cette étude lève la ligne « formatage » du hors-périmètre v1 de [00-study.md](00-study.md) ; tout le reste de cette ligne (LSP, complétion, diagnostics, go-to-definition) y reste.

## User stories

- US7 — J'ouvre un `.ts`, je tape, `cmd+shift+l` : le fichier est reformaté par le `prettier` du projet, mon curseur est resté sur la ligne où j'étais, `cmd+z` annule tout le formatage d'un coup.
- US8 — Je mets `"formatter": { "onSave": true, "java": "…" }` dans `.wraith/config.json` : `cmd+s` formate puis sauve.
- US9 — Le formateur n'est pas installé, ou refuse mon fichier parce qu'il ne compile pas : je vois sa sortie d'erreur, mon texte n'a pas bougé, et ma sauvegarde a quand même eu lieu.
- US10 — J'ouvre un fichier dont l'extension n'a pas de formateur déclaré : `cmd+shift+l` me le dit une fois et ne fait rien.

## Règles fonctionnelles

### Déclenchement

- R24 — Deux points d'entrée, et deux seulement : l'action `editor.format` (défaut `cmd+shift+l`, portée `tab(editor.file)` comme les autres actions de l'éditeur, R23) sur l'onglet actif ; et la sauvegarde quand `formatter.onSave` vaut `true`. Pas de formatage à la frappe, au collage, ni sur une sélection (hors périmètre).
- R25 — Le formateur est choisi par **extension du fichier**, dans la section `formatter` de `.wraith/config.json` (`config` R3, R5) :
  ```json
  {
    "formatter": {
      "onSave": false,
      "swift": "swift format --configuration .swift-format",
      "ts": "npx --no-install prettier --stdin-filepath file.ts",
      "py": "black -q -",
      "rs": "rustfmt --emit stdout",
      "go": "gofmt",
      "java": "clang-format --assume-filename=file.java"
    }
  }
  ```
  Une extension sans entrée n'a pas de formateur : l'action affiche une fois « no formatter for `.<ext>` in .wraith/config.json » et ne fait rien ; la sauvegarde n'est ni bloquée ni retardée. `onSave` est la seule clé réservée de la section ; elle n'est jamais lue comme une extension.
- R26 — La commande est **du texte de l'utilisateur**, lancée telle quelle par `$SHELL -l -c "<commande>"` avec l'environnement du login shell (`terminal` R3, `Workspace.loginEnvironment()`) et `cwd` = dossier du fichier. Aucune interpolation : Wraith n'injecte ni le chemin, ni le contenu, ni une variable dans la ligne de commande (`architecture.md`, sécurité ; même politique que `run` et `agents`).
- R27 — Le texte **de la vue** (pas le fichier sur disque) est écrit sur `stdin`, le texte formaté est lu sur `stdout`, les diagnostics sur `stderr`. Wraith ne donne aucun chemin au formateur : une commande qui a besoin du nom du fichier pour choisir son parseur le reçoit dans sa propre ligne (`--stdin-filepath file.ts`), écrite par l'utilisateur.

### Application

- R28 — Le résultat n'est appliqué **que si** les trois conditions sont réunies : code de sortie `0`, `stdout` non vide, texte différent de l'actuel. Sinon rien ne bouge et `stderr` (tronqué) s'affiche dans la bannière de l'onglet. Un formateur qui écrit ses diagnostics sur `stdout` avec un code non nul ne peut donc pas écraser le fichier.
- R29 — Le remplacement se fait dans la vue de texte en **une seule opération d'undo** : `cmd+z` rend exactement le texte d'avant le formatage. La position du curseur est conservée par **ligne et colonne** (bornées au nouveau texte), le scroll est conservé, et l'onglet devient `isDirty` (le formatage est une modification comme une autre — sauf en R31, où la sauvegarde suit immédiatement).
- R30 — Borne : 5 s. Au-delà, le process est arrêté (`SIGTERM` puis `SIGKILL`), le texte reste inchangé et la bannière le dit. Une seule exécution à la fois par onglet ; un second déclenchement pendant qu'une exécution est en cours est ignoré (bip), jamais mis en file.
- R31 — `formatter.onSave` : le formatage s'exécute **avant** l'écriture de `cmd+s` (R8), sur le texte de la vue, et l'écriture porte sur le texte formaté. **Un échec ne bloque jamais une sauvegarde** : si le formateur échoue, dépasse la borne ou n'existe pas, le fichier est sauvé tel qu'il est et la bannière explique. `cmd+opt+s` (tout sauver) formate chaque onglet modifié de la même façon, en série.
- R32 — Refusé avec sa raison sur un fichier en lecture seule ou dépassant le seuil de lecture seule (R16, 2 Mo), et sur un onglet markdown en mode `preview` (R14) : il n'y a pas de texte éditable à remplacer.
- R33 — Le formateur ne reçoit aucun chemin et Wraith n'écrit rien pour lui : tout passe par `stdin`/`stdout`. Si la commande de l'utilisateur écrit elle-même sur le disque, Wraith ne le détecte ni ne l'empêche — c'est sa commande, comme un `run` (`run` R2).

## Cas limites

- Binaire absent du `PATH` : la commande rend `command not found` sur `stderr` et un code non nul ; en plus, le premier mot de la commande est cherché dans le `PATH` résolu (comme `agents` R2) pour dire « `prettier` not found in PATH » plutôt que recopier la plainte du shell.
- Fichier syntaxiquement invalide : les formateurs (prettier, black, rustfmt) sortent en erreur ; R28 s'applique, le texte ne bouge pas.
- Formateur lent au premier appel (JVM, `npx` qui résout un paquet) : la borne de 5 s de R30 peut le couper ; la bannière propose alors d'augmenter la borne (`formatter.timeout`, secondes) ou d'installer le binaire localement.
- Fins de ligne : le texte de la vue est toujours en LF (`FileDocument.decode` normalise, R3) et la sauvegarde restaure les CRLF (R8). Le formateur ne voit et ne rend que du LF.
- Encodage : le texte est transmis en UTF-8 ; un fichier lu en Latin-1 est déjà réécrit en UTF-8 à la sauvegarde (R3, cas limites) — le formatage ne change pas cette politique.
- Formateur qui rend un texte identique : rien n'est appliqué, l'onglet ne devient pas `isDirty` (R28 : texte différent requis).
- Fichier modifié sur disque pendant le formatage : la sauvegarde qui suit applique R10 (conflit détecté, *Écraser* / *Annuler*), inchangé.
- Deux onglets du même fichier dans deux groupes : impossible dans un groupe (R1), et chaque groupe formate son propre texte ; le second recevra la bannière de conflit à la sauvegarde (R10).

## Hors périmètre v1

- Formatage d'une sélection seulement, format on type, format on paste.
- Formatage de plusieurs fichiers, d'un dossier ou du workspace.
- LSP (`textDocument/formatting`), organisation des imports, fix-all, linting, diagnostics.
- Détection automatique du formateur d'un projet (`.prettierrc`, `pom.xml`, `.editorconfig`) : la commande est déclarée dans la config, point — même politique que `run` R1 (pas de détection automatique).
- Formatage du diff `git` (lecture seule, `git` R13) et de l'éditeur SQL de `postgres` (`postgres` R9) : si le besoin apparaît, il réutilisera la même section de config.
- Formateur embarqué dans l'app : voir les options techniques et la décision du 2026-08-27.

## Options techniques

Le point à trancher est unique : **librairie embarquée ou binaire externe**.

### Binaires de l'utilisateur, lancés par `Process`

C'est ce que fait déjà Wraith pour `run`, `agents` et `rg` : `$SHELL -l -c "<commande>"` avec l'environnement du login shell résolu une fois par fenêtre (`Workspace.loginEnvironment()`), `stdin`/`stdout`/`stderr` en `Pipe`, exécution hors main actor. Les formateurs courants lisent tous `stdin` et écrivent sur `stdout` :

| Langage | Commande | Mode stdin → stdout |
|---|---|---|
| Swift | `swift format` | `swift format` sans fichier lit `stdin` |
| TypeScript / JS / CSS / JSON / Markdown / YAML | `prettier` | `prettier --stdin-filepath <nom>` |
| Python | `black` | `black -q -` |
| Rust | `rustfmt` | `rustfmt --emit stdout` |
| Go | `gofmt` | `gofmt` sans argument lit `stdin` |
| C / C++ / Java / ObjC | `clang-format` | `clang-format --assume-filename=<nom>` |

Coût : ~80 lignes (lancement, `Pipe`, borne de temps, décision d'application), plus le décodage de la section. Aucune dépendance ajoutée. Détection du binaire : `AgentCatalog.executables(among:inPath:)` (`Wraith/Agents/AgentCatalog.swift`) est déjà écrite, `static` et pure — elle est appelée directement plutôt que recopiée.

### Librairie SPM embarquée

Une seule existe vraiment et est maintenue : **swift-format** (`github.com/swiftlang/swift-format`), projet Swift.org. Vérifié sur le dépôt amont le 2026-08-27 : dernier tag `603.0.0` (2026-06-30), produit **librairie** `SwiftFormat`, API `SwiftFormatter.format(source:assumingFileURL:selection:to:parsingDiagnosticHandler:)` — avec un paramètre `Selection` par plages d'offsets, donc même le formatage de sélection serait gratuit. Elle dépend de `swift-syntax` (≥ 602), `swift-markdown` (déjà dans le projet) et `swift-argument-parser` (déjà résolu).

Ce qu'elle ne fait pas : tout le reste. Elle ne formate que du Swift, soit **une** des quatorze grammaires de R11, et le projet type de l'auteur est en Java, Kotlin ou TypeScript. Pour les autres langages, aucune librairie Swift maintenue n'existe : ce qui existe sont les binaires ci-dessus, écrits en Rust, Go, Python ou C++. Embarquer swift-format signifierait donc **deux mécanismes** — une lib pour le Swift, des binaires pour le reste — et `swift-syntax` en dépendance, la plus grosse du projet à compiler.

Aucune autre librairie de formatage n'est proposée ici : elles n'existent pas, et `AGENTS.md` interdit d'en citer une de mémoire.

### Le reste

- **Application du texte** : `NSTextView.shouldChangeText(in:replacementString:)` puis `replaceCharacters(in:with:)` puis `didChangeText()` — c'est la voie native pour une modification annulable d'un coup, avec le `NSUndoManager` déjà activé (`allowsUndo = true`, `EditorTextView.swift`). Rien à écrire.
- **Position du curseur** : ligne et colonne relevées avant, réappliquées après avec `TextEditing.location(ofLine:in:)` (`Wraith/Editor/TextEditing.swift`, déjà écrite pour `cmd+l`), bornées au nouveau texte.
- **Tests** : décodage de la section `formatter` (clé `onSave` réservée, extension inconnue, valeur mal typée), choix de la commande par extension, décision d'application (code, `stdout` vide, texte identique), report de la position du curseur (ligne/colonne, y compris ligne disparue et fichier raccourci), construction de l'invocation. Aucun test ne lance un formateur (`coding-rules` : hermétiques).

## Décisions

Voir [decisions.md](decisions.md).
