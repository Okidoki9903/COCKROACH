# COCKROACH — État du projet

_Dernière mise à jour : 2026-09-28 — validation du socle avec Godot 4.7.2._

## Version du moteur (fixée)

| Élément | Valeur |
|---|---|
| Moteur | **Godot 4.7.2-stable**, édition standard, build `4.7.2.stable.official.ed1daf0bf` |
| Provenance | Release officielle `godotengine/godot`, tag `4.7.2-stable`, fichier `Godot_v4.7.2-stable_linux.x86_64.zip` (GitHub Releases) |
| Intégrité | SHA-512 vérifié contre le fichier `SHA512-SUMS.txt` de la même release : OK. Pas de signature cryptographique, car le projet Godot n'en publie pas. |
| Rendu | Forward+ (défaut du projet, inchangé) |
| Tag de fonctionnalités | `4.7` dans `project.godot` |

Conserver cette version pendant tout le prototype. Tout changement de
version passe par `docs/DECISIONS.md`.

## État réel

Le socle s'importe et s'exécute sans erreur ni avertissement dans Godot
4.7.2. `boot` charge `scale_test`. Le rendu Forward+ a été capturé et
inspecté. Il n'y a aucun système de gameplay.

**Étape A : validée pour l'import, l'exécution et le rendu Forward+ logiciel.**
Il reste des contrôles sur machine avec écran (voir plus bas). Ils ne bloquent pas la tâche B.

## Éléments du projet

| Fichier | Rôle |
|---|---|
| `project.godot` | Configuration ; scène principale = `scenes/boot/boot.tscn` |
| `scenes/boot/boot.tscn` + `scripts/boot/boot.gd` (+ `.uid`) | Point d'entrée qui charge la scène de test |
| `scenes/tests/scale_test.tscn` | Scène de vérification d'échelle |
| `data/`, `assets/` | Dossiers réservés (vides, `.gitkeep`) |
| `docs/DECISIONS.md` | Décisions de production |
| `docs/TEST_CHECKLIST.md` | Procédure de lancement, contrôles et historique |
| `docs/validation/scale_test_forward_plus_4.7.2.png` | Capture de référence |
| `.gitignore`, `.gitattributes` | Exclusion du cache `.godot/`, fins de ligne LF |

## Échelle (1 unité = 1 mètre)

| Objet | Dimensions (m) | Position (m) |
|---|---|---|
| Sol (`Floor`, collision) | 2 × 0,02 × 2 — face supérieure à y = 0 | (0, −0,01, 0) |
| Meuble (`Furniture`, collision) | 0,6 × 0,85 × 0,6 — caisson de cuisine | (0, 0,425, −0,5) |
| Repère cafard (`CockroachMarker`) | 0,012 × 0,006 × 0,03 — 3 cm de long selon Z | (0, 0,003, 0) |
| Barre d'échelle (`ScaleBar10cm`, jaune) | 0,10 de long selon X | (0, 0,001, 0,03) |
| Caméra fixe (`FixedCamera`) | FOV 60°, near 0,001, far 20 | (0,06, 0,035, 0,10), visée vers (0, 0,012, −0,06) |
| Lumière (`KeyLight`) | Directionnelle, direction ≈ (0,61 ; −0,66 ; −0,45) | biais 0,02, biais normal 0,5, distance d'ombre 1,5 |

## Vérifications — 2026-09-28

Environnement : conteneur Ubuntu 24.04 x86_64, sans écran ni GPU. Godot est
installé hors du dépôt (`/home/user/tools/godot/4.7.2/`). Pour le rendu :
Xvfb, et le pilote Vulkan logiciel Mesa lavapipe (`mesa-vulkan-drivers`,
installé par apt dans le conteneur).

| Type | Commande | Code | Résultat |
|---|---|---|---|
| Statique | Script de cohérence des scènes (session précédente) | — | OK ; non relancé, car les modifications ne touchent aucune référence |
| Importation | `--headless --path . --import` | 0 | Aucune erreur ni avertissement. Génère `.godot/` (ignoré) et `scripts/boot/boot.gd.uid` (committé) |
| Exécution | `--headless --path . --verbose --quit-after 120` | 0 | Aucune erreur ni avertissement ; journal : chargement de `boot.tscn`, `boot.gd`, puis `scale_test.tscn` |
| Rendu Forward+ | `xvfb-run … --write-movie … --quit-after 60` avec lavapipe | 0 | Journal : `Vulkan 1.4.318 - Forward+ - llvmpipe` ; 60 images capturées |
| Visuel | Inspection de la capture | — | Voir ci-dessous |

Un premier rendu sans Vulkan a basculé automatiquement vers OpenGL
(Compatibility). Ce rendu n'est pas la cible et n'a pas servi à la
validation. Le renderer du projet n'a pas été modifié.

### Inspection visuelle (capture Forward+)

- Repère cafard, barre de 10 cm (environ 3 fois le repère) et meuble
  gigantesque : visibles et lisibles.
- Pas d'objet coupé par le plan proche, pas d'acné d'ombre.
- 55 images consécutives identiques au pixel près. Cela exclut un
  scintillement **pour une caméra et une scène statiques uniquement**.

### Défaut constaté et corrigé

**Symptôme :** aucune ombre portée sous le repère cafard.

1. Hypothèse « ombre cachée derrière le repère » : lumière et caméra venaient
   du même côté. J'ai réorienté la lumière, sans effet sur l'ombre : **réfutée**.
   La nouvelle orientation est conservée, car elle place l'ombre du côté visible.
2. Hypothèse « biais d'ombre par défaut trop grand pour un objet de 6 mm » :
   `shadow_bias` 0,1 → 0,02, `shadow_normal_bias` 2,0 → 0,5,
   `directional_shadow_max_distance` 5 → 1,5. **Confirmée** : l'ombre apparaît,
   attachée à la base du repère.

Après correction, l'importation, l'exécution et le rendu ont été relancés :
tous OK.

## Vérifications restantes (non bloquantes pour B)

- Lancement interactif (F5) sur une machine avec GPU réel.
- Contrôles dans l'éditeur (voir `docs/TEST_CHECKLIST.md`), puis commit des
  `uid=` que l'éditeur ajoutera aux scènes.
- Scintillement en mouvement : à tester avec la caméra de la tâche C.

## Limites connues

- Aucune icône de projet.
- Caméra fixe provisoire, sans script ; elle sera remplacée à la tâche C.
- Pas de collision sur le repère cafard (pas de gameplay).
- Le conteneur distant est éphémère. Godot et lavapipe devront être
  réinstallés à chaque nouvelle session (voir le script dans
  `docs/TEST_CHECKLIST.md`).

## Prochaine tâche

Tâche **B — Player : entrées du joueur** (actions nommées dans l'`InputMap`,
adaptateur d'entrées). **Prête à commencer ; non commencée.**
