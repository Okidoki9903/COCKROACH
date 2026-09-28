# COCKROACH — État du projet

_Dernière mise à jour : 2026-09-28 — tâche J (instinct visuel et lumière) terminée techniquement._

## Version du moteur (fixée)

| Élément | Valeur |
|---|---|
| Moteur | **Godot 4.7.2-stable**, édition standard, build `4.7.2.stable.official.ed1daf0bf` |
| Provenance | Release officielle `godotengine/godot`, tag `4.7.2-stable`, fichier `Godot_v4.7.2-stable_linux.x86_64.zip` (GitHub Releases) |
| Intégrité | SHA-512 vérifié contre le fichier `SHA512-SUMS.txt` de la même release : OK. Pas de signature cryptographique, car le projet Godot n'en publie pas. |
| Rendu | Forward+ (défaut du projet, inchangé) |
| Tag de fonctionnalités | `4.7` dans `project.godot` |

Conserver cette version pendant tout le prototype. Tout changement de
version passe par `docs/DECISIONS.md`.

## État réel

Le socle s'importe et s'exécute sans erreur ni avertissement dans Godot
4.7.2. `boot` charge `scale_test`. Le rendu Forward+ a été capturé et
inspecté.

**Étape A : validée pour l'import, l'exécution et le rendu Forward+ logiciel.**
**Étape B : terminée.** Une couche d'entrées clavier (InputMap, `PlayerInput`,
`PauseController`) et sa scène de test existent. Le cafard ne se déplace pas.
Voir `docs/CONTROLS.md`.
**Étape C : terminée.** `CameraRig` troisième personne (SpringArm3D), regard
à la souris dans `PlayerInput`, capture de la souris dans `PauseController`,
et scène `camera_test`. Le cafard ne se déplace toujours pas. Voir
`docs/CAMERA.md`.

**Étape D : terminée.** Scène Player (CharacterBody3D, cylindre de 10 × 8 mm,
`PlayerMotor`), marche à 0,08 m/s et sprint à 0,16 m/s relatifs à la
caméra, parcours `movement_test`. Voir `docs/MOVEMENT.md`.

**Étape E : terminée.** Blockout de cuisine `scenes/levels/kitchen_blockout.tscn`
(≈ 2,0 × 1,25 m) : refuge dans le mur, route directe (1,60 m, 20 s en marche),
route couverte sous les meubles (2,40 m, 30 s), bascule, détour vers l'eau, et
repères inertes de nourriture et d'eau. Voir `docs/LEVEL_BLOCKOUT.md`.

**Étape G : terminée.** Boucle jouable dans `scenes/levels/kitchen_loop.tscn`
(composition autour de la cuisine, inchangée) : prélever, porter en marchant,
lâcher, reprendre, boire, déposer ; la réussite demande l'eau et le dépôt.
Réinitialisation depuis la pause. Voir `docs/RESOURCE_LOOP.md`.

**Étape F : terminée techniquement.** Humain à routine, perception par rayons,
doute, confirmation, recherche à la dernière position vue, capture annoncée
et évitable, dans `scenes/levels/kitchen_threat.tscn` (composition autour de
`kitchen_loop`). Un seul résultat terminal ; recommencer reconstruit tout.
Voir `docs/HUMAN_AI.md`. Lisibilité et plaisir : non évalués.

**Étape I : terminée techniquement, écoute humaine non faite.** Première
couche audio de la menace, dans `kitchen_threat.tscn` :
- pas, froissement de fouille, annonce et résolution de capture, retour
  final, ronronnement discret ;
- entendus depuis le cafard (écouteur sur le cafard, tourné avec le
  regard), spatialisés, avec une occultation bornée ;
- bus Master, Threat et Ambience ; volumes réglables en pause.

