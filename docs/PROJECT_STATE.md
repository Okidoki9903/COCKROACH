# COCKROACH — État du projet

_Dernière mise à jour : 2026-09-28 — tentative de validation du socle (bloquée : Godot absent)._

## Version du moteur

| Élément | Valeur |
|---|---|
| Moteur ciblé | Godot 4 stable, GDScript, rendu Forward+ |
| Version exacte | **Non détectée** — aucun exécutable Godot dans l'environnement de création |
| Format des fichiers | `config_version=5` (projet), `format=3` (scènes) : format Godot 4.x |
| Tag de fonctionnalités | `4.4` dans `project.godot` (valeur minimale supposée, à remplacer) |

**Action requise :** à la première ouverture, noter ici la version exacte
(menu *Aide → À propos*), puis la conserver pendant tout le prototype.
Godot peut réécrire `project.godot` et ajouter des `uid` dans les scènes :
committer ces changements tels quels.

## État réel

Conception initiale terminée. Socle de projet écrit à la main, **jamais ouvert
dans Godot**. Aucun système de gameplay.

## Éléments créés

| Fichier | Rôle |
|---|---|
| `project.godot` | Configuration ; scène principale = `scenes/boot/boot.tscn` |
| `scenes/boot/boot.tscn` + `scripts/boot/boot.gd` | Point d'entrée qui charge la scène de test |
| `scenes/tests/scale_test.tscn` | Scène de vérification d'échelle |
| `data/`, `assets/` | Dossiers réservés (vides, `.gitkeep`) |
| `docs/DECISIONS.md` | Décisions de production déjà prises |
| `docs/TEST_CHECKLIST.md` | Procédure de lancement et contrôles |
| `.gitignore`, `.gitattributes` | Exclusion du cache `.godot/`, fins de ligne LF |

## Échelle (1 unité = 1 mètre)

| Objet | Dimensions (m) | Position (m) |
|---|---|---|
| Sol (`Floor`, collision) | 2 × 0,02 × 2 — face supérieure à y = 0 | (0, −0,01, 0) |
| Meuble (`Furniture`, collision) | 0,6 × 0,85 × 0,6 — caisson de cuisine | (0, 0,425, −0,5) |
| Repère cafard (`CockroachMarker`) | 0,012 × 0,006 × 0,03 — 3 cm de long selon Z | (0, 0,003, 0) |
| Barre d'échelle (`ScaleBar10cm`, jaune) | 0,10 de long selon X | (0, 0,001, 0,03) |
| Caméra fixe (`FixedCamera`) | FOV 60°, near 0,001, far 20 | (0,06, 0,035, 0,10), visée vers (0, 0,012, −0,06) |

Point d'attention découvert : le plan proche par défaut de `Camera3D`
(0,05 m) est plus grand que le cafard. Il est fixé à 0,001 m. Toute future
caméra devra conserver une valeur de cet ordre.

## Vérifications

| Vérification | Statut |
|---|---|
| Cohérence manuelle des chemins `res://` et des identifiants de ressources | Exécutée (relecture) |
| Orthonormalité des matrices caméra et lumière | Exécutée (calcul) |
| Ouverture du projet dans Godot | **Non exécutée** — moteur absent |
| Lancement de la scène, erreurs console | **Non exécutée** |
| Cadrage et lisibilité de l'échelle | **Non exécutée** |

### Tentative de validation — 2026-09-28

Environnement : conteneur Linux distant. Recherche de Godot : `which godot
godot4 Godot godot-headless`, recherche de fichiers `*godot*` sur tout le
disque, flatpak, snap. Résultat : **aucun exécutable**, seulement des
définitions de type MIME (`/usr/share/mime/application/x-godot-*.xml`).
Statut : **bloquée**. Aucun fichier du projet n'a été modifié.

Contrôle statique exécuté par script, sans le moteur :

| Contrôle | Résultat |
|---|---|
| `run/main_scene` pointe vers un fichier existant | OK |
| La cible de `boot.gd` (`scale_test.tscn`) existe | OK |
| Chaque `SubResource`/`ExtResource` utilisé est défini ; aucun inutilisé ni en double | OK (2 scènes) |
| Fichiers des `ext_resource` présents | OK |
| `load_steps` cohérent | OK |
| Chaque nœud a un parent déclaré avant lui | OK |

Ce contrôle ne garantit ni que Godot accepte les propriétés, ni le rendu.
Il n'y a eu aucun import, aucun lancement et aucune inspection visuelle.

**L'étape A n'est pas validée** tant que la checklist `docs/TEST_CHECKLIST.md`
n'a pas été passée dans Godot.

## Limites connues

- Aucune icône de projet (Godot affichera l'icône par défaut).
- Caméra fixe provisoire, sans script ; elle sera remplacée à la tâche C.
- Collision du repère cafard volontairement absente (pas de gameplay).

## Prochaine tâche

1. Passer `docs/TEST_CHECKLIST.md` dans un environnement où Godot 4 stable est
   installé (machine locale, ou environnement distant dont le script
   d'installation fournit Godot), puis consigner la version exacte.
2. Puis tâche **B — Player : entrées du joueur** (actions nommées dans
   l'`InputMap`, adaptateur d'entrées). Ne pas la commencer avant la
   validation de l'étape A. **Tâche B : en attente.**
