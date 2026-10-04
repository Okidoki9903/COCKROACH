# Spec — Mouvement multi-surfaces (sol, murs, plafond, dessous des objets)

Bible §4, système prioritaire n° 2 (et n° 3 : échelle et vitesses). Spec **indépendante du moteur**, reconstruite
à partir de mesures runtime sur *Les Fourmis* (Empire of the Ants, UE 5.4). Aucun code du jeu n'a été copié.

Conventions : 1 u = 1 cm moteur ; rayon du corps **R = 14 u** ; « up » = normale courante de l'insecte.
Confiance : **M** = mesuré (CSV `reverse/data/`), **P** = paramètre lu en jeu (`reverse/data/params_baseline.txt`),
**I** = inféré (cohérent avec les mesures, non observé directement).

---

## 1. Résumé du comportement

1. L'insecte **colle à toute surface**, quelle que soit son orientation : sol, mur vertical, dessous d'un rocher
   (mesuré jusqu'à **171°** entre son up et le haut du monde, donc quasiment tête en bas). Il n'y a **aucun
   ralentissement** sur les murs ou au plafond (M, cas 5-6).
2. Son « up » se **réaligne en continu** sur la normale de la surface sous lui. Sur une arête, il **s'enroule** :
   environ 5° par unité parcourue, soit un arc de rayon ≈ R. Un passage sol → mur de 90° prend **~0,2 s**
   à 100 u/s (M).
3. La marche est **sans inertie** : vitesse proportionnelle à l'inclinaison du stick, atteinte en ≤ 0,05 s,
   arrêt en une image. La course a une **vraie accélération** (M).
4. Le stick est interprété **à l'écran** (repère caméra), puis projeté sur le plan de la surface. Sur un mur
   face caméra, stick haut = monter (M, cas 6).
5. L'insecte se **tourne toujours face à sa direction de déplacement** (M : avant·direction = 0,98-1,00).
6. En l'air, la gravité est **monde** (−Z, 980 u/s²) et l'up revient progressivement vers le haut du monde (M, P).

---

## 2. Échelle et vitesses (Bible §4.3)

| Grandeur | Valeur | En R/s ou ×R | Conf. |
|---|---|---|---|
| Rayon de collision du corps | **14 u** | 1 R | P `BodyCollisionRadius` |
| Marche, stick à fond | **180 u/s** (exactement, en régime établi) | 12,9 R/s | M (cas 2), P `WalkSpeed` |
| Marche, stick partiel | ∝ inclinaison (53 u/s observés à mi-course environ) | — | M (cas 1) |
| Accélération / arrêt en marche | **≤ 0,05 s** (10→90 % en 1 à 3 images) ; arrêt en 1 image | — | M |
| Course (bouton maintenu) | **700 u/s** (plafond exact ; 670 en moyenne sur terrain accidenté) | 50 R/s | M (cas 3), P `RunSpeed` |
| Accélération en course | **≈ 1000 u/s²** (0 → 350 u/s en 0,35-0,4 s ; 700 atteint en ~1,1 s) | 71 R/s² | M, P `RunAcceleration` |
| Endurance course | −5 %/s en course, +2,5 %/s au repos, reprise possible à 25 % | — | P |
| Vitesse sur mur / plafond | identique au sol (170-180 u/s stick à fond) | — | M (cas 5) |

À retenir pour le feeling « Toy Story » : en marche, l'insecte parcourt environ **13 fois son rayon par
seconde**. Le rapport course / marche vaut **3,9**.

---

## 3. Attachement à la surface (algorithme reconstruit)

### 3.1 Données d'entrée (P)

| Paramètre | Valeur | Rôle (I) |
|---|---|---|
| `CastSamples` | 32 | nombre d'échantillons (rayons) pour estimer la surface sous / devant le corps |
| `GroundedCastDistance` | 0,02 u | marge de contact (« skin ») pour déclarer le corps posé |
| `BlockerCastDistance` | 0,06 u | marge de détection d'obstacle devant le corps (déclenche la montée sur la paroi) |
| `BaseGroundUpInterpSpeed` | 2π rad/s (360 °/s) | vitesse de réalignement de l'up à l'arrêt |
| `WalkUpInterpSpeed` | 1,5π rad/s (270 °/s), min 0,3 | vitesse de réalignement de l'up en marche |
| `BaseGroundForwardInterpSpeed` | 3π rad/s | réorientation de l'avant à l'arrêt |
| `WalkForwardInterpSpeed` | 4,5π rad/s (810 °/s), min 0,05 | réorientation de l'avant en marche |
| `WalkSampleDuration` | 0,25 s | fenêtre de lissage de la direction de marche |
| `MaxWalkRotationSpeedBoost` | ×2,5 | accélération des rotations lors des changements de direction brusques |
| `AngularInertia` | π | inertie angulaire en course |

### 3.2 Boucle par image

```
// 1. Normale cible : moyenne des normales de surface échantillonnées autour du corps
hits = []
for i in 0..32:
    dir_i = direction d'échantillonnage i (hémisphère orienté vers -up, plus quelques rayons vers l'avant)
    hit = ray_or_sphere_cast(origin = p, dir = dir_i, length = R + skin)
    if hit: hits.push(hit)
grounded = any(hit.distance <= R + GroundedCastDistance)
n_target = normalize(Σ hit.normal · w_i)          // poids w_i : plus fort sous le corps (I)

// 2. Bloqueur devant : la paroi devient la nouvelle surface
if cast(p, forward, R + BlockerCastDistance) touche une paroi:
    n_target = normalize(n_target + wall.normal)   // l'up « bascule » vers la paroi (I)

// 3. Réalignement de l'up (interpolation exponentielle, rad/s)
k_up = moving ? max(WalkUpInterpSpeed * boost, 0.3) : BaseGroundUpInterpSpeed
up = slerp(up, n_target, 1 - exp(-k_up * dt))

// 4. Coller : projeter la position à distance R de la surface, le long de -up
p = closest_surface_point - (-up) * R             // pas de gravité tant que grounded
```

La moyenne de normales sur un **disque de rayon ≈ R** est ce qui produit le comportement mesuré : sur une arête,
la normale cible tourne progressivement quand le corps la franchit, ce qui donne **~5°/u, soit un arc de
rayon 11-14 u ≈ R** (M). Les pics de rotation de l'up atteignent **450-500 °/s** (M, max 775 °/s sur des
arêtes vives). Sur terrain irrégulier, l'up bouge en permanence (médiane 221 °/s quand il bouge, p90 446 °/s).