La présentation n'écoute que des événements ; un seul événement a été
ajouté (`inspecting`). Les essais de capture sont clarifiés dans
`HUMAN_AI.md`, sans modifier les règles. Signal vérifié ; timbre,
confort, localisation perçue et lisibilité non validés. Voir
`docs/AUDIO.md`.

**Étape J : terminée techniquement, non évaluée par un joueur.** Indices
d'instinct à l'écran, présentés par `ThreatCues`, qui remplace le texte
« vibrations » :
- pas proches, avec une direction approximative relative au regard ;
- fouille proche ;
- annonce de capture : bandeau avec une barre, et disque de progression
  dans la zone ;
- esquive et annulation.

Réglages : intensité, mouvement réduit et indices renforcés sans son.
Nouvelle scène héritée `kitchen_instinct.tscn` : une lampe et sa zone
d'exposition, commandées par un seul contrôleur. Exposé et vu, le cafard
est confirmé ×1,5 plus vite (provisoire). Les autres scènes gardent leur
comportement. Voir `docs/INSTINCT.md`. L'écoute audio de la tâche I
reste à faire.

Il reste des contrôles sur machine réelle (voir plus bas).

## Éléments du projet

| Fichier | Rôle |
|---|---|
| `project.godot` | Configuration ; scène principale = `scenes/boot/boot.tscn` |
| `scenes/boot/boot.tscn` + `scripts/boot/boot.gd` (+ `.uid`) | Point d'entrée qui charge la scène de test |
| `scenes/tests/scale_test.tscn` | Scène de vérification d'échelle (référence visuelle, inchangée) |
| `scripts/player/player_input.gd` | `PlayerInput` : intentions du joueur lues depuis l'InputMap |
| `scripts/game/pause_controller.gd` | `PauseController` : pause, reprise, pause sur perte de focus |
| `scripts/ui/input_debug_panel.gd` | Panneau de diagnostic des entrées (lecture seule) |
| `scenes/tests/input_test.tscn` | Scène de test des entrées (instancie `scale_test`) |
| `scenes/tests/input_test_runner.tscn` + `scripts/tests/input_test_runner.gd` | Test automatique des entrées |
| `docs/CONTROLS.md` | Commandes, interface des composants, convention des axes |
| `scenes/camera/camera_rig.tscn` + `scripts/camera/camera_rig.gd` | `CameraRig` réutilisable |
| `scenes/tests/camera_test.tscn` + `scripts/ui/camera_debug_panel.gd` | Scène de test caméra et boutons de position |
| `scenes/tests/camera_test_runner.tscn` + `.gd` | Test automatique caméra |
| `scenes/tests/camera_capture.tscn` + `.gd` | Captures de rendu reproductibles |
| `docs/CAMERA.md` | Caméra : structure, réglages, imprécision des collisions, limites |
| `scenes/player/player.tscn` + `scripts/player/player_motor.gd` | Player réutilisable et `PlayerMotor` |
| `scenes/tests/movement_test.tscn` + `scripts/ui/movement_debug_panel.gd` | Parcours de locomotion et panneau |
| `tools/gen_movement_test.py` | Générateur du parcours |
| `scenes/tests/movement_test_runner.tscn` + `.gd` | Scénarios de locomotion (47) et contrôle d'indépendance au rendu |
| `scenes/tests/movement_capture.tscn` + `.gd` | Séquences rendues |
| `docs/MOVEMENT.md` | Locomotion : corps, mesures de collision, paramètres, limites |
| `scenes/levels/kitchen_blockout.tscn` | Blockout de cuisine, lançable séparément |
| `tools/gen_kitchen_blockout.py` | Outil de création hors ligne de la scène de cuisine |
| `scripts/ui/level_debug_panel.gd` | Panneau de niveau : position, chronomètre de trajet, retours ; F3 |
| `scenes/tests/kitchen_route_runner.tscn` + `.gd` | Parcours automatisé des routes, captures |
| `docs/LEVEL_BLOCKOUT.md` | Plan, dimensions, routes, temps, limites |
| `scenes/levels/kitchen_loop.tscn` + `scripts/levels/kitchen_loop.gd` | Session jouable : cuisine + boucle de ressources ; réinitialisation |
| `scripts/resources/*.gd` | `Interactable`, `Crumb`, `FoodSource`, `WaterPoint`, `RefugeDeposit`, `CarrySlot` |
| `scripts/player/player_interactor.gd` | Sélection de cible, E et lâcher |
| `scripts/game/session_state.gd` | Objectifs de la session (mémoire seulement) |
| `scripts/ui/loop_hud.gd` | Interface minimale de la boucle |
| `scenes/tests/resource_loop_runner.tscn` + `.gd`, `scripts/tests/fake_interactable.gd` | Scénarios de la boucle (66) et séquence rendue |
| `docs/RESOURCE_LOOP.md` | Boucle : commandes, états, réglages, vérifications, limites |
| `scenes/levels/kitchen_threat.tscn` + `scripts/levels/kitchen_threat.gd` | Tentative avec humain ; résultat terminal ; recommencer |
| `scenes/threat/human.tscn` + `scripts/threat/human_brain.gd`, `human_perception.gd` | Humain : états, déplacement, capture, perception |
| `scripts/threat/human_tuning.gd` + `data/tuning/human_tuning.tres` | Réglages centralisés de l'humain |
| `scripts/threat/threat_cues.gd` | Instinct (J) : indices de pas, fouille, annonce, badge d'exposition |
| `scripts/instinct/*.gd` | Réglages d'instinct et leur panneau, `ExposureLight`, `ExposureZone`, diagnostic de la lumière |
| `scenes/levels/kitchen_instinct.tscn` | Composition héritée de `kitchen_threat` + lumière et exposition |
| `scenes/tests/instinct_runner.tscn` + `.gd` | Contrôles d'instinct et de lumière (37), vues de la lumière, séquence |
| `docs/INSTINCT.md` | Indices, portées, durées, réglages, modèle d'exposition, limites |
| `docs/validation/instinct/` | Vues de la lumière, planches des séquences avec et sans son |
| `scripts/threat/threat_debug.gd` | Diagnostic d'IA (F3) |
| `scripts/threat/human_camera_guard.gd` | Caméra hors des pieds et jambes de l'humain |
| `scenes/tests/threat_runner.tscn` + `.gd` | Scénarios de l'humain (36) et séquence rendue |
| `docs/HUMAN_AI.md` | Route, états, paramètres, fenêtres de fuite (essais mesurés), limites |
| `scripts/audio/threat_audio.gd` | `ThreatAudio` : événements de l'humain → sons, écouteur sur le cafard |
| `scripts/audio/audio_settings.gd` | Curseurs de volume en pause |
| `default_bus_layout.tres` | Bus Master (limiteur −1 dB), Threat, Ambience |
| `assets/audio/*.wav` (+ `.import`) | 9 sons provisoires synthétisés |
| `tools/gen_audio.py`, `tools/analyze_audio.py` | Générateur des sons ; analyse du signal enregistré |
| `scenes/tests/audio_runner.tscn` + `.gd` | Contrôles audio (27), sonde et scénario enregistrés |
| `scenes/tests/capture_trials_runner.tscn` + `.gd` | Essais de capture mesurés (7) |
| `docs/AUDIO.md` | Audio : événements, provenance, écouteur, bus, cycle de vie, mesures, limites |
| `docs/validation/audio/` | Clip stéréo du scénario, frises, images, analyses |
| `docs/validation/threat/*.jpg` | Séquence repérage → recherche → routine |
| `docs/validation/kitchen/*.jpg` | Plan annoté, vues à hauteur de cafard, séquence |
| `docs/validation/movement/sequences_4.7.2.jpg` | Captures de référence |
| `docs/validation/camera/*.jpg` | Captures de référence caméra |
| `docs/.gdignore` | Empêche Godot d'importer la documentation comme ressource |
| `data/`, `assets/` | Réglages (`data/tuning/`) et sons (`assets/audio/`) |
| `docs/DECISIONS.md` | Décisions de production |
| `docs/TEST_CHECKLIST.md` | Procédure de lancement, contrôles et historique |
| `docs/validation/scale_test_forward_plus_4.7.2.png` | Capture de référence |
| `.gitignore`, `.gitattributes` | Exclusion du cache `.godot/`, fins de ligne LF |

