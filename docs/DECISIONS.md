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

Vision complète : voir la direction de production (sections 1 à 12) fournie
en début de projet ; le résumé opérationnel est le « Master Development
Prompt ».