### 3.3 Critères mesurés à reproduire

| Situation | Mesure | Conf. |
|---|---|---|
| Sol → mur vertical (90°) à ~100 u/s | rotation de l'up en **0,15-0,25 s**, sur ~18-24 u de trajet | M (cas 5) |
| Mur → dessous de rocher (~120°) | 0,25 s à 95 u/s | M |
| Plafond maintenu | jusqu'à 171° d'inclinaison, sans chute, vitesse normale | M |
| L'insecte ne « décolle » pas sur une arête convexe | il suit l'arête (paroi fine franchie des deux côtés, cas 6) | M |

---

## 4. Contrôle : du stick à la direction sur la surface

```
// stick gauche m = (mx, my), |m| ≤ 1 (deadzone circulaire)
right_s = normalize(project_on_plane(cam_right, up))
fwd_s   = normalize(project_on_plane(cam_forward + cam_up, up))   // robuste pour toutes orientations
wish    = normalize(right_s * mx + fwd_s * my)                     // direction tangente
speed   = running ? run_speed_current : WalkSpeed * |m|           // marche ∝ inclinaison
velocity = wish * speed                                            // marche : sans inertie
```

Pourquoi `cam_forward + cam_up` : au sol, `cam_forward` projeté donne « devant » ; sur un mur face caméra,
`cam_forward` est presque normal au mur (projection nulle) mais `cam_up` projeté donne « haut du mur ».
Au plafond, avec une caméra horizontale, `cam_forward` projeté donne « devant ». La somme ne s'annule dans
aucun de ces cas. Ça reproduit ce qu'on a mesuré : sur paroi, stick haut → déplacement écran-haut avec un
alignement de +0,88 à +1,00 ; stick bas → −0,86 à −0,99 ; côtés → droite/gauche écran ±0,9 (M, cas 6).

Orientation du corps :
```
forward = slerp_on_plane(forward, wish, 1 - exp(-WalkForwardInterpSpeed * boost * dt))  // 810 °/s nominal
forward = normalize(project_on_plane(forward, up))
```
Mesuré : l'avant du corps reste aligné sur la vitesse (0,98-1,00) pendant toute la marche (M).

Course : `run_speed_current` tend vers 700 à 1000 u/s² tant que le bouton est maintenu et que l'endurance
le permet. `RunStickStrength=75` et `RunStick*Angle` (0 à π/2) réduisent la vitesse quand on braque fort en
course (P, I).

---

## 5. Air : saut, chute, décrochage

| Paramètre | Valeur | Conf. |
|---|---|---|
| Gravité | **980 u/s²**, monde −Z | P `GravityStrength`, M (950-980 sur 6 chutes) |
| Vitesse de chute max (verticale) | 2000 u/s | P |
| Vitesse horizontale max en l'air | 900 u/s | P |
| Freinage horizontal sans input | **≈ 400 u/s²** | P `FallHorizontalDampening`, M (≈ 393) |
| Contrôle en l'air | accélération 400 u/s², limité à ±30° de la direction | P `AirControlAcceleration`, `MaxAirControlAngle=π/6` |
| Réalignement de l'up en l'air | vers le haut du monde, π rad/s | P `AirUpInterpSpeed` |
| Inclinaison visuelle en l'air (course) | max 45° à partir de 600 u/s | P |