## Échelle (1 unité = 1 mètre)

| Objet | Dimensions (m) | Position (m) |
|---|---|---|
| Sol (`Floor`, collision) | 2 × 0,02 × 2 — face supérieure à y = 0 | (0, −0,01, 0) |
| Meuble (`Furniture`, collision) | 0,6 × 0,85 × 0,6 — caisson de cuisine | (0, 0,425, −0,5) |
| Repère cafard (`CockroachMarker`) | 0,012 × 0,006 × 0,03 — 3 cm de long selon Z | (0, 0,003, 0) |
| Barre d'échelle (`ScaleBar10cm`, jaune) | 0,10 de long selon X | (0, 0,001, 0,03) |
| Caméra fixe (`FixedCamera`) | FOV 60°, near 0,001, far 20 | (0,06, 0,035, 0,10), visée vers (0, 0,012, −0,06) |
| Lumière (`KeyLight`) | Directionnelle, direction ≈ (0,61 ; −0,66 ; −0,45) | biais 0,02, biais normal 0,5, distance d'ombre 1,5 |

## Vérifications tâche J — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Instinct, lumière, confirmation, cycle de vie | `instinct_runner` (kitchen_instinct + kitchen_threat) | **37/37** |
| Validité du test | 7 défauts injectés (suivi continu, lumière sans occultation, lumière qui fait voir, lampe sans zone, direction fixe, remise à zéro du doute, bandeau non effacé) | Tous détectés (la 6e mutation corrigée pour être pertinente) |
| Lumière rendue et zone | vues de dessus et du cafard | coïncident ; sous l'assise : ombre, pas d'exposition |
| Séquences | avec son, et sans son + indices renforcés | 17 indices identiques ; `validation/instinct/` |
| Non-régression | B 57, C 54, D 47, E 52, G 66, F 36, essais 7, audio 27 ; scène principale | OK ; **identique au pixel près** |
| Joueur réel | — | **Non évalué** (compréhension, surcharge, exposition, première capture) |
| Écoute audio (I) | — | **Toujours non faite** |

