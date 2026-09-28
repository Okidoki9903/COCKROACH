# Locomotion au sol (tâche D)

## Composants

| Fichier | Rôle |
|---|---|
| `scenes/player/player.tscn` | Scène Player réutilisable : CharacterBody3D, collision, visuel provisoire |
| `scripts/player/player_motor.gd` | `PlayerMotor` : déplacement relatif à la caméra, marche/sprint, gravité, orientation du visuel |
| `scenes/tests/movement_test.tscn` | Parcours de test (généré par `tools/gen_movement_test.py`) |
| `scripts/ui/movement_debug_panel.gd` | Panneau : vitesses demandée/réelle, contact au sol, position, boutons de retour |
| `scenes/tests/movement_test_runner.tscn` + `.gd` | Scénarios ciblés (47 contrôles) et mesure d'indépendance au rendu |
| `scenes/tests/movement_capture.tscn` + `.gd` | Séquences rendues personnage + caméra |

Structure du Player :

```text
Player (CharacterBody3D, PlayerMotor)   couche 2, masque 1 ; origine aux pieds
├─ Collision (CollisionShape3D)         cylindre vertical, ne tourne jamais
└─ Visual (Node3D)                      seul nœud orienté vers le déplacement
   ├─ Body   (boîte 1,2 × 0,6 × 3 cm)
   └─ Head   (repère d'orientation sombre, à l'avant)
```

La cible de `CameraRig` est le `CharacterBody3D` lui-même : le rig exclut
ainsi le corps de sa sonde. Toutes les échelles de transformation valent 1.

## Corps et collision

| Élément | Valeur | Pourquoi |
|---|---|---|
| Forme | `CylinderShape3D` vertical | Invariante par rotation : tourner le visuel ne change pas la collision |
| Rayon / hauteur | 10 mm / 8 mm | Couvre la largeur (12 mm) avec marge ; tête et queue du visuel dépassent de 5 mm |
| `safe_margin` | 0,2 mm | Voir mesures ci-dessous |
| `floor_max_angle` | 35° | Pente de 25° franchissable, 50° non |
| `floor_snap_length` | 5 mm | Colle au sol sur les pentes sans aspirer à travers un bord de 4 cm |
| `floor_constant_speed` | vrai | Même vitesse en montée qu'à plat |

### Mesures de collision à petite échelle (2026-09-28, Jolt, 60 Hz)

Formes comparées avec les mêmes scénarios (`--shape`, `--margin`) :

| Forme | Marge | Mur (poussée) | Longer un mur | Coin | Joint | Pente 25° | Résultat |
|---|---|---|---|---|---|---|---|
| Cylindre 10 × 8 mm | 1 mm (défaut) | écart 0,33 mm | **vibration 0,44 mm** | vibration 0,49 mm | **saut de 0,94 mm** | OK | 40/46 |
| Cylindre | 0,5 mm | 0,33 mm | OK | vibration 0,49 mm | OK | OK | 44/46 hors défauts de test |
| **Cylindre** | **0,2 mm** | **0,33 mm** | **OK** | **stable** | **OK** | **OK** | **47/47** |
| Cylindre | 0,1 mm | — | **corps bloqué, ne bouge plus** | — | — | — | inutilisable |
| Cylindre | 0,3 à 0,4 mm | OK | OK | OK | OK | vitesse en pente < 95 % | 44/46 |
| Capsule r 7 mm | 0,2 mm | **pénètre de 2,5 mm** | OK | vibration 0,75 mm | OK | n'atteint pas le plateau | 42/46 |
| Sphère r 8 mm | 0,2 mm | 0,11 mm | OK | OK | OK | n'atteint pas le plateau | 44/46 |

Conclusions :

- Le défaut de la caméra (sondes de sphère qui pénètrent de 2 à 4 mm) ne
  se retrouve pas tel quel dans le personnage. Le cylindre s'arrête bien
  avant le mur. En revanche, la capsule pénètre (2,5 mm), ce qui est
  cohérent avec l'imprécision des formes arrondies. Aucune marge de la
  caméra n'a été recopiée.
- Le défaut dominant était la **marge de sécurité par défaut (1 mm)**,
  trop grande pour un corps de 6 mm de haut : vibration contre les murs,
  et hauteur de repos variable entre 0 et 0,94 mm (le « saut » au joint).
