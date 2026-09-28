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

Aucune position physique n'est partagée entre deux actions. Sur AZERTY, la
touche **Q** déplace à gauche et la touche **A** lâche la charge, puisque
`drop` est lié au Q *physique*. Le test automatique vérifie ces deux points.

Souris : aucune action à cette étape. L'orientation de la caméra appartient
à la tâche C. Manette : hors périmètre.

## `PlayerInput` (`scripts/player/player_input.gd`)

Composant `Node` qui lit uniquement des actions InputMap et ne déplace rien.

| Membre | Type | Rôle |
|---|---|---|
| `move_vector` | `Vector2` | Intention de déplacement, longueur ≤ 1 |
| `sprint_held` | `bool` | Sprint maintenu |
| `interact_pressed` | signal | Émis une fois par pression, jamais sur répétition clavier |
| `drop_pressed` | signal | Idem |
| `pause_requested` | signal | Demande de bascule de pause (Échap) |

**Convention des axes de `move_vector`** (espace écran/caméra, pas espace
monde) :

- `x > 0` : droite, `x < 0` : gauche ;
- `y > 0` : avant, `y < 0` : arrière.

Une diagonale vaut (±0,707 ; ±0,707). Deux directions opposées s'annulent.
La conversion en direction 3D reviendra à la tâche D.

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

- Deux pressions de la même touche espacées de quelques millisecondes
  seulement sont fusionnées par le backend X11 de Godot, qui les prend
  pour une répétition clavier. Observé avec xdotool (0 ms : 3 pressions
  comptées 1 ; 150 ms : 3 pressions comptées 3). C'est hors du rythme d'un
  humain, mais à garder en tête pour des tests automatisés sous X11.
- Sous Xvfb sans gestionnaire de fenêtres, `xdotool windowfocus` provoque
  un événement de perte de focus, donc une pause. C'est un artefact de
  l'environnement de test, pas un défaut du jeu.
- Pas de remappage des touches (hors périmètre de la tâche B).
