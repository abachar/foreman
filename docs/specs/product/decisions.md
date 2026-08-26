# product — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Utilisateur unique (l'auteur), pas de publication en v1 | Publication Homebrew dès le départ | Itérer vite sans contrainte de compatibilité |
| 2026-08-25 | Une fenêtre = un dossier = un workspace (modèle IDE) | Fenêtre unique multi-workspaces ; workspace multi-fenêtres | Simplicité du modèle mental, isolation de l'état |
| 2026-08-25 | Zone centrale = arbre de splits H/V, feuilles = groupes d'onglets (composant réutilisé) | Onglets seuls en v1 | Besoin réel de terminaux côte à côte ; le composant unique évite la duplication |
| 2026-08-25 | Persistance et restauration de l'état du workspace | Repartir à zéro à chaque ouverture | Confort quotidien |
| 2026-08-25 | Exécution locale uniquement, aucune distribution en v1 | DMG signé/notarisé | Inutile pour un usage perso ; reporté |
| 2026-08-25 | État persisté dans `<workspace>/.wraith/state.json` ; `.wraith/` est le dossier de config local du workspace | `~/Library/Application Support/Wraith/<hash>` | État lié au dossier, visible et versionnable/ignorable au choix |
| 2026-08-26 | Positionnement **agentic** : les agents CLI sont des citoyens de première classe (boutons dédiés, onglet par agent), distincts des commandes `run` | « Terminal-first » pur, agents = un shell parmi d'autres | C'est l'usage principal visé ; un agent n'est pas une commande définie par l'utilisateur |
| 2026-08-26 | **Pas de shell libre** : aucun onglet terminal à l'initiative de l'utilisateur ; les surfaces terminal hébergent uniquement agents et runs (un onglet = un process, pas de shell) ; groupe vide = écran d'accueil (style IntelliJ) | Terminal-first avec `cmd+t` = nouveau shell (décision du 2026-08-25) ; shell ouvrable mais non par défaut | Wraith n'est pas un émulateur de terminal ; `cd`/`ls` se font ailleurs, l'agent fait le travail |
| 2026-08-26 | Deployment target = dernière version stable de macOS (26), projet Xcode source de vérité, App Sandbox désactivé | macOS 15 ; SwiftPM seul | Un seul utilisateur sur la dernière version ; Liquid Glass et Swift 6.2 natifs ; un `.app` réel (bundle, `open -a`) exige Xcode ; le sandbox bloque disque et process |
| 2026-08-26 | Barre d'outils native possédée par le layout, alimentée par les features (agents à gauche, Run à droite) | Tout au clavier/palette ; boutons dans les panneaux | Les actions les plus fréquentes méritent un clic ; une seule surface, déclarative |
| 2026-08-25 | Pas de workspace « scratch » : sans argument, le workspace est `$HOME` (comme un shell) | Fenêtre sans dossier | Modèle uniforme : toujours un dossier racine |
| 2026-08-26 | Ouverture depuis le CLI : `cli/wraith` = `open -a Wraith <dossier>`, reçu par `application(_:open:)` ; un dossier passé en argument direct au binaire reste accepté | Schéma d'URL `wraith://open?path=` ; lancer le binaire directement | Zéro code d'ouverture à écrire : `open -a` lance ou active l'app et lui passe le dossier ; le schéma d'URL ajouterait un encodage dans le script et une deuxième porte d'entrée |
| 2026-08-26 | `Info.plist` déclare `public.folder` en `CFBundleDocumentTypes` (rôle Viewer) | Aucune déclaration, `open -a` seul | LaunchServices doit savoir que Wraith ouvre des dossiers ; c'est aussi ce qui autorise le glisser-déposer d'un dossier sur l'icône, même porte d'entrée |