- **Point de fragilité :** 0,1 mm bloque complètement le corps. 0,2 mm
  est le meilleur réglage mesuré, mais il est proche de cette limite. Ne
  pas descendre plus bas ; revalider si le moteur physique ou sa version
  change.

## Paramètres de locomotion (exportés sur `PlayerMotor`)

| Paramètre | Valeur | Mesuré |
|---|---|---|
| `walk_speed` | 0,08 m/s | 80,00 mm en 1 s |
| `sprint_speed` | 0,16 m/s | 160,00 mm en 1 s |
| `accel_time` | 0,1 s | vitesse atteinte en 6 ticks (0,100 s) |
| `stop_time` | 0,08 s | arrêt en 5 ticks (0,083 s) |
| `gravity` | 9,8 m/s² | chute de 4 cm en 5 ticks (théorie 5,4) |
| `turn_speed` (visuel) | 12 rad/s | demi-tour du visuel en ≈ 0,26 s |

- Direction : `move_vector` (x droite, y avant) tournée par le **lacet**
  de `CameraRig` uniquement. Le tangage n'intervient pas : 4 lacets × 3
  tangages donnent la même distance.
- Diagonale : vecteur d'entrée limité à 1, donc vitesse égale à la vitesse
  axiale (0,16000 m/s).
- Accélération et freinage linéaires. Le freinage part de la vitesse
  courante, ce qui donne toujours 0,08 s, quelle que soit la vitesse.
- Gravité seulement hors du sol ; `move_and_slide()` gère le glissement le
  long des murs et le maintien sur les pentes.
- Visuel : tourne vers la vitesse réelle, seulement quand une direction est
  demandée. Tourner la caméra à l'arrêt ne le fait pas tourner.

## Ordre de mise à jour (par tick physique)

| Priorité physique | Nœud | Action |
|---|---|---|
| −2 | `PlayerInput` | rafraîchit `move_vector` et `sprint_held` |
| −1 | `PlayerMotor` | se déplace avec le lacet de la caméra (celui du tick précédent) |
| 0 | `CameraRig` puis son `SpringArm3D` | lit le regard, se place sur le joueur, mesure l'obstacle |
| — | `CameraRig._process` | place la caméra à la distance permise |

Vérifié : le pivot de la caméra est sur le joueur à chaque tick (écart
0,000000 mm), et le déplacement ne fait pas tourner la caméra.

## Corrections faites pendant l'intégration

1. **Latence d'entrée dépendante du rendu.** `PlayerInput` ne se
   rafraîchissait que dans `_process`. Les ticks physiques précédant
   `_process` dans une image lisaient l'intention de l'image précédente.
   Avec rendu réel à environ 25 images/s, la distance après 90 ticks
   variait de 1 à 3 ticks (−2,7 à −8 mm). Correction : rafraîchissement
   aussi dans `_physics_process`, en priorité −2. Résultat : 0,233332 m
   identique à 20, 45 et 120 images/s en rendu, et avec 30 à 217 images
   en headless.
2. **Respiration de la caméra dans les passages.** Dans un passage de
   section constante, la distance caméra oscillait de 31,7 à 38,7 mm, avec
   des sauts jusqu'à 5,6 mm par tick. Cause : le bruit de mesure du bras
   (imprécision des sondes, tâche C), suivi fidèlement par un retour à
   0,3 m/s. Correction dans `CameraRig`, sans toucher au rapprochement
   immédiat :
   - retour proportionnel à l'écart (`return_smoothing` = 0,15 s),
     toujours plafonné à `return_speed` ;
   - cible de retour = distance libre minimale des 10 derniers ticks
     (`return_window_ticks`).

   Résultat : au plus 0,47 mm par tick (il y avait 5,6 mm). Les tests C
   passent toujours (retour progressif, distance complète en moins de
   1,5 s).
3. **Pause sous un parent `ALWAYS`.** `PlayerMotor` force
   `PROCESS_MODE_PAUSABLE` : le corps s'arrête en pause, même instancié
   sous un nœud qui tourne toujours (ce que faisait le test).
4. **Panneau :** il affiche 0 m/s pendant la pause au lieu de la vitesse
   mémorisée.