**Saut chargé** (maintenir puis relâcher le bouton) :

| Paramètre | Valeur | Conf. |
|---|---|---|
| Durée de charge complète | 0,5 s (charges mesurées 0,4-0,9 s) | P `JumpChargeDuration`, M |
| Vitesse de départ (charge complète) | **≈ 680 u/s** (660-690 mesurés), réglage 700 | M, P `JumpStrength` |
| Direction | vers l'avant du corps, **30-38° au-dessus du plan de la surface** (le long de up + forward) | M (6 sauts) |
| Charge partielle | vitesse réduite (0,4 s → ~576 u/s) | M |
| Rotation pendant la charge | 5 rad/s | P `JumpChargeTurnSpeed` |
| Coût en endurance | 10 % par saut complet | P |
| Limite d'angle de saut | 2,2 rad depuis le haut du monde | P `JumpClampAngle` (I : empêche de sauter « vers le bas ») |

```
on_jump_release(charge):
    s = JumpStrength * f(charge / 0.5)                 // f croissante, f(1) = 1 (I : linéaire saturée)
    dir = normalize(forward * cos(34°) + up * sin(34°))
    dir = clamp_angle_from(world_up, dir, 2.2 rad)
    velocity = dir * s ; mode = Jump → Fall
```

**Décrochage volontaire** (I, d'après les paramètres, non mesuré) : sur une surface où
`dot(up, world_up) < DropCosThreshold (0,1)`, donc un mur raide ou un plafond, une charge courte
(`DropChargeDuration = 0,15 s`) fait lâcher prise et tomber. `ForceDropMaxAngle = 0,3 rad` force la chute si
l'orientation devient intenable.

**Atterrissage** : quand un échantillon de l'étape 3.2 touche une surface, `grounded` repasse à vrai et l'up se
réaligne à `BaseGroundUpInterpSpeed`. Le mode repasse en marche ou au repos sans délai mesurable.

---

## 6. États (machine à états mesurée)

`Idle, Walk, Run, ChargeJump, Jump, Fall, Drop, FollowRail, Blocked, Drown` (M : Idle, Walk, Run,
ChargeJump, Jump et Fall observés).

- `Walk ↔ Idle` : instantané selon le stick.
- `Walk → Run` : bouton course maintenu (B à la manette, Maj au clavier).
- `* → ChargeJump → Jump (≈0,08 s) → Fall → Idle/Walk`.
- `Drown` : vitesse 100 u/s dans l'eau (P).

---

## 7. Transposition au cafard (Rust / Bevy)

- **Échelle** : poser `R_c` = rayon du cafard dans les unités du projet, et `s = R_c / 14`.
  Longueurs et vitesses linéaires × `s`, accélérations × `s`, gravité × `s` (pour garder les mêmes durées de
  saut), vitesses angulaires inchangées. Exemple pour R_c = 1,2 cm (1 u = 1 cm) : marche 15,4 cm/s,
  course 60 cm/s, gravité 84 cm/s². Cette gravité « à l'échelle du corps » est **voulue** : c'est elle qui donne
  la sensation de petit insecte vif. Si on préfère une gravité réelle (981 cm/s²), il faut aussi raccourcir les
  durées de saut.
- **Repères** : UE (X avant, Y droite, Z haut, gaucher) → Bevy (Y haut, −Z avant, droitier) :
  `bevy = (ue.y, ue.z, −ue.x)`.
- **Physique** : le mouvement est **cinématique** (pas de corps rigide dynamique). Utiliser des requêtes de scène
  (ray / shape casts, par ex. `avian3d` `SpatialQuery` ou `bevy_rapier3d` `QueryPipeline`) pour les 32
  échantillons, puis écrire directement `Transform`.
- **Ordre des systèmes** : `input → surface_probe (casts) → up_align → wish_dir (repère caméra) → integrate →
  snap_to_surface → facing → camera (camera.md)`.
- **Composants suggérés** : `SurfaceWalker { up, forward, grounded, mode, run_speed, stamina }`,
  `SurfaceProbeConfig { samples: 32, radius, skin, blocker_skin }`, `MoveTuning { …valeurs ci-dessus… }`.

## 8. Ce qu'il reste à mesurer (si besoin plus tard)

- Le décrochage volontaire au plafond (`Drop`) et l'atterrissage sur un mur après un saut.
- La réduction de vitesse en course quand on braque fort (`RunStick*`).
- La perception / détection (Bible §4.4) : hors périmètre de cette session.

Sources : `reverse/data/c1..c6*.csv`, `reverse/data/params_baseline.txt`, `reverse/data/NOTES.md`,
`reverse/analysis/analyze_frames.py --extras`.
