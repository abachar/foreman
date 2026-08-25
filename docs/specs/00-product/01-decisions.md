# 00-product — Décisions

| Date | Décision | Alternatives rejetées | Raison |
|---|---|---|---|
| 2026-08-25 | Utilisateur unique (l'auteur), pas de publication en v1 | Publication Homebrew dès le départ | Itérer vite sans contrainte de compatibilité |
| 2026-08-25 | Une fenêtre = un dossier = un workspace (modèle IDE) | Fenêtre unique multi-workspaces ; workspace multi-fenêtres | Simplicité du modèle mental, isolation de l'état |
| 2026-08-25 | Zone centrale = arbre de splits H/V, feuilles = groupes d'onglets (composant réutilisé) | Onglets seuls en v1 | Besoin réel de terminaux côte à côte ; le composant unique évite la duplication |
| 2026-08-25 | Persistance et restauration de l'état du workspace | Repartir à zéro à chaque ouverture | Confort quotidien |
| 2026-08-25 | Exécution locale uniquement, aucune distribution en v1 | DMG signé/notarisé | Inutile pour un usage perso ; reporté |
| 2026-08-25 | État persisté dans `<workspace>/.wraith/state.json` ; `.wraith/` est le dossier de config local du workspace | `~/Library/Application Support/Wraith/<hash>` | État lié au dossier, visible et versionnable/ignorable au choix |
| 2026-08-25 | Pas de workspace « scratch » : sans argument, le workspace est `$HOME` (comme un shell) | Fenêtre sans dossier | Modèle uniforme : toujours un dossier racine |
