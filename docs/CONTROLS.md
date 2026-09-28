# Commandes et couche d'entrées (tâche B)

## Actions InputMap (`project.godot`, section `[input]`)

Toutes les touches sont liées par **position physique** (`physical_keycode`),
ce qui les rend indépendantes de la disposition du clavier.

| Action | Position physique (QWERTY) | Touche AZERTY | Type |
|---|---|---|---|
| `move_forward` | W | Z | maintenue |
| `move_backward` | S | S | maintenue |
| `move_left` | A | Q | maintenue |
| `move_right` | D | D | maintenue |
| `sprint` | Maj (gauche ou droite) | Maj | maintenue |
| `interact` | E | E | une fois par pression |
| `drop` | Q | A | une fois par pression |
| `pause` | Échap | Échap | une fois par pression (bascule) |
| `toggle_debug` | F3 | F3 | masque ou affiche le panneau de diagnostic du niveau (tâche E) |

Depuis la tâche G, dans `kitchen_loop.tscn` : **E** prélève, reprend, boit
ou dépose selon la cible ; la touche **lâcher** (Q physique, A en AZERTY)
pose la miette ; le sprint est refusé tant qu'une miette est portée. Voir
`docs/RESOURCE_LOOP.md`.

Depuis la tâche F, dans `kitchen_threat.tscn` : aucune nouvelle commande.
F3 affiche aussi le diagnostic de l'humain ; « Recommencer » (bouton) après
une capture ou une réussite.

Depuis la tâche I, dans `kitchen_threat.tscn` : aucune nouvelle touche.
**Volume** : en pause (Échap), trois curseurs sous le menu de pause
(« Général », « Humain », « Ambiance »), de 0 à 100 % par pas de 5, à la
souris ou au clavier (Tab puis flèches). 0 % coupe le bus. Les réglages
durent la session (ils survivent à « Recommencer »), sans sauvegarde. F3
liste aussi les derniers sons émis. Voir `docs/AUDIO.md`.

Depuis la tâche J : aucune nouvelle touche. En pause, le panneau
« Indices d'instinct » (à gauche des volumes) offre :
- l'intensité, de 25 à 100 % ;
- le mouvement réduit ;
- les indices renforcés (sans son).

Dans `kitchen_instinct.tscn`, la lumière ne se bascule que depuis le
diagnostic : F3, puis le bouton « Basculer la lumière (diagnostic) ».
Voir `docs/INSTINCT.md`.

Aucune position physique n'est partagée entre deux actions. Sur AZERTY, la
touche **Q** déplace à gauche et la touche **A** lâche la charge, puisque
`drop` est lié au Q *physique*. Le test automatique vérifie ces deux points.

Souris (tâche C) : le mouvement relatif oriente la caméra. Il ne passe pas
par une action InputMap : `PlayerInput` lit directement
`InputEventMouseMotion`. Voir `docs/CAMERA.md`.

## Manette (depuis la version jouable Windows)

Les actions existantes ont reçu des liaisons manette dans `project.godot`.
Les touches du clavier sont inchangées, et clavier, souris et manette
marchent ensemble. Godot reconnaît les manettes courantes (Xbox,
PlayStation, 8BitDo…) par la base SDL ; ce sont les **positions** des
boutons qui comptent (A = bouton du bas).

| Manette (disposition Xbox / X-input) | Action |
|---|---|
| Stick gauche ou croix | se déplacer (`move_*`, zone morte 0,2) |
| Stick droit | regarder (`look_*`, zone morte 0,15, 2,5 rad/s à fond, réponse au carré) |
| RB, gâchette droite ou clic du stick gauche | sprint |
| A | interagir (et valider dans les menus) |
| B | lâcher la miette |
| Start | pause / reprise |
| Back / Select | diagnostic (F3) |

- **Regard :** le stick droit ajoute une vitesse à la même file que la
  souris (`PlayerInput.consume_look`), intégrée une fois par tick
  physique. La caméra n'est pas modifiée. Réglages :
  `PlayerInput.stick_look_speed` et `invert_look_y`.
