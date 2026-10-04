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