## Parcours `movement_test.tscn`

Sol de 2 × 2 m, en deux dalles coplanaires jointes en z = 0. Lumière
principale, lumière d'appoint sans ombre et ambiance plus claire que
`scale_test`, qui n'est pas modifiée.

| Bouton | Départ | Élément testé |
|---|---|---|
| Depart | (0 ; 0 ; 0,8), vers −Z | ligne droite graduée tous les 10 cm (repères jaunes), traverse le joint |
| Mur | (0,555 ; 0 ; 0,6) | mur latéral, face en x = 0,58 |
| Coin | (0,45 ; 0 ; −0,75), yaw −45° | coin intérieur (x = 0,58, z = −0,9) |
| Pente | (−0,5 ; 0 ; 0,9) | rampe de 25° vers un plateau de 4 cm |
| PenteRaide | (−0,8 ; 0 ; 0,9) | rampe de 50° vers un bloc de 5 cm |
| Joint | (0 ; 0 ; 0,1) | joint coplanaire en z = 0 |
| SousMeuble | (−0,5 ; 0 ; −0,15) | caisson sur pieds, dessous à 10 cm |
| Passage | (0,3 ; 0 ; −0,05) | passage de 5 cm × 3 cm × 30 cm (corps de 2 cm de diamètre, 8 mm de haut) |
| Bord | (−0,5 ; 0,04 ; 0,6) | bord du plateau : chute de 4 cm |

Un bouton de position est un **retour de diagnostic**, pas une mort ni une
sauvegarde : position, vitesse à zéro, caméra recalée derrière.

Lancer :

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/tests/movement_test.tscn        # interactif (F6)
$G --headless --fixed-fps 60 --path . res://scenes/tests/movement_test_runner.tscn   # 47/47
# Indépendance au rendu (temps réel, comparer les distances) :
$G --headless --path . res://scenes/tests/movement_test_runner.tscn -- --render-check=20
$G --headless --path . res://scenes/tests/movement_test_runner.tscn -- --render-check=240
# Comparaison de formes ou de marges :
$G --headless --fixed-fps 60 --path . res://scenes/tests/movement_test_runner.tscn -- --shape=capsule --margin=0.0002
# Séquences rendues :
$G --fixed-fps 60 --path . res://scenes/tests/movement_capture.tscn -- --out=/tmp/mv
# Régénérer le parcours après modification :
python3 tools/gen_movement_test.py
```

Commandes : ZQSD/WASD, Maj pour le sprint, souris pour la caméra. Échap
libère la souris ; on clique sur une position, puis Échap pour reprendre.

## Tolérances des tests (corps de 3 cm)

| Mesure | Tolérance | Justification |
|---|---|---|
| Distance en 1 s | ± 1 mm | Simulation déterministe ; 1 mm vaut environ 1 % |
| Montée / arrêt | ± 1 tick | Granularité de la physique à 60 Hz |
| Poussée contre un mur | écart entre −0,5 et +2 mm | Pas de pénétration visible ; pas de vide visible |
| Vibration (mur, coin, repos) | < 0,1 mm | En dessous de tout effet visible |
| Joint | vitesse ≥ 99 %, bosse < 0,1 mm | Aucun accrochage perceptible |
| Pente 50° | hauteur atteinte < 3 mm | La moitié de la hauteur du corps |
| Repos après une chute | au sol, entre 0 et `safe_margin` au-dessus | Hauteur d'équilibre d'un CharacterBody3D |
| Caméra dans le passage | < 2 mm par tick | Fixé avant la mesure ; mesuré 0,47 mm |

## Limites

- Le cap du déplacement utilise le lacet de la caméra du tick précédent
  (16 ms de retard sur la direction seulement).
- La vitesse est conservée pendant la pause. Après une perte de focus, la
  reprise sans touche produit un freinage normal de 0,08 s, soit environ
  2 mm de glissement.
- Tête et queue du visuel dépassent de 5 mm de la collision : face à un
  mur, elles peuvent entrer dans le mur. À revoir avec le modèle définitif.
- En chutant du plateau, la caméra se rapproche brusquement (bord du
  plateau derrière le joueur), puis s'éloigne progressivement. À juger en
  confort.
- Rendu logiciel seulement : aucune mesure de performance.
