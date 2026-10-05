# Notes de mesures — Empire of the Ants (UE 5.4)

Réglages du joueur pendant les mesures (menu Options) : manette Xbox ; vitesse caméra 50 ; vitesse
caméra en visée 30 ; pivot mode visée = Personnage ; champ de vision 90 ; VSync 60 i/s ;
distance caméra = moyenne (ArmLength2 = 300, change avec clic stick gauche / M).
Commandes manette : stick G = se déplacer (vitesse ∝ inclinaison), B = sprint (maintenir),
Y = saut (maintenir et relâcher), LT = viser, stick D = caméra.

| Fichier | Cas | Résumé |
|---|---|---|
| c1_walk_straight.csv | marche stick à mi-course, arrêt | 53 u/s, accél 0,05 s, laisse +11, τ retour 0,50 s |
| c2_run_straight.csv  | marche stick à fond (B pas appuyé) | 180 u/s (= WalkSpeed), laisse +26 / -24, τ 0,46 s |
| c3_run.csv           | sprint B + sauts | 670 u/s croisière (max 726), accél ~0,9 s ; sauts 560-660 u/s |
| c4_camera_rotate.csv | stick droit | 180 °/s (norme yaw+pitch), pas de lissage, pitch ±86°, pivot +20, bras 300, collision sol, ressortie 200 u/s |
| c5_ground_to_wall.csv | sol → mur → dessous de rocher (jusqu'à 171° = quasi tête en bas) → retour sol | caméra NE tourne PAS avec la surface (yaw/pitch/roll monde constants) ; pivot = pawn + 20·up_pawn ; bascule up ≈ 450-500 °/s en pic, ~5°/u parcouru (arc ≈ 11-14 u ≈ rayon du corps) ; vitesse non réduite sur mur/plafond (≈170-180 u/s stick à fond) ; collision caméra en espace serré : dist jusqu'à 30, ressortie 200 u/s |
| c6_wall_stick_dirs.csv | stick haut/droite/bas/gauche sur paroi (+ sauts) | stick interprété à l'écran puis projeté sur la paroi ; avant du corps = direction (0,98-1,00) ; sauts charge complète 660-690 u/s à 30-38° du plan ; gravité 961-980 u/s² |

## Perception (5 octobre 2026)

| Fichier | Cas | Résumé |
|---|---|---|
| perception_baseline.txt | F10 hub + mission | DetectionRange = PlayerDetectionRange = 1500 u ; créatures ×2 ; AggroRadiusFactor 1 (fourmis/termites) / 0 (créatures) ; écoute colonnes ambiantes 500 u ; sonar 2000/1500/1000/750/250 u ; DetectionTime 0 |
| p1_*_army_fight.csv | approche des ennemis | les termites combattent les armées du joueur, jamais le joueur (chased_general = 10 = aucun) |
| p2_*_swarm_danger.csv | approche d'un essaim de gendarmes (fight_radius 540) | aucune réaction de l'essaim (Patrol) à 1134/984/675/469 u ; dégâts au joueur dès ~512 u du centre (394-638), arrêt ~577 u ⇒ zone rouge = fight_radius × 1,0 ; 17,3 s cumulées sans mourir (EnemyUnitSecondsToKill = 45 s) |
