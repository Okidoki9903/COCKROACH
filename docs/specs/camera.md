# Spec — Caméra 3e personne à hauteur d'insecte

Bible §4, système prioritaire n° 1. Spec **indépendante du moteur**, reconstruite à partir de mesures runtime
sur *Les Fourmis* (Empire of the Ants, UE 5.4) — voir `reverse/data/` et `reverse/analysis/`.
Aucun code du jeu n'a été copié : ce document décrit un comportement observé et des paramètres mesurés.

Conventions :
- Unités du jeu mesuré : **1 u = 1 cm moteur**. Le corps de la fourmi a un rayon de collision **R = 14 u**.
  Chaque longueur est aussi donnée en **multiples de R** pour pouvoir la transposer au cafard
  (voir §8).
- Repère monde « Z en haut ». Angles en degrés sauf mention.
- Niveau de confiance : **M** = mesuré (CSV), **P** = paramètre lu dans le jeu (`reverse/data/params_baseline.txt`),
  **I** = inféré (cohérent avec les mesures mais non observé directement).

---

## 1. Résumé du comportement (ce qui fait le « feeling »)

1. La caméra est une **orbite libre pilotée par le joueur**, en repère **monde** : yaw et pitch ne bougent que
   sous l'action du stick droit / de la souris. Elle **ne se replace jamais toute seule** derrière l'insecte,
   même quand il marche vers elle (M, cas 1-2-4).
2. Elle **ne tourne pas avec la surface** : quand l'insecte monte sur un mur ou marche au plafond, l'orientation
   de la caméra et son « haut » restent ceux du monde (roll = 0). Seul le **point visé** suit l'insecte (M, cas 5).
3. Le point visé est **20 u au-dessus de l'insecte le long de SA normale** (son « haut »), pas du haut monde (M).
4. Le suivi en translation est retardé par une **laisse** : un point de suivi rappelé vers l'insecte avec une
   vitesse qui croît plus vite que la distance (loi de puissance), borné par une longueur de laisse (M, §3).
5. La caméra est **très basse** et en **très grand angle** (focale 12 mm, plan proche 5 u) : au repos elle regarde
   presque à l'horizontale, ~2-13° vers le bas selon le pitch choisi (M).
6. Collision : la caméra **rentre instantanément** devant un obstacle et **ressort à vitesse constante**
   200 u/s (M, cas 4-5).

---

## 2. Orientation (yaw / pitch)

| Paramètre | Valeur | ×R | Conf. |
|---|---|---|---|
| Vitesse angulaire max (stick à fond) | **180 °/s** | — | M (médiane p90 = 180,2 °/s), P `RotationSpeed=180` |
| Vitesse en visée | 140 °/s | — | P `AimRotationSpeed` |
| Réglage joueur « vitesse caméra » | 50 (sur 100) ↔ 180 °/s | — | M (options) |
| Pitch min / max | **−86° / +86°** | — | M, P `MaxPitchAngle=86` |
| Roll | **0** toujours (haut caméra = haut monde) | — | M (cas 5, jusqu'à 171° d'inclinaison du corps) |
| Lissage de la rotation | **aucun** | — | M : démarre en 2-3 images (course physique du stick), s'arrête en 1 image |

Algorithme (par image, `dt` en s, stick droit `s = (sx, sy)`, |s| ≤ 1 après deadzone circulaire) :

```
ω = RotationSpeed * sensitivity_scale            // 180 °/s pour le réglage 50
yaw   += sx * ω * dt
pitch += sy * ω * dt                             // signe selon préférence d'inversion
pitch  = clamp(pitch, -86°, +86°)
cam_rot = rotation_monde(yaw, pitch, roll = 0)  // jamais dérivée de l'orientation de l'insecte
```

Note : la norme de la vitesse angulaire combinée vaut 180 °/s en diagonale (ex. 151 °/s en yaw + 98 °/s en
pitch). Le stick est donc traité comme un **vecteur circulaire**, sans normaliser chaque axe séparément (M).

Souris (I) : même modèle avec un gain en °/pixel (non mesuré, la session a été faite à la manette).

---

## 3. Position : pivot, laisse, bras

### 3.1 Pivot (point visé)

