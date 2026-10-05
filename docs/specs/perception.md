# Spec — Perception limitée et détection

Bible §4, système prioritaire n° 4. Partie A : comportement de *Les Fourmis* (Empire of the Ants, UE 5.4),
mesuré ou lu en jeu (`reverse/data/perception_baseline.txt`, `p1_*`, `p2_*`). Partie B : proposition pour
COCKROACH (humains, suspicion 0-100), qui s'appuie sur A mais **n'est pas** une mesure.

Conventions : 1 u = 1 cm moteur ; corps de la fourmi joueur R = 14 u. Confiance : **M** mesuré, **P** paramètre
lu en jeu, **I** inféré, **D** décision de design (partie B).

---

## A. Ce que fait Les Fourmis

### A.1 Résumé

La perception de Les Fourmis est **entièrement fondée sur la distance**, en sphères et en bandes. On n'a observé
ni cône de vision, ni ligne de vue, ni discrétion liée à la vitesse ou à la lumière (M, P : aucun paramètre de
ce type dans les classes du jeu). Elle a trois couches :

1. **Les unités détectent d'autres unités** dans une sphère (combat d'armées).
2. **Les zones de danger** autour des unités hostiles blessent le joueur, sans que celles-ci le « voient »
   ni le poursuivent.
3. **La perception du joueur** : un sonar d'antennes gradué de froid à brûlant pour les objets cachés, un
   « sixième sens » par impulsions, et des sphères d'interaction.

### A.2 Détection entre unités

| Paramètre | Valeur | ×R | Conf. |
|---|---|---|---|
| Portée de détection d'une unité | **1500 u** | 107 R | P `CoreStats.DetectionRange`, M (toutes les unités en mission) |
| Portée de détection du joueur (par les unités) | 1500 u | 107 R | P `PlayerDetectionRange` |
| Facteur des créatures (« creeps ») | ×2 → 3000 u | 214 R | P `CreepsDetectionRangeFactor` |
| Agressivité spontanée | fourmis / termites : 1 ; créatures, gardes, pucerons : **0** | — | P `AggroRadiusFactor` (UnitStats) |
| Délai de détection par clan | **0 s** (instantané) ; modificateur de portée ×1 | — | P `ClansSetup.DetectionTime / DetectionRangeModifier` |
| Rayon de combat (`fight_radius`) | 240 (gardes) / 330 (termites) / 390 (guerrières) / **540 (essaim de gendarmes)** | 17-39 R | M |
| Fin de combat | 3 s sans contact | — | P `UnitBreakFightDuration` |

Les états de comportement mesurés sont `Idle, Patrol, Chase, Fight, AttackNest, Die…`. Les transitions vers
`Fight` sont déclenchées par la présence d'unités adverses, pas par le joueur (M, P1 : `chased_general` reste
« aucun » pendant tout l'enregistrement).

### A.3 Zones de danger pour le joueur