- **Menus :** le dernier appareil utilisé est retenu
  (`PlayerInput.using_gamepad`).
  - À la manette, la pause donne le focus au premier curseur de volume,
    jamais à « Réinitialiser » (pas de remise à zéro accidentelle).
  - La croix navigue et règle les curseurs ; A valide (ajouté à
    `ui_accept`, qui ne contient par défaut qu'Entrée et Espace).
  - En fin de tentative, « Recommencer » a le focus : A ou Entrée
    recommence.
  - À la reprise, aucun contrôle ne garde le focus : A reste « interagir ».
- **Invites :** « [A] Boire », « [B] lâcher » à la manette ; les touches
  du clavier sinon.
- **Non vérifié avec une vraie manette :** les tests envoient des
  événements manette simulés.

## `PlayerInput` (`scripts/player/player_input.gd`)

Composant `Node` qui lit uniquement des actions InputMap et ne déplace rien.

| Membre | Type | Rôle |
|---|---|---|
| `move_vector` | `Vector2` | Intention de déplacement, longueur ≤ 1 |
| `sprint_held` | `bool` | Sprint maintenu |
| `interact_pressed` | signal | Émis une fois par pression, jamais sur répétition clavier |
| `drop_pressed` | signal | Idem |
| `pause_requested` | signal | Demande de bascule de pause (Échap) |
| `consume_look()` | `Vector2` | Rotation demandée depuis l'appel précédent, en radians (x = droite, y = haut) |
| `look_sensitivity` | export | Radians par pixel (0,003) |
| `invert_look_y` | export | Inversion verticale |

**Convention des axes de `move_vector`** (espace écran/caméra, pas espace
monde) :

- `x > 0` : droite, `x < 0` : gauche ;
- `y > 0` : avant, `y < 0` : arrière.

Une diagonale vaut (±0,707 ; ±0,707). Deux directions opposées s'annulent.
La conversion en direction 3D reviendra à la tâche D.

`move_vector` et `sprint_held` sont rafraîchis dans `_process` **et** au
début de chaque tick physique (priorité −2, avant `PlayerMotor`). Sinon, les
ticks exécutés avant `_process` dans une image lisent l'intention de l'image
précédente (mesuré en tâche D).

Pendant la pause, ou après une perte de focus, `move_vector` vaut zéro,
`sprint_held` vaut faux, et aucun signal `interact_pressed` ou `drop_pressed`
n'est émis. `pause_requested` reste actif, pour pouvoir reprendre.

## `PauseController` (`scripts/game/pause_controller.gd`)

- Reçoit `pause_requested` et bascule `get_tree().paused`. Signal
  `paused_changed(paused)`.
- Perte de focus (application ou fenêtre) : met en pause et relâche de force
  les actions de gameplay, car une touche relâchée hors de la fenêtre
  n'envoie jamais d'événement de relâchement.
- Retour du focus : **ne reprend pas** la partie. Échap est nécessaire.
- `capture_mouse` (export, faux par défaut) : souris capturée pendant le
  jeu, libérée en pause et à la perte de focus, recapturée seulement à la
  reprise explicite.
- Aucun menu.

## Scène de test des entrées

`scenes/tests/input_test.tscn` instancie `scale_test.tscn` sans la modifier
et ajoute `PlayerInput`, `PauseController` et un panneau de diagnostic
(`scripts/ui/input_debug_panel.gd`). Le panneau affiche le vecteur, le
sprint, les compteurs interact/drop et l'état de pause, et continue de se
mettre à jour pendant la pause.

La scène principale (`boot`, puis `scale_test`) est inchangée.

Lancer la scène de test des entrées :

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/tests/input_test.tscn
```

Dans l'éditeur : ouvrir `scenes/tests/input_test.tscn` puis **F6**
(scène courante).

Test automatique (événements simulés traités par le moteur) :

```sh
$G --headless --path . res://scenes/tests/input_test_runner.tscn
# code de sortie 0 = tout est passé ; 1 = échec ; 2 = délai dépassé
```

## Limites connues

- Test X11 avec xdotool : 3 pressions envoyées sans délai ont été comptées
  une seule fois ; avec 150 ms d'écart, 3 sur 3. 150 ms n'est **pas** une
  limite humaine établie : des appuis rapides réels peuvent être plus
  serrés. L'origine de la fusion reste **à confirmer**. Hypothèse non
  vérifiée : le backend X11 de Godot interprète un relâchement suivi d'un
  appui immédiat comme une répétition ; ce pourrait aussi venir de xdotool.
  La logique clavier n'est pas modifiée tant qu'aucun défaut n'est
  reproduit avec un vrai clavier (contrôle manuel en attente).
- Sous Xvfb sans gestionnaire de fenêtres, `xdotool windowfocus` provoque
  un événement de perte de focus, donc une pause. C'est un artefact de
  l'environnement de test, pas un défaut du jeu.
- Pas de remappage des touches (hors périmètre de la tâche B).
