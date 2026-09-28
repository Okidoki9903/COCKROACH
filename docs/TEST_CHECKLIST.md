# Checklist de test — Étape A (socle)

## Lancement

1. Installer Godot 4 stable (édition standard, pas .NET).
2. Ouvrir le gestionnaire de projets → *Importer* → sélectionner
   `project.godot` à la racine du dépôt.
3. Si Godot propose une conversion ou une mise à jour du format, accepter,
   puis noter la version dans `docs/PROJECT_STATE.md`.
4. Lancer le projet avec **F5** (scène principale) — pas F6.

Ligne de commande équivalente (vérification de chargement sans fenêtre) :

```sh
godot --headless --path . --import          # génère le cache .godot/
godot --headless --path . --quit-after 120  # lance ~2 s puis quitte
```

## Contrôles automatiques / console

- [ ] Import sans erreur dans le panneau *Sortie*.
- [ ] Au lancement, aucune erreur ni avertissement dans *Débogueur → Erreurs*.
- [ ] La scène `Boot` est remplacée par `ScaleTest`
      (*Débogueur → Arbre distant* : racine `ScaleTest`).

## Contrôles visuels (inspection humaine)

- [ ] Le repère cafard brun (3 cm) est visible en avant-plan.
- [ ] La barre jaune de 10 cm est visible devant lui ; le repère fait
      environ un tiers de sa longueur.
- [ ] Le meuble brun occupe l'arrière-plan et paraît gigantesque.
- [ ] Le sol est visible, sans scintillement (z-fighting) ni objet coupé
      par le plan proche.
- [ ] Les ombres portées du repère et du meuble sont visibles.

## Contrôles dans l'éditeur

- [ ] `scale_test.tscn` s'ouvre sans ressource manquante.
- [ ] Sélectionner `CockroachMarker` : la taille du maillage vaut
      (0,012 ; 0,006 ; 0,03).
- [ ] *Projet → Paramètres → Application → Exécuter* : scène principale
      = `res://scenes/boot/boot.tscn`.

## Résultat

Consigner dans `docs/PROJECT_STATE.md` : version exacte, date, cases
cochées, capture éventuelle et problèmes constatés.