| Paramètre | Valeur | Conf. |
|---|---|---|
| Zone rouge (dégâts) | **rayon de combat × 1,0** : essaim de gendarmes ≈ 540 u (dégâts dès 394-638 u du centre, médiane 512 ; fin vers 577) | M (P2), P `CreepRedZoneRatio=1` |
| Zone jaune (avertissement) | rayon de combat × 2,5 (≈ 1350 u pour l'essaim) | P `CreepYellowZoneRatio=2.5` (I : affichage) |
| Réaction de la créature | **aucune** : l'essaim reste en patrouille à 1134, 984, 675, 469 u du joueur | M (P2) |
| Temps d'exposition pour mourir | 45 s d'exposition continue (17,3 s cumulées mesurées sans mourir) | P `EnemyUnitSecondsToKill`, M |
| Régénération complète | 60 s | P `SecondsToFullyHeal` |
| Réapparition | 5 s (+ animation de mort 2 s, fondu 0,6 s) | P |
| Dégâts / s (unités hostiles, créatures) | 5 %/s ; 20 %/s | P (unités internes, non isolées) |

Les dégâts sont **intermittents** près du bord de la zone : les individus de l'essaim bougent autour du centre
du groupe (M : 6 alternances début/fin entre 394 et 649 u).

### A.4 Perception du joueur (« antennation »)

| Paramètre | Valeur | ×R | Conf. |
|---|---|---|---|
| Sonar d'objets cachés : froid / tiède / chaud / très chaud / brûlant | **2000 / 1500 / 1000 / 750 / 250 u** | 143 / 107 / 71 / 54 / 18 R | P (`SimulatedLevel.*DetectionDistance`, niveau de mission) |
| États du sonar | `Directional → ProximityFar → MediumIsh → Medium → CloseIsh → Close` | — | P (enum `ECollectibleDetectState`) |
| « Sixième sens » | 5 impulsions, une toutes les 2 s | — | P `SpideySenseTickNumber/Interval` |
| Sphères d'interaction | nid 200 u ; ressource / fourragement 400 u ; barrière 40 u | 14 / 29 / 3 R | P |
| Écoute des colonnes ambiantes (le joueur est « entendu ») | 500 u | 36 R | P `PlayerHearingRange` |

Effets visuels associés (P, I) : post-process « antennation » et « vision nocturne », désaturation, et une
« paroi » de détection directionnelle dont l'épaisseur varie selon la bande.

---

## B. Proposition pour COCKROACH (D)

La Bible demande une **détection réaliste** (« un cafard peut passer loin sans être vu ») et une
**suspicion humaine 0-100** qui déclenche une escalade. Les Fourmis n'a que des sphères. On garde sa
**structure** (portée maximale, bandes, zones rouge/jaune, temps d'exposition, régénération) et on ajoute ce
qu'un humain a de plus qu'une fourmi : un **regard**, la **ligne de vue** et la sensibilité au **mouvement**.

### B.1 Perception d'un humain, par image

```
d     = distance(tête humaine, cafard)
if d > range_max: visible = 0
los   = raycast(tête → cafard) libre ?          // occlusion : meubles, dessous de table, interstices
angle = angle(regard, direction du cafard)
f_dist  = smoothstep(range_max, range_near, d)   // 0 au-delà de range_max, 1 en deçà de range_near
f_cone  = angle < cone_focus/2 ? 1 : angle < cone_peripheral/2 ? peripheral_gain : 0
f_move  = clamp(speed / speed_ref, idle_floor, 1)   // immobile = presque invisible
f_light = luminosité locale (1 = plein jour), via sondes ou zones
f_surf  = 1 (sol), mur_gain (murs), plafond_gain (plafond : contraste sur fond clair)
visible = los * f_dist * f_cone * f_move * f_light * f_surf
suspicion += visible * gain * dt
if visible == 0: suspicion -= decay * dt après un délai de grâce
```

### B.2 Réglages de départ (à ajuster au prototype)

| Paramètre | Valeur de départ | Justification |
|---|---|---|
| `range_max` | 107 R (≈ 1,1 m pour R = 1 cm) | = portée de détection de Les Fourmis (1500 u / 14) |
| `range_near` | 18 R | = bande « brûlante » du sonar (250 u) |
| `cone_focus` / `cone_peripheral` | 30° / 120°, `peripheral_gain = 0,3` | vision humaine, fovéa et périphérie |
| `speed_ref` / `idle_floor` | vitesse de course (50 R/s) / 0,05 | immobile = quasi invisible (Bible : se cacher) |
| `gain` | 100 / 1,5 s | un cafard en pleine lumière, au centre du regard, qui court, est repéré en 1,5 s |
| `decay`, délai de grâce | 8 /s après 3 s | la suspicion retombe lentement (régénération 60 s dans Les Fourmis) |
| Seuils | **30 = remarque** (tourne la tête), **60 = cherche** (se déplace vers la dernière position), **100 = détecté** (escalade, Bible §1) | — |
| Zone rouge (écrasement) | pied de l'humain : 3 R, uniquement si suspicion ≥ 60 | équivalent de la zone rouge = rayon de combat |
| Zone jaune (avertissement HUD) | 2,5 × zone rouge | `CreepYellowZoneRatio` |

### B.3 Perception du cafard (antennes)

On reprend le sonar de Les Fourmis pour les ressources et les dangers : **bandes à 143 / 107 / 71 / 54 / 18 R**,
retour visuel et sonore croissant, impulsion toutes les 2 s. Les humains, eux, sont « sentis » par les
vibrations dans la zone jaune.

### B.4 Critères d'acceptation (prototype)

1. Un cafard immobile dans l'ombre, à 50 R, dans le champ central, n'atteint pas 30 en 10 s.
2. Un cafard qui court en pleine lumière à 30 R, dans le champ central, atteint 100 en moins de 2 s.
3. Un cafard derrière un obstacle (ligne de vue bloquée) n'augmente jamais la suspicion.
4. Hors du cône périphérique (dans le dos de l'humain), la suspicion n'augmente pas.
5. La suspicion retombe de 60 à 0 en moins de 15 s une fois le cafard caché.

Sources : `reverse/data/perception_baseline.txt`, `reverse/data/p1_*`, `reverse/data/p2_*`,
`reverse/analysis/analyze_units.py`, `reverse/data/NOTES.md`.
