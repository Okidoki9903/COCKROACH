# COCKROACH — État du projet

_Dernière mise à jour : 2026-09-28 — tâche C (caméra) terminée._

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

Il reste des contrôles sur machine réelle (voir plus bas). Ils ne bloquent pas la tâche D.

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
| `docs/validation/camera/*.jpg` | Captures de référence caméra |
| `docs/.gdignore` | Empêche Godot d'importer la documentation comme ressource |
| `data/`, `assets/` | Dossiers réservés (vides, `.gitkeep`) |
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

## Vérifications restantes (non bloquantes pour D)

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
  `docs/CAMERA.md`). C'est un risque direct pour le contrôleur de la tâche D.
- Le conteneur distant est éphémère. Godot et lavapipe devront être
  réinstallés à chaque nouvelle session (voir le script dans
  `docs/TEST_CHECKLIST.md`).

## Prochaine tâche

Tâche **D — Movement : locomotion**. **Non commencée.** Commencer par
mesurer l'imprécision des collisions pour un corps de 3 cm.
