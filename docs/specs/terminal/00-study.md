# terminal — Étude

## Objectif

Fournir la **surface terminal** qui héberge les onglets des plugins `agents` et `run` : un pseudo-terminal (PTY) possédé par Wraith, un **process** lancé dedans (l'agent ou la commande), une émulation VT + rendu par SwiftTerm, un cycle de vie (running → exited), des événements (sortie du process, bell, titre) et le service `TerminalService` offert aux plugins.

**Ce n'est pas un type d'onglet utilisateur** (`product` R4) et **ce n'est pas un shell** : aucun `cmd+t`, aucun « nouveau terminal », aucun prompt. Un onglet terminal = un process ; quand il se termine, la surface se fige avec son code de sortie. L'utilisateur interagit avec le process (les agents sont des TUI plein écran : saisie, couleurs, souris, redimensionnement), jamais avec un shell.

## Pourquoi SwiftTerm et pas libghostty

Le besoin a changé : on n'émule pas un terminal pour l'utilisateur, on affiche des TUI (Ink, Bubbletea…) et la sortie de builds. SwiftTerm (pur Swift, SPM, PTY intégré, VT/xterm complet, 24 bits, souris, utilisé par des TUI lourds) couvre ça sans build zig, sans C vendorisé, sans API instable. libghostty (rendu Metal, shell integration, config Ghostty) n'apporte rien au produit et coûtait le milestone le plus risqué. Décision : **SwiftTerm seul**, aucun repli prévu (`coding-rules` §12.1).

## User stories

- US1 — Je clique un agent ou lance un run : la surface apparaît en < 100 ms et le process démarre avec mon environnement habituel (PATH, variables du login shell).
- US2 — L'agent (TUI plein écran) fonctionne comme dans Terminal : saisie, couleurs, souris, redimensionnement, copier/coller.
- US3 — Un onglet inactif me montre que le process a sonné ou s'est terminé (et comment : code de sortie).
- US4 — Je ferme un onglet dont le process tourne : confirmation ; le process est arrêté proprement.
- US5 — Un plugin peut lancer une commande dans un dossier, connaître son état (running / exit code) et lui envoyer un signal.
- US6 — À la réouverture du workspace, mes onglets agent/run sont recréés au même cwd, prêts à être relancés (`product` R7).

## Règles fonctionnelles

### Process et environnement

- R1 — Un onglet terminal exécute **une commande** fournie par le plugin propriétaire, via `$SHELL -l -c "<commande>"` (`$SHELL` de l'utilisateur, sinon `/bin/zsh`) : le login shell charge l'environnement de l'utilisateur (PATH, profils) puis exécute la commande ; il n'y a **pas de prompt**, le shell se termine avec la commande. La commande est le texte fourni tel quel (`coding-rules` R16.3), jamais recomposée par Wraith.
- R2 — cwd : fourni par le plugin (`agents` : racine ou repo ; `run` : dossier du repo/`cwd`), obligatoirement sous la racine ou absolu explicite. Le cwd est celui du lancement ; il est persisté (`config` R10) et sert à la restauration.
- R3 — Environnement : celui du login shell, enrichi de `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=wraith`, `WRAITH_WORKSPACE=<racine>`, plus l'`env` fourni par le plugin (`run` R8). Aucune variable de `config.json` n'est injectée d'office.
- R4 — Pas de shell integration (OSC 7/133) : inutile, Wraith possède le process. L'état vient du PTY (R6), le cwd est connu (R2).

### État, titre et signaux

- R5 — Titre d'onglet : **fixe**, fourni par le plugin (`Claude`, `backend:test`). Un titre poussé par le process (OSC 0/2) est exposé en sous-titre/tooltip, jamais à la place.
- R6 — État d'un onglet : `idle` (créé ou restauré, pas encore lancé) → `running` (process vivant, pid connu) → `exited(code)` (`waitpid`, code ou signal). Exposé par `TerminalService` et publié en événements ; c'est la seule source de l'état pour `agents` R6 et `run` R10.
- R7 — Un onglet **inactif** est marqué (badge) quand : la bell sonne, ou son process se termine. Le marqueur disparaît à l'activation de l'onglet. Pas de notification système en v1.
- R8 — Process terminé : la surface reste affichée, figée, avec une ligne d'état en bas (`terminé · code 0` / `code 1` / `signal SIGINT`) et un bouton *Relancer* (même commande, même cwd, nouvelle PTY dans le même onglet). L'onglet ne se ferme jamais seul.
- R9 — Signaux : `signal(SIGINT|SIGTERM, to: tab)` envoyé au **groupe de process** du PTY. `SIGKILL` n'est jamais automatique.

### Fermeture

- R10 — Fermeture demandée (`cmd+w`, groupe, fenêtre) : si `running` → confirmation (`layout` R15, l'onglet est « dirty » à ce titre) ; sinon fermeture immédiate.
- R11 — Fermer envoie `SIGHUP` au groupe de process, ferme le maître du PTY, attend la fin (`waitpid`, 5 s max puis `SIGKILL` **uniquement dans ce cas de fermeture forcée**) ; aucun descripteur ni zombie ne survit à l'onglet (`coding-rules` §12.2).

### Saisie, souris, apparence

- R12 — Clavier : `layout` R25 — tout ce qui n'est pas un raccourci `cmd+…` de Wraith va au process (dont `ctrl+c`, `ctrl+d`, flèches, `esc`). `cmd+c`/`cmd+v` copient/collent (sélection SwiftTerm), `cmd+k` efface le scrollback, `cmd+=`/`cmd+-` zoom police (portée `tab(terminal)`).
- R13 — Souris : sélection, copie, scroll, transmission des événements souris aux TUI qui la demandent — délégués à SwiftTerm. Liens détectés cliquables (`cmd+clic`).
- R14 — Apparence : police monospace et thème définis par Wraith (`ThemeService`, `coding-rules` R9.7) ; `~/.config/wraith/config.json` (`terminal.font`, `terminal.fontSize`, `terminal.theme`) les surcharge. Scrollback : 10 000 lignes.
- R15 — Redimensionnement : la surface reçoit sa taille en points depuis le layout (`layout` R21) ; SwiftTerm en déduit lignes/colonnes et Wraith envoie `TIOCSWINSZ`/`SIGWINCH`.

### Service pour les plugins (`WraithKit`)

- R16 — `TerminalService` : `spawn(command:, cwd:, env:, kind:, title:) -> TabID` (crée l'onglet et lance), `relaunch(TabID)`, `signal(_:to:)`, `write(_ bytes:, to:)` (saisie brute, rarement utile), `state(of:) -> TerminalState`, `pid(of:)`, et un flux `events` (`started(tab, pid)`, `exited(tab, code)`, `bell(tab)`, `closed(tab)`) en `AsyncStream` (`coding-rules` R7.9). Le `kind` est celui du plugin appelant (`agent.<id>`, `run.<id>`) ; il n'existe pas de kind `terminal`.
- R17 — Un plugin ne peut agir que sur les onglets de la fenêtre courante ; un `TabID` inconnu ou fermé → `TerminalError.noSuchTab`.
- R18 — Plusieurs surfaces coexistent sans limite ; chacune a son PTY et son process. Une surface `exited` ou inactive ne consomme pas de CPU (`coding-rules` R15.7) ; la lecture du PTY est agrégée avant de toucher l'UI.

## Cas limites

- `$SHELL` introuvable ou non exécutable : repli `/bin/zsh`, message dans la surface.
- Commande introuvable (`command not found`) : le shell sort avec 127 → `exited(127)`, visible dans la surface ; pas de bannière Wraith.
- cwd persisté disparu à la restauration : onglet `idle` avec bannière « dossier introuvable », *Relancer* désactivé jusqu'à correction.
- Process qui ignore `SIGINT`/`SIGTERM` : R11 (fermeture forcée uniquement) ; sinon il tourne, l'utilisateur voit `running`.
- Sortie massive (build verbeux) : lecture du PTY par blocs, rendu par frame ; scrollback borné (R14).
- Process qui lance des sous-process (serveur, `npm start`) : ils sont dans le groupe de process du PTY et reçoivent les signaux R9/R11.

## Hors périmètre v1

- **Shell interactif** (`cmd+t`, « nouveau terminal », « terminal ici », prompt) : délibérément absent (`product` R4).
- libghostty, rendu Metal, config Ghostty, shell integration (OSC 7/133).
- Restauration du scrollback (`product`), sessions persistantes façon tmux.
- Notifications système, profils par workspace.

## Options techniques

- **Dépendance** : `SwiftTerm` (SPM, épinglé `.upToNextMinor`), importé uniquement dans `WraithTerminal` (`coding-rules` R11.1). `TerminalView` (AppKit) confiné dans un `NSViewRepresentable` (`coding-rules` R9.1) ; on n'utilise **pas** `LocalProcessTerminalView` : le PTY et le process sont à Wraith (R6, R9, R11), SwiftTerm ne reçoit que les octets (`feed`) et renvoie ce que l'utilisateur tape (`send`).
- **PTY** : `actor PTYSession` (`coding-rules` §12.2) : `posix_openpt`/`forkpty`, `execve` de `$SHELL -l -c`, lecture non bloquante via `DispatchIO`/`FileHandle.readabilityHandler` → `AsyncStream<Data>`, `waitpid` via `DispatchSource.makeProcessSource`, `tcsetpgrp`/`killpg` pour les signaux. Interop POSIX confinée (`coding-rules` §13).
- **Tests** (`coding-rules` P6) : `PTYSession` testé en vrai sur `/bin/sh -c 'exit 3'`, `sleep` + `SIGINT`, sortie massive ; `FakeTerminalService` pour les plugins ; la logique de badge (R7), d'état (R6) et de confirmation (R10) testée sans UI.

## Décisions

Voir [decisions.md](decisions.md).
