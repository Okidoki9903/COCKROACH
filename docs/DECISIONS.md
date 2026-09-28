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

Vision complète : voir la direction de production (sections 1 à 12) fournie
en début de projet ; le résumé opérationnel est le « Master Development
Prompt ».