## Vérifications tâche I — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Événements, routage, écouteur, pause, fin, redémarrages | `audio_runner` | **27/27** |
| Validité du test | 7 défauts injectés (double connexion, écouteur sur la caméra, lecteurs non pausables, pas d'arrêt à la fin, froissement sur chaque pas, lecteurs hors scène, son d'échec sur réussite) | Tous détectés (le 6e après correction du comptage) |
| Règles de capture | `capture_trials_runner` : réglages + 6 essais ; `threat_runner` | **7/7** ; **36/36** inchangé |
| Signal (sonde) | movie writer, 48 kHz stéréo, `tools/analyze_audio.py` | G/D ≈ ±10 dB, inversé par la rotation ; −21 dB de 0,3 à 1,2 m ; caméra à 2 cm sans effet ; occultation ≈ −7 dB ; crête −7,0 dBFS, rien ≥ −1 dBFS ; annonce +30 dB sur l'ambiance dans sa bande |
| Signal (scénario) | approche hors champ, passages, recherche près de la cachette, annonce ratée, capture | 21 sons synchronisés (15–63 ms) ; crête −9,3 dBFS ; clip `validation/audio/scenario_menace_stereo_4.7.2.wav` |
| Écoute humaine | — | **Non faite** : timbre, confort, localisation perçue, lisibilité non validés |
| Panneau de volume | rendu en pause | affiché sous le menu ; 40 % → −7,96 dB ; 0 % coupe le bus |
| Non-régression | B 57, C 54, D 47, E 52, G 66, F 36 ; scène principale | OK ; **identique au pixel près** |

