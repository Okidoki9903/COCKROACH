# Caméra troisième personne (tâche C)

## Composants

| Fichier | Rôle |
|---|---|
| `scenes/camera/camera_rig.tscn` + `scripts/camera/camera_rig.gd` | `CameraRig` réutilisable |
| `scripts/player/player_input.gd` | Intention de regard (souris), à côté du déplacement |
| `scripts/game/pause_controller.gd` | Capture et libération de la souris (`capture_mouse`) |
| `scenes/tests/camera_test.tscn` | Scène de test caméra |
| `scripts/ui/camera_debug_panel.gd` | Panneau de diagnostic et boutons de position |
| `scenes/tests/camera_test_runner.tscn` + `.gd` | Test automatique (54 contrôles) |
| `scenes/tests/camera_capture.tscn` + `.gd` | Captures de rendu reproductibles |

Structure du rig :

```text
CameraRig (Node3D, top_level)      lacet (yaw), suit la cible
└─ Pitch (Node3D)                   tangage (pitch)
   ├─ SpringArm3D                   mesure seulement l'espace libre (sphère)
   └─ Camera3D                      placée par le script, pas par le bras
```

La caméra n'est pas enfant du `SpringArm3D`. Le bras mesure l'espace libre ;
le script rapproche la caméra immédiatement si nécessaire, puis la ramène
à `return_speed`.

Ordre de mise à jour, vérifié par le test :

1. `_physics_process` du rig : lit le regard, applique lacet et tangage,
   suit la cible ;
2. étape physique du `SpringArm3D` (enfant, donc après le rig) : mesure
   avec l'orientation courante ;
3. `_process` du rig : place la caméra à la distance permise.

## Entrées souris

- `PlayerInput.consume_look()` renvoie la rotation demandée depuis
  l'appel précédent, en radians : **x > 0 = tourner à droite, y > 0 =
  regarder vers le haut**.
- Source : `InputEventMouseMotion.screen_relative`, indépendant de
  l'étirement de la fenêtre. C'est une distance déjà mesurée : **jamais
  multipliée par delta**. Le test vérifie que 10 × 10 px = 1 × 100 px.
- Pendant la pause ou après une perte de focus, les mouvements sont ignorés
  et l'accumulateur est vidé. La reprise ne produit donc aucun saut.
- La capture est gérée par `PauseController` (`capture_mouse = true` dans
  la scène caméra ; `false` par défaut, donc `input_test` est inchangé) :
  - souris capturée pendant le jeu ;
  - libérée en pause et à la perte de focus ;
  - recapturée seulement à la reprise par Échap.
- Le rig ne connaît pas la pause. Il tourne en `PROCESS_MODE_ALWAYS` pour
  continuer à mesurer les obstacles, par exemple après un changement de
  position pendant la pause. Le regard est figé par `PlayerInput`.

## Réglages retenus

| Réglage | Où | Valeur | Justification |
|---|---|---|---|
| `look_sensitivity` | PlayerInput | 0,003 rad/px (≈ 0,17°/px) | 100 px ≈ 17°. Point de départ, à régler avec une vraie souris |
| `invert_look_y` | PlayerInput | faux | Option |
| `pitch_min_deg` / `pitch_max_deg` | CameraRig | −70° / +10° | Vue plongeante utile sans retournement ; au-delà de +10°, le sol bloque la caméra de toute façon |
| `pivot_height` | CameraRig | 0,012 m | Juste au-dessus du dos du cafard (6 mm) |
| `desired_distance` | CameraRig | 0,12 m | Environ 4 longueurs de corps ; cible lisible, contexte visible |
| `return_speed` | CameraRig | 0,3 m/s | Vitesse de retour maximale |
| `return_smoothing` | CameraRig | 0,15 s | Ajouté en tâche D : retour proportionnel à l'écart, qui filtre le bruit de mesure |
| `return_window_ticks` | CameraRig | 10 | Ajouté en tâche D : on ne revient que vers la distance libre minimale des 10 derniers ticks |
| `collision_mask` | CameraRig | couche 1 (décor) | La cible est sur la couche 2 **et** exclue du bras |
| Rayon de la sphère du bras | camera_rig.tscn | 0,006 m | Voir « Imprécision des collisions » |
| Marge du bras | camera_rig.tscn | 0,003 m | Soustraite à la distance mesurée en cas de contact |
| FOV / near / far | Camera3D | 70° / 0,001 m / 20 m | Le near de 1 mm est conservé, car tous les tests passent |

La marge de `SpringArm3D` ne s'applique qu'aux **enfants** du bras. La
caméra n'en est pas un, donc le rig la soustrait lui-même
(`get_free_distance()`). Aucune distance minimale n'est imposée : si le
bras mesure 0, la caméra vient au pivot, elle ne traverse pas un mur.

