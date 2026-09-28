# Décisions de production

| # | Décision | Raison | Statut |
|---|---|---|---|
| D1 | Godot 4 stable + GDScript, PC solo | Scènes et scripts textuels, itération compacte, développement assisté par IA | Proposée ; qualité visuelle à valider sur une scène représentative |
| D2 | 1 unité = 1 mètre ; cafard ≈ 3 cm | Proportions réelles des objets domestiques | Actée ; à éprouver pour collisions et caméra |
| D3 | Plan proche des caméras ≈ 1 mm | Le défaut Godot (5 cm) dépasse la taille du cafard | Actée (tâche A) |
| D4 | MVP = une portion de cuisine, un refuge, deux itinéraires | Tester le plaisir central avant toute extension | Actée |
| D5 | Contrôleur cinématique, pas de physique des pattes | Contrôle précis et stable | Actée, implémentation tâche D |
| D6 | Suspicion globale séparée de la détection immédiate | Éviter les échecs perçus comme arbitraires | Actée, implémentation tâches F et K |
| D7 | Aucun plugin externe au démarrage | Réduire les dépendances | Actée |
| D8 | Version fixée : Godot 4.7.2-stable (standard) | Dernière stable au 2026-09-28 ; import, exécution et rendu Forward+ validés | Actée |
| D9 | Ombres directionnelles réglées pour l'échelle millimétrique (biais 0,02, biais normal 0,5, distance 1,5 m) | Avec les valeurs par défaut, un objet de 6 mm ne projette aucune ombre visible | Actée ; à réévaluer avec la caméra mobile (tâche C) |
| D10 | Touches liées par position physique (WASD = ZQSD) | Une seule configuration pour QWERTY et AZERTY | Actée (tâche B) |
| D11 | Pause = `SceneTree.paused` ; perte de focus met en pause sans reprise automatique | Aucune intention bloquée, reprise volontaire | Actée (tâche B) |
| D12 | `move_vector` en espace écran : x = droite, y = avant | Séparer lecture des entrées et conversion 3D (tâche D) | Actée (tâche B) |
| D13 | Caméra : SpringArm3D en mesure seule ; caméra rapprochée immédiatement, retour à 0,3 m/s | Rapprochement sans traverser, retour sans à-coup ; testé | Actée (tâche C) |
| D14 | Sonde de 6 mm et marge de 3 mm appliquée par le rig | Compense l'imprécision mesurée de `cast_motion` à l'échelle du mm | Actée ; à revoir si l'origine de l'imprécision est trouvée |
| D15 | Rotation appliquée dans `_physics_process` | Le bras mesure toujours l'orientation courante | Provisoire ; à revoir si saccades constatées au-delà de 60 Hz |
| D16 | Capture souris dans `PauseController` (`capture_mouse`) | Une seule logique de pause ; aucune reprise automatique | Actée (tâche C) |
| D17 | Collision du joueur : cylindre vertical de 10 × 8 mm, qui ne tourne jamais | Mesuré le plus stable (47/47) ; la capsule pénètre de 2,5 mm | Actée (tâche D) |
| D18 | `safe_margin` du joueur = 0,2 mm | 1 mm fait vibrer contre les murs ; 0,1 mm bloque le corps | Actée ; revalider à tout changement de moteur physique |
| D19 | Marche 0,08 m/s, sprint 0,16 m/s, montée 0,1 s, arrêt 0,08 s | Valeurs de départ vérifiées ; confort à juger | Provisoire |
| D20 | `PlayerInput` rafraîchi aussi en physique (priorité −2) | Supprime une latence dépendante de la fréquence de rendu | Actée (tâche D) |
| D21 | Retour caméra lissé (0,15 s) et fenêtré (10 ticks) | Supprime la respiration de la caméra dans les passages | Actée (tâche D) |
| D22 | Portion de cuisine d'environ 2,0 × 1,25 m au lieu de 1,2 × 0,8 m | Nécessaire pour 20 s (directe) et 30 s (couverte) en marche | Provisoire ; à juger en jeu |
| D23 | Route couverte = dessous des meubles bas, derrière une plinthe en retrait à trois brèches | Couverture crédible, bascule possible, 10 cm de hauteur pour la caméra | Actée (tâche E) |
| D24 | Repères de nourriture et de refuge visibles de loin (biscuit de 3 cm, prise murale) | Les repères plats étaient invisibles à hauteur de cafard | Actée (tâche E) |
| D25 | Scènes de parcours écrites par des outils hors ligne (`tools/*.py`) | Dimensions exactes et modifiables ; aucune génération à l'exécution | Actée |
| D26 | Boucle de ressources dans une scène de composition (`kitchen_loop.tscn`) autour de la cuisine | La cuisine, son générateur et ses tests restent inchangés | Actée (tâche G) |
| D27 | Une miette unique qui porte sa machine d'états ; aucun inventaire | Rend impossibles duplication et double comptage | Actée (tâche G) |
| D28 | Portée d'interaction de 2 cm depuis l'enveloppe du corps, avec vue dégagée | Interaction liée au corps, pas à la caméra ; pas à travers les murs | Provisoire ; confort à juger |
| D29 | Transport = marche forcée via `PlayerMotor.sprint_blocked` | Changement minimal du moteur ; `PlayerInput` intact | Actée (tâche G) |
| D30 | Miette portée sur la tête, pas devant | Devant, elle entrait de 10,5 mm dans les murs | Actée (tâche G) |
| D31 | Humain à proportions réelles, confiné à des zones rectangulaires de l'allée, points de passage et lignes droites | Pas de navigation complexe ; meubles bas, refuge et chaise hors de portée | Actée (tâche F) |
| D32 | Perception par 3 rayons sur le corps réel, cône de ±60°, portée de 1,6 m, confirmation en 0,8 s | Occultation par le décor ; aucune connaissance hors vue | Provisoire ; à régler en jeu |
| D33 | Capture annoncée 0,7 s, point figé avec 60 % d'anticipation, zone de 3,5 cm, bloquée par tout obstacle au-dessus | Évitable en changeant de mouvement ou en se couvrant | Provisoire ; lisibilité à valider |
| D34 | Tentative de démonstration : un seul résultat terminal, recommencer reconstruit tout | Pas de sauvegarde ni de mort persistante | Actée (tâche F) |
| D35 | Garde de caméra sur les pièces visibles de l'humain, plutôt que des corps physiques sur les pieds | Les corps attachés aux pieds suivaient mal le visuel | Actée (tâche F) |
| D36 | Présentation audio séparée (`ThreatAudio`) : n'écoute que des signaux existants, un son par événement ; un seul événement ajouté (`inspecting`) | Aucun état d'IA reconstruit ; humain immobile silencieux, pas de sonar | Actée (tâche I) |
| D37 | Écouteur sur le cafard (12 mm), tourné avec le lacet du regard, indépendant de la distance et de l'inclinaison de la caméra | La caméra rapprochée ne doit pas changer la proximité perçue | Actée (tâche I) |
| D38 | Sons provisoires synthétisés par `tools/gen_audio.py` (Python standard, graines fixes) | Aucun téléchargement ni licence tierce ; reproductibles | Provisoire ; à remplacer par des sons produits |
| D39 | Bus Master (limiteur −1 dB), Threat, Ambience ; occultation bornée à −6 dB + passe-bas 2,5 kHz | Marge garantie ; la couverture assourdit sans rendre muet | Provisoire ; niveaux à juger à l'écoute |

Vision complète : voir la direction de production (sections 1 à 12) fournie
en début de projet ; le résumé opérationnel est le « Master Development
Prompt ».