## Vérifications tâche F — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Scénarios de l'humain | `threat_runner` (perception et collisions réelles) | **36/36** |
| Sortie complète par les commandes | boire → prendre → éviter → déposer, sans téléportation ni invulnérabilité | Réussie. L'humain a repéré le cafard (doute 74 ticks, confirmé 33), l'a perdu et l'a cherché, sans capture ; distance minimale 0,28 m |
| Validité du test | 5 défauts injectés (sans occultation, position connue mise à jour sans vue, capture à travers obstacle, capture qui suit, recherche sans fin) | Tous détectés |
| Rendu | Séquence repérage → fuite → annonce → recherche → routine (vue diagnostic et vue du cafard) | Caméra dans les chaussures (188 ticks) → corrigé : 0 |
| Non-régression | B 57, C 54, D 47, E 52, G 66 ; scène principale | OK ; **identique au pixel près** |

Défauts trouvés et corrigés pendant la tâche :
- départ du joueur visible par l'entrée du refuge → départ au fond ;
- oscillation de l'humain au point de jonction (seuil d'arrivée), puis
  arrêt à 2 cm de la jonction ;
- caméra dans les pieds de l'humain → garde de caméra, pieds reculés de
  3 cm.

## Vérifications tâche G — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Scénarios de la boucle | `resource_loop_runner` (touches et sélection de cible réelles) | **66/66** |
| Validité du test | 5 défauts injectés (reprise à la source, vue dégagée, rebord, sprint, double dépôt) | 4 détectés directement ; le 5ᵉ est couvert par une seconde règle, et désactiver les deux est détecté |
| Rendu | Séquence prendre → sprint refusé → lâcher → reprendre → déposer → boire | Caméra dans le biscuit → corrigé ; miette visible sur la tête |
| Non-régression | B 57/57, C 54/54, D 47/47, E 52/52 ; scène principale | OK, aucune attente modifiée ; **identique au pixel près** |

## Vérifications tâche E — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Traversabilité | `kitchen_route_runner` : 4 routes × aller/retour × marche/sprint | **52/52** ; 16 trajets arrivés, jamais bloqués, caméra jamais dans le décor |
| Visuel de 3 cm | Boîte du visuel testée contre le décor à chaque tick | 0 pénétration sur 17 972 ticks |
| Temps (marche, aller) | Même runner | Directe 20,1 s / 1,60 m ; couverte 30,1 s / 2,40 m (33 % plus court) |
| Rendu | Plan annoté, 8 vues, vue d'ensemble, séquence de la route couverte | 2 défauts de lisibilité corrigés : destination et refuge invisibles de loin |
| Non-régression | B 57/57, C 54/54, D 47/47 ; scène principale | OK ; **identique au pixel près** |