Changement de position (`snap_to_target`) : la caméra est placée au pivot
jusqu'à la prochaine étape physique, puis directement à la distance
mesurée. Elle ne balaie jamais le décor entre l'ancienne et la nouvelle
position.

## Imprécision des collisions à l'échelle millimétrique

Mesuré le 2026-09-28 : `cast_motion` d'une petite sphère contre un mur
renvoie une fraction « sûre » qui pénètre en réalité le mur, de 2 à 4 mm.
Exemple : une sphère de 4 mm s'arrête à 1,5 mm de la face, et
`intersect_shape` confirme le chevauchement. Le résultat est identique avec
JoltPhysics3D (moteur par défaut) et GodotPhysics3D, ce qui est vérifié
avec un `override.cfg` temporaire. Avec 8 mm de rayon, l'écart tombe à
0,6 mm : l'erreur n'est pas proportionnelle et sa cause n'est pas
identifiée.

Conséquence pour la caméra : sphère de 6 mm et marge de 3 mm. Le critère
testé est direct : une sphère de 1,5 mm autour de la caméra (demi-diagonale
du plan proche, plus une marge) ne touche jamais le décor. Le test le
vérifie aux 5 positions et sur 4 × 144 pas de rotation. Avant la marge,
jusqu'à 25 images fautives apparaissaient face à un mur ou dans le coin.

**Risque pour la tâche D :** un contrôleur de personnage de 3 cm sera
exposé à la même imprécision. À étudier en premier dans D.

## Scène de test

`scenes/tests/camera_test.tscn` (1 unité = 1 m, sol de 2 × 2 m) :

| Position (bouton) | Cible | Décor testé | Distance caméra mesurée |
|---|---|---|---|
| Ouvert | (−0,2 ; 0 ; 0,4), yaw 0° | rien derrière | 0,120 m |
| Mur | (−0,3 ; 0 ; −0,86), yaw 180° | mur à 4 cm derrière (face z = −0,9) | 0,038 m |
| Coin | (−0,86 ; 0 ; −0,86), yaw −135° | deux murs à 4 cm | 0,048 m |
| SousMeuble | (0,5 ; 0 ; −0,5), yaw 0° | caisson 50 × 40 × 40 cm sur pieds, dessous à 10 cm | 0,120 m (0,084 m à −70°) |
| PassageEtroit | (0,5 ; 0 ; 0,42), yaw 0° | passage de 5 cm de large, 3 cm de haut, 30 cm de long | 0,034 m |

Le cafard mesure 1,2 cm de large et 0,6 cm de haut : le passage lui laisse
environ 4 fois sa largeur et 5 fois sa hauteur.

Lancer :

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/tests/camera_test.tscn     # interactif (F6 dans l'éditeur)
$G --headless --path . res://scenes/tests/camera_test_runner.tscn   # 54/54, code 0
# Captures (rendu réel nécessaire) :
$G --path . res://scenes/tests/camera_capture.tscn -- --out=/tmp/captures
```

Utilisation : souris pour tourner, **Échap** pour libérer la souris et
cliquer sur une position, **Échap** pour reprendre. Les boutons ne font que
téléporter la cible : ce n'est pas un contrôleur de déplacement.

Captures de référence (Forward+, lavapipe) :
`docs/validation/camera/positions_4.7.2.jpg` et
`docs/validation/camera/sweep_wall_4.7.2.jpg` (rotation de 82° le long du
mur, la caméra se dégage progressivement).

## Évolution en tâche D

Avec un personnage mobile, la distance caméra « respirait » dans les
passages : de 31,7 à 38,7 mm, avec des sauts jusqu'à 5,6 mm par tick.
Le retour est maintenant lissé et fenêtré (voir le tableau). Le
rapprochement reste immédiat. Résultat : au plus 0,47 mm par tick. Détails
dans `docs/MOVEMENT.md`.

## Limites observées

- Le long d'un mur, la distance varie de quelques millimètres d'un pas de
  rotation à l'autre (par exemple 38 → 35 → 37 mm), à cause de
  l'imprécision ci-dessus. Aucune oscillation n'apparaît à position fixe,
  mais un léger tremblement en rotation lente contre un mur reste possible.
  **À juger avec une vraie souris.**
- La rotation est appliquée au rythme physique (60 Hz). Sur un écran à plus
  de 60 Hz, la caméra peut paraître saccadée. Pistes si c'est constaté :
  physics interpolation, ou mesure manuelle de l'obstacle dans `_process`.
- Si le bras mesure presque 0 (cafard collé à un mur, caméra pointée vers
  lui), la caméra entre dans le maillage du cafard. Ce n'est pas observé
  aux positions testées (distance minimale 3,4 cm).
- Dans les zones d'ombre (coin, passage, dessous de meuble), la cible
  devient très sombre. C'est une question d'éclairage, pas de caméra.
- Rendu logiciel (lavapipe) uniquement : **aucune mesure de performance**
  n'a de valeur ici.