```
T = pawn_position + LocationOffset_z * pawn_up       // LocationOffset_z = 20 u (1,43 R)
```
- `pawn_up` = normale courante de l'insecte (celle du système de mouvement, cf. `surface-movement.md`).
  Vérifié au sol, sur mur et sous un rocher : la hauteur caméra mesurée est cohérente avec ±20 u le long de
  `pawn_up` (M, cas 5).
- En visée : `AimLocationOffset_z = 85 u` (P), non mesuré.

### 3.2 Point de suivi retardé (la laisse)

Le point `F` suit `T` en 3D :

```
e = T - F ; d = |e|
if d > 0:
    step = min(d, A * d^P * dt)          // vitesse de rappel croissant plus vite que d
    F += e/d * step
// laisse : borne dure
e = T - F ; d = |e|
L = (mode == Run) ? L_run : (aim ? L_aim : L_walk)
if d > L:  F = T - e/d * L
```

| Paramètre | Valeur ajustée | Conf. |
|---|---|---|
| A (gain de rappel) | **2,6** (u^(1−P)/s) | M (ajustement, `reverse/analysis/fit_leash.py`) |
| P (exposant) | **1,2** | M (fit direct à l'arrêt : 1,29-1,36 ; fit global : 1,2) |
| L_walk (laisse marche / repos) | **25-30 u** (1,8-2,1 R) | M (fit 25), P `BaseLeashLength=30` |
| L_run (laisse course) | **75 u** recommandé (5,4 R) ; valeur jeu 100 u | P `RunLeashLength=100`, M (excès max observé 73 u ; le prototype atteint 94 u avec 100) |
| L_aim (laisse visée) | 15 u | P `AimLeashLength` |

Vitesse de rappel équivalente : `v_rappel(d) = 2,6·d^1,2` → 6 u/s à d = 2, 46 u/s à d = 11, 125 u/s à d = 25,
470 u/s à d = 70. Ça donne les excès en régime établi mesurés : **+11 u à 53 u/s**, **±26 u à 180 u/s**
(marche stick à fond), **±65-73 u en course à 700 u/s**. Après un arrêt, le retour est quasi exponentiel avec
**τ ≈ 0,33 s pour un petit excès et 0,5 s pour un grand** (M).

Qualité du modèle (erreur de position caméra, 90ᵉ percentile, hors collision) : 0,3 u (marche), 1,8 u (marche
rapide), 4,7 u (course), 2,6 u (mur/plafond), 6,1 u (manipulations sur paroi), contre 11 à 60 u pour un suivi
sans retard (M).

Les autres paramètres de laisse du jeu (`BaseLeashRetractSpeed=150`, `RunLeashRetractSpeed=600`,
`FollowSmoothnessStart=0,1`, `FollowSmoothnessDistanceFactor=0,1`, `TransitionSpeed=600`) n'ont pas été
isolés individuellement. La loi A·d^P ci-dessus reproduit leur effet combiné (I). Pour la transition entre
L_walk et L_run, faire varier L à `TransitionSpeed ≈ 600 u/s` (I).

### 3.3 Bras

```
arm_target = ArmLength[setting]          // 150 / 300 / 500 u  (10,7 / 21,4 / 35,7 R), défaut 300
cam_desired = F - cam_forward * arm_target
```
- Au repos, la caméra est **exactement** à `T − cam_forward·300` (écart latéral 0,01 u, M).
- Le joueur change de distance par un bouton (clic du stick gauche / touche M) parmi les 3 valeurs (M options, P).
- `ArmLengthMinValueForNearBlur = 100` : flou de premier plan désactivé sous 100 u (P, I).

---

## 4. Collision et occlusion

| Paramètre | Valeur | Conf. |
|---|---|---|
| Rayon de la sphère caméra | **8 u** (0,57 R) | P `CameraSphereRadius`, M (la caméra s'arrête 6 u sous le pivot, au ras du sol) |
| Rentrée devant un obstacle | **instantanée** (même image) | M (300 → 52 u en une image) |
| Ressortie quand c'est libre | **200 u/s, vitesse constante** | M (167→217→267→317 par pas de 0,25 s), P `ZoomoutSpeed=200` |
| Distance min observée | 6,3 u (pivot collé au sol) | M |
| Occlusion (I) | 12 rayons sur un cercle de rayon 40 u | P `OcclusionTestCount`, `OcclusionCircleRadius` |

Algorithme :
```
hit = sphere_cast(from = T, to = cam_desired, radius = 8)
allowed = hit ? hit.distance : arm_target
if allowed < arm_current:  arm_current = allowed                          // instantané
else:                      arm_current = min(allowed, arm_current + 200*dt) // ressortie lente
camera_position = T + normalize(cam_desired - T) * arm_current
```
(Le cast part de `T`, et non de `F`, pour ne jamais placer la caméra derrière un mur à cause du retard : I.)

Masquage de l'insecte quand la caméra est trop proche (P) : fondu sur 0,2 s si distance caméra-insecte
< 50 u (70 u en visée).

---

## 5. Optique

| Paramètre | Valeur | Conf. |
|---|---|---|
| FOV horizontal | **90°** (réglage joueur 90, `DefaultFOV=90`) | M (`GetFOVAngle`), M options |
| Focale CineCamera | 12 mm (très grand angle) | M, P `CurrentFocalLength` |
| Plan de coupe proche | **5 u** (0,36 R) | P `CustomNearClippingPlane=5` |
| Ouverture / DOF | f/5 standard, f/15 visée ; mise au point 250 u au repos | P (non mesuré visuellement) |
| Ratio | 16:9 contraint | P |

Le plan proche à 5 u est **indispensable** : la caméra passe régulièrement à moins de 10 u des surfaces
(collision, coins).

---

## 6. Ce qui N'existe PAS (à ne pas implémenter si on veut le même feeling)

- Pas de recentrage automatique derrière l'insecte (ni au démarrage, ni en course).
- Pas d'inclinaison (roll) ni de rotation de l'horizon sur les murs et plafonds.
- Pas de lissage ni d'inertie sur la rotation au stick.
- Pas de changement de FOV avec la vitesse (FOV constant à 90° en marche comme en course, M).

---

## 7. Critères d'acceptation (tests à reproduire dans le prototype)

1. Repos au sol, pitch −2,5° : caméra à 300 u du pivot, 32,9 u au-dessus de l'insecte (20 + 300·sin 2,47°).
2. Marche en ligne droite à 53 u/s en s'éloignant de la caméra : excès de distance stable de +11 ± 1 u ;
   après l'arrêt, retour à < 1 u en ~1 s.
3. Stick droit à fond pendant 1 s : 180 ± 5° de rotation ; relâché, arrêt en 1 image.
4. Pitch bloqué à ±86°. À −86°, caméra 319,3 u au-dessus de l'insecte.
5. Monter sur un mur : orientation caméra inchangée, horizon droit.
6. Regarder vers le haut (pitch > 0) au sol : la caméra rentre sans traverser le sol, puis ressort à 200 u/s.

---

## 8. Transposition au cafard (Rust / Bevy)

- **Échelle** : exprimer tout en multiples du rayon du corps R. Pour un cafard de rayon `R_c` (unités du projet,
  1 u = 1 cm selon la Bible), multiplier chaque longueur du tableau « ×R » par `R_c`. Garder les vitesses
  angulaires telles quelles. Les vitesses linéaires se mettent à l'échelle par `R_c / 14`, et la loi de
  laisse devient `v = 2,6 · (R_c/14)^(1−1,2) · d^1,2` (A dépend de l'unité, car P ≠ 1).
- **Repères** : UE est gaucher (X avant, Y droite, Z haut) ; Bevy est droitier (Y haut, −Z avant).
  Conversion : `bevy = (ue.y, ue.z, −ue.x) × échelle`.
- **Ordre des systèmes** (par frame, après la physique du joueur) :
  `read_input → orbit_yaw_pitch → pivot(T) → leash(F) → arm_collision → write Transform + Projection`.
- **Composants suggérés** : `OrbitCamera { yaw, pitch, arm_setting, arm_current }`,
  `LeashFollow { point: Vec3, a: f32, p: f32, l_walk, l_run }`, `CameraCollision { radius: 8.0×s, zoom_out_speed }`.
- FOV : `PerspectiveProjection { fov: vertical(90° horizontal, aspect), near: 5×s }`. Attention, Bevy prend un
  FOV **vertical** : `fov_v = 2·atan(tan(45°)/aspect)` ≈ 58,7° en 16:9.

Sources : `reverse/data/c1..c6*.csv`, `reverse/data/params_baseline.txt`, `reverse/data/NOTES.md`,
`reverse/analysis/analyze_frames.py`, `reverse/analysis/fit_leash.py`.