Défauts de test corrigés en cours de route : contrôle caméra fait avant
`_process` (même piège qu'en tâche C) ; critère « bloqué » déclenché par un
demi-tour.

## Vérifications tâche D — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Collision à petite échelle | Cylindre, capsule et sphère ; marges de 1 à 0,1 mm, sur le même parcours | Cylindre et 0,2 mm retenus ; 0,1 mm bloque le corps ; la capsule pénètre de 2,5 mm |
| Scénarios de locomotion | `movement_test_runner` (`--fixed-fps 60`) | **47/47**, stable sur 3 exécutions ; 47/47 aussi en temps réel |
| Validité du test | 3 défauts injectés : cap tiré de la caméra 3D, visuel suivant la caméra, accélération ×2 | Tous détectés |
| Indépendance au rendu | 90 ticks à 60 Hz physique ; limites max_fps 20/45/120 en rendu (fréquence mesurée 15–17 i/s dans les trois cas) et 20/240 en headless (mesurée 20 et ≈ 145 i/s) | 0,233332 m partout, après correction. Démontrée pour 20–145 i/s en headless seulement ; en rendu, la fréquence n'a pas varié. GPU réel au-delà de 60 i/s : en attente (détail dans `docs/MOVEMENT.md`) |
| Non-régression | B 57/57 ; C 54/54 (×2) ; scène principale, capture de référence | OK ; **identique au pixel près** |
| Événements X11 réels | Xvfb + xdotool : Z, Maj, Échap, souris, perte de focus | Marche 0,080, sprint 0,160, arrêt ; position figée en pause ; rien de bloqué après perte de focus |
| Rendu | 5 séquences personnage + caméra | Pas de clipping ; caméra stable dans le passage |

## Vérifications tâche C — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Test automatique (simulé) | `camera_test_runner.tscn` | **54/54**, stable sur 3 exécutions ; 5 contrôles de mode souris ignorés en headless, vérifiés sous X11 |
| Validité du test | 3 défauts injectés : regard × delta, regard actif en pause, retour instantané | Tous détectés ; code restauré |
| Non-régression B | `input_test_runner.tscn` | 57/57 |
| Non-régression socle | Scène principale headless, puis capture Forward+ comparée à la référence | Code 0 ; **identique au pixel près** |
| Rendu | `camera_capture.tscn` : 5 positions, tangages extrêmes, rotation de 24 pas le long du mur | Voir `docs/validation/camera/` |
| Événements X11 réels | Xvfb + xdotool : souris relative, Échap, perte de focus | 100 px → −17,2° ; 50 px haut → +8,6° ; rien en pause ni hors focus ; pas de saut à la reprise ; pointeur bloqué au centre si capturé, libre sinon |

Défauts trouvés et corrigés pendant la tâche :

1. Face à un mur, la caméra passait à 1,2 mm de la surface, et jusqu'à
   25 images sur 144 avaient le plan proche en contact avec le décor.
   Cause : l'imprécision de `cast_motion` à cette échelle, plus la marge du
   `SpringArm3D` qui ne s'applique pas à une caméra non enfant. Correction :
   sphère de 6 mm, marge de 3 mm appliquée par le rig. Résultat : 0 image
   fautive.
2. Test : `SceneTree.process_frame` est émis avant les `_process()`. Les
   contrôles lisaient un état jamais rendu. Correction : contrôles exécutés
   depuis un `_process` de priorité maximale, après une étape physique.

## Vérifications tâche B — 2026-09-28

| Type | Méthode | Résultat |
|---|---|---|
| Importation | `--headless --import` | Code 0, aucune erreur ni avertissement |
| Test automatique (simulé) | `input_test_runner.tscn` : `Input.parse_input_event`, routage par le moteur | **57/57**, code 0 |
| Validité du test | Deux défauts injectés : répétitions acceptées, pause ignorée | Détectés : 53/57 et 54/57, code 1 ; code restauré |
| Régression, exécution | Scène principale headless, `--quit-after 120` | Code 0 ; `boot` charge `scale_test` |
| Régression, rendu | Capture Forward+ de la scène principale, comparée à la capture de référence | **Identique au pixel près** |
| Rendu de la scène de test | Capture Forward+ | Seule la zone du panneau diffère de la référence ; panneau lisible |
| Événements X11 réels | Xvfb + xdotool (XTest), captures du panneau | Voir ci-dessous |

Couvert par le test automatique : chaque direction seule, 4 diagonales
(longueur 1, 45°), opposés annulés, relâchement, positions physiques AZERTY,
sprint maintenu et répété, interact/drop une fois malgré 5 répétitions,
pause et reprise par Échap (répétitions d'Échap ignorées), intentions
neutres et aucun signal pendant la pause, panneau actif pendant la pause,
perte de focus (pause, intentions et actions relâchées), retour du focus
sans reprise, repère cafard immobile.

Événements X11 réels (le serveur X transmet les touches à Godot, mais ce
n'est pas un clavier physique) : diagonale W+D = (0,71 ; 0,71) ; W+D+S =
(1 ; 0) ; relâchement = 0 ; W+Maj = avant et sprint ; E et Q comptés une
fois par pression (espacement de 150 ms) ; E maintenu 2 s = 1. Perte de
focus vers une autre fenêtre avec W et Maj enfoncés : pause, intentions à
zéro, rien de bloqué après relâchement hors fenêtre, pas de reprise au
retour du focus, Échap reprend.

Constats (voir `docs/CONTROLS.md`, « Limites connues ») : fusion par X11 de
pressions espacées de quelques ms ; `xdotool windowfocus` sans gestionnaire
de fenêtres déclenche une pause (artefact de test). Au lancement, la scène
démarre bien non pausée.

## Vérifications socle — 2026-09-28

Environnement : conteneur Ubuntu 24.04 x86_64, sans écran ni GPU. Godot est
installé hors du dépôt (`/home/user/tools/godot/4.7.2/`). Pour le rendu :
Xvfb, et le pilote Vulkan logiciel Mesa lavapipe (`mesa-vulkan-drivers`,
installé par apt dans le conteneur).

| Type | Commande | Code | Résultat |
|---|---|---|---|
| Statique | Script de cohérence des scènes (session précédente) | — | OK ; non relancé, car les modifications ne touchent aucune référence |
| Importation | `--headless --path . --import` | 0 | Aucune erreur ni avertissement. Génère `.godot/` (ignoré) et `scripts/boot/boot.gd.uid` (committé) |
| Exécution | `--headless --path . --verbose --quit-after 120` | 0 | Aucune erreur ni avertissement ; journal : chargement de `boot.tscn`, `boot.gd`, puis `scale_test.tscn` |
| Rendu Forward+ | `xvfb-run … --write-movie … --quit-after 60` avec lavapipe | 0 | Journal : `Vulkan 1.4.318 - Forward+ - llvmpipe` ; 60 images capturées |
| Visuel | Inspection de la capture | — | Voir ci-dessous |

Un premier rendu sans Vulkan a basculé automatiquement vers OpenGL
(Compatibility). Ce rendu n'est pas la cible et n'a pas servi à la
validation. Le renderer du projet n'a pas été modifié.

### Inspection visuelle (capture Forward+)

- Repère cafard, barre de 10 cm (environ 3 fois le repère) et meuble
  gigantesque : visibles et lisibles.
- Pas d'objet coupé par le plan proche, pas d'acné d'ombre.
- 55 images consécutives identiques au pixel près. Cela exclut un
  scintillement **pour une caméra et une scène statiques uniquement**.

### Défaut constaté et corrigé

**Symptôme :** aucune ombre portée sous le repère cafard.

1. Hypothèse « ombre cachée derrière le repère » : lumière et caméra venaient
   du même côté. J'ai réorienté la lumière, sans effet sur l'ombre : **réfutée**.
   La nouvelle orientation est conservée, car elle place l'ombre du côté visible.
2. Hypothèse « biais d'ombre par défaut trop grand pour un objet de 6 mm » :
   `shadow_bias` 0,1 → 0,02, `shadow_normal_bias` 2,0 → 0,5,
   `directional_shadow_max_distance` 5 → 1,5. **Confirmée** : l'ombre apparaît,
   attachée à la base du repère.

Après correction, l'importation, l'exécution et le rendu ont été relancés :
tous OK.

## Vérifications restantes

- Tâche J, avec écran, clavier et souris :
  - compréhension spontanée des arcs « pas » et du « ? fouille » ;
  - surcharge visuelle ;
  - perception de l'exposition (badge et flaque de lumière) ;
  - lisibilité du bandeau en 0,7 s, et possibilité de comprendre et
    d'esquiver la **première** capture ;
  - confort du mouvement réduit ;
  - jeu sans son avec les indices renforcés.

  Aucun temps de réaction n'est jugé confortable sur la base des tests
  automatiques.
- **Écoute audio (tâche I) : toujours non réalisée.**

- Tâche I, au casque puis sur haut-parleurs : timbre et crédibilité des
  sons ; confort (pas répétés, ronronnement) ; localisation gauche/droite
  perçue (devant/derrière non distingués) ; lisibilité de l'annonce, et
  différence entre raté et attrapé ; audibilité des froissements près
  de la cachette ; niveaux relatifs des trois bus ; pilote audio réel.

- Tâche F, avec clavier, souris et écran : compréhension de l'approche
  (pieds, vibrations), du repérage et de la zone de capture ; temps de
  réaction réel face à 0,7 s d'annonce ; compréhension de la règle
  « changer de mouvement pour esquiver » ; surprise des pieds qui passent
  sur le cafard ; intérêt et difficulté de la sortie.

- Tâche G, avec clavier, souris et écran : confort de la portée de 2 cm,
  lisibilité de l'action proposée, des objectifs et du lâcher refusé,
  libellé AZERTY de la touche lâcher, visibilité de la miette sur la tête
  et de la pile au refuge.

- Tâche E, à l'écran avec clavier et souris : compréhension de la première
  sortie, lisibilité de la destination et du retour, choix entre les deux
  routes, monotonie du tunnel sous les meubles, confort des rapprochements
  caméra aux virages serrés, visibilité de la prise-repère à 1,5 m.

- Tâche D, clavier/souris/écran réels : confort des vitesses (0,08 et
  0,16 m/s), nervosité de l'accélération (0,1 s) et du freinage (0,08 s),
  lecture de l'orientation du cafard, sensation de la caméra en entrée de
  passage et après une chute, fluidité au-delà de 60 Hz (la caméra suit au
  rythme physique).

- Tâche C, souris physique et GPU réel : confort de la sensibilité (0,003
  rad/px), sens de rotation, absence de saut à la reprise, tremblement
  éventuel en rotation lente contre un mur, fluidité sur écran de plus de
  60 Hz, clic sur les boutons pendant la pause, Alt+Tab.
- Tâche C, performance : non mesurée (rendu logiciel uniquement).

- Tâche B, sur machine réelle avec clavier physique : ZQSD sur AZERTY et WASD
  sur QWERTY, Maj gauche et droite, E, A (AZERTY) ou Q (QWERTY), Échap,
  Alt+Tab avec une touche enfoncée, répétition réelle d'une touche maintenue.
- Lancement interactif (F5) sur une machine avec GPU réel.
- Contrôles dans l'éditeur (voir `docs/TEST_CHECKLIST.md`), puis commit des
  `uid=` que l'éditeur ajoutera aux scènes.
- Scintillement en mouvement : à tester avec la caméra de la tâche C.

## Limites connues

- Aucune icône de projet.
- Caméra fixe provisoire, sans script ; elle sera remplacée à la tâche C.
- Pas de collision sur le repère cafard (pas de gameplay).
- Collisions millimétriques : `cast_motion` pénètre de 2 à 4 mm (voir
  `docs/CAMERA.md`). Pour le personnage, c'est maîtrisé avec un cylindre et
  `safe_margin` = 0,2 mm. Attention : 0,1 mm bloque le corps (voir
  `docs/MOVEMENT.md`).
- Le conteneur distant est éphémère. Godot et lavapipe devront être
  réinstallés à chaque nouvelle session (voir le script dans
  `docs/TEST_CHECKLIST.md`).

## Prochaine tâche

Tâche J faite techniquement. La suspicion globale et la sauvegarde ne
sont pas commencées. Prochaine étape selon la feuille de route, après
les évaluations manuelles de F, I et J.
