# Boucle de ressources (tâche G)

Première sortie complète, sans menace : prélever une miette, la transporter
(la lâcher et la reprendre si besoin), boire, et déposer la miette au
refuge.

## Lancer et réinitialiser

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/levels/kitchen_loop.tscn        # jouer (F6 dans l'éditeur)
$G --headless --fixed-fps 60 --path . res://scenes/tests/resource_loop_runner.tscn   # 66/66
$G --fixed-fps 60 --path . res://scenes/tests/resource_loop_runner.tscn -- --capture=/tmp/g   # séquence rendue
```

**Réinitialiser la session :** Échap, puis le bouton « Réinitialiser la
session ». La scène est reconstruite : miette à la source, objectifs
vides, joueur au refuge, jeu non pausé. Relancer la scène donne le même
résultat. Rien n'est conservé à la fermeture.

Les boutons de diagnostic (F3 : Refuge, Nourriture, Eau) ne font que
téléporter. Ils ne déposent pas la charge, ne valident pas l'eau et ne
touchent pas aux objectifs (c'est testé).

## Composition

`scenes/levels/kitchen_loop.tscn` instancie `kitchen_blockout.tscn` **sans
le modifier** : le générateur, la géométrie et les tests de la tâche E
restent valables. La composition ajoute :

| Nœud | Script | Rôle |
|---|---|---|
| `KitchenLoop` (racine) | `scripts/levels/kitchen_loop.gd` | `reset_session()` |
| `Session` | `scripts/game/session_state.gd` | `drank`, `reserve`, `success` (émis une seule fois) |
| `CarrySlot` | `scripts/resources/carry_slot.gd` | 0 ou 1 miette ; bloque le sprint ; cherche un point de lâcher |
| `Interactor` | `scripts/player/player_interactor.gd` | Choix de la cible ; relaie E et la touche lâcher de `PlayerInput` |
| `Resources/Crumb` | `scripts/resources/crumb.gd` | **La** miette de la session et sa machine d'états |
| `Resources/FoodSource` | `scripts/resources/food_source.gd` | Source fixe (biscuit) ; halo quand une miette est disponible ; `BiscuitBody` donne au biscuit une collision |
| `Resources/WaterPoint` | `scripts/resources/water_point.gd` | Boire ; éclair bleu de confirmation |
| `Resources/RefugeDeposit` | `scripts/resources/refuge_deposit.gd` | Dépôt au refuge ; pile au fond de la cavité |
| `Hud` | `scripts/ui/loop_hud.gd` | Action proposée, charge, objectifs, réussite, messages ; bouton de réinitialisation en pause |

Classe de base : `scripts/resources/interactable.gd`, qui fournit un
prompt et `interact()`. Un prompt vide signifie « pas disponible
maintenant ». Ce n'est pas un inventaire.

Seule modification d'un système existant : `PlayerMotor.sprint_blocked`
(4 lignes). `CarrySlot` le positionne ; le moteur ignore alors l'entrée de
sprint et marche. `PlayerInput`, la pause, l'accélération et le freinage
sont inchangés.

## Commandes

| Touche | Action | Selon la cible |
|---|---|---|
| **E** (`interact`) | Prélever une miette | source disponible, charge vide |
| | Reprendre la miette | miette au sol, charge vide |
| | Boire | point d'eau (possible en portant) |
| | Déposer la miette | refuge, miette portée |
| **Q physique** (`drop`) : A en AZERTY | Lâcher la miette | charge portée |
| Maj | Sprint | refusé tant qu'une miette est portée |

L'action disponible s'affiche en bas de l'écran (« [E] Boire »), avec la
touche adaptée à la disposition du clavier. E et le lâcher ne se répètent
pas quand la touche reste enfoncée (comportement de `PlayerInput`,
tâche B).

## Machine d'états de la miette

```text
 AT_SOURCE ──E à la source──▶ CARRIED ──lâcher──▶ ON_GROUND
                                 ▲                    │
                                 └────E sur la miette─┘
 CARRIED ──E au refuge──▶ DEPOSITED  (état final)
```

- Chaque transition vérifie l'état de départ et que la charge est vide :
  pas de duplication, pas de second prélèvement, pas de reprise d'une
  miette déposée. Le test tente aussi ces transitions par appel direct :
  elles sont refusées sans changer l'état.
- Portée, la miette est rattachée au visuel du joueur, **posée sur la
  tête**, et ne dépasse pas l'avant de la tête. Au sol, elle est statique,
  sans corps physique.
- La source reste visible (le biscuit). Seuls la miette posée dessus et le
  halo disparaissent quand elle est épuisée.

## Sélection de la cible (`PlayerInteractor`)

- Portée : **2 cm** entre l'enveloppe du corps (cylindre de 1 cm de rayon)
  et le bord de la cible, mesurée à l'horizontale depuis le corps, pas
  depuis la caméra.
- Rayon des cibles : source 1,8 cm, miette 0,4 cm, eau 3 cm, refuge 5 cm.
- Vue dégagée : un rayon à 4 mm du sol, du corps vers la cible, ne doit
  rien toucher sur la couche 1. Les propres corps de la cible (le biscuit)
  sont exclus.
- Une seule cible : la plus proche. En cas d'égalité à 0,1 mm près, c'est
  le chemin de nœud le plus petit qui gagne. Le choix est stable (testé).
- La sélection est recalculée à chaque tick physique et juste avant
  d'agir. Elle est figée en pause (le nœud est pausable, et `PlayerInput`
  n'émet rien).

## Lâcher (`CarrySlot.try_drop`)

Candidats, dans l'ordre : directions 0°, ±35°, ±70°, ±110° et 180° par
rapport au regard du cafard, à 2,6 puis 3,4 cm du centre du corps. Le
premier point valide est retenu. Un point est valide si :

1. un rayon vertical (±2 cm) trouve un sol de pente ≤ 35° **au niveau du
   joueur** (±5 mm) : ni vide, ni contrebas ;
2. la boîte de la miette (6 × 4 × 6 mm) ne chevauche rien ;
3. rien ne se trouve entre le corps et le point (rayon à 3–4 mm du sol).

Si aucun point n'est valide, la miette reste portée. `drop_failed` est
émis et l'interface affiche « Pas de place pour lâcher ici ». Il n'y a ni
lancer ni chute : la position est statique.

## Session

- `record_drink()` : met `drank` à vrai. Les répétitions sont comptées
  pour le diagnostic (`drink_events`), mais n'ajoutent rien.
- `record_deposit()` : ajoute 1 à `reserve`. Il n'est appelé que par le
  dépôt d'une miette réellement portée, et l'état final de la miette
  empêche un second dépôt.
- Réussite : `drank` et `reserve > 0`, dans n'importe quel ordre. Elle est
  émise une fois ; les déplacements restent libres. La position seule ne
  change jamais la session.

## Réglages

| Réglage | Où | Valeur |
|---|---|---|
| Portée d'interaction | `Interactor.reach` | 0,02 m |
| Hauteur du rayon de vue | `Interactor.sight_height` | 4 mm |
| Distances et angles de lâcher | `CarrySlot.drop_distances` / `drop_angles` | 2,6 et 3,4 cm ; 0, ±35, ±70, ±110, 180° |
| Pente maximale pour poser | `CarrySlot.max_floor_angle_deg` | 35° |
| Position portée | `Crumb.CARRY_OFFSET` | sur la tête (0 ; 7,5 mm ; −12 mm) |
| Durée des messages | `Hud.message_time` | 1,6 s |
| Éclair de l'eau | `WaterPoint.flash_time` | 0,5 s |

## Vérifications (2026-09-28)

`resource_loop_runner`, **66/66**. Tout passe par les touches et la
sélection de cible. Les téléportations servent seulement à la mise en
place. Des objets de test temporaires sont ajoutés pour le bord et
l'enclos.

| Scénario | Résultat |
|---|---|
| Refuge → eau → nourriture → refuge (route couverte puis directe) | Réussite émise une fois |
| Nourriture → dépôt (pas de réussite), puis eau (réussite) | OK |
| Sprint avant, pendant et après le transport | 0,16, puis au plus 0,080, puis de nouveau 0,16 m/s |
| Lâcher et reprendre sur la route directe et sous les meubles | Miette au sol, libre, à côté du joueur |
| Lâcher face à la plinthe | Posée du côté du joueur |
| Lâcher au bord d'un plateau de 1 cm | Posée sur le plateau, jamais en contrebas |
| Lâcher dans un enclos sans place | Charge conservée, message affiché |
| Miette derrière la plinthe, à portée en distance (1,5 cm) | Non sélectionnée ; E sans effet |
| Deux cibles à portée (miette 0 cm, eau 1,1 cm) | La plus proche, stable ; égalité stricte départagée par le chemin |
| E répété et maintenu (5 à 8 répétitions) à la source, à l'eau, au refuge | Aucune duplication, réserve = 1, réussite unique |
| Pause avec une cible disponible | Ni E ni lâcher ; pas d'action affichée |
| Réinitialisation | État initial complet |
| Téléportations de diagnostic en portant | Rien de déposé ni validé |
| Miette portée sur les trajets (4 751 ticks) | 0 pénétration du décor |
| Dos au biscuit | Caméra hors du biscuit |

Validité du test : 5 défauts injectés un par un, dont 4 détectés
directement. Le cinquième (sans le contrôle « même niveau » au lâcher) est
couvert par la règle de vue dégagée. Désactiver les deux est détecté.

Non-régression : B 57/57, C 54/54, D 47/47, E 52/52 ; scène principale
identique au pixel près. **Aucune attente existante n'a été modifiée.**

Séquence rendue : `docs/validation/resources/sequence_boucle_4.7.2.jpg`
(prendre → tenter de sprinter → lâcher → sprinter → reprendre → déposer →
boire).

## Défauts trouvés et corrigés pendant la tâche

- **Miette portée devant la tête :** poussée contre un mur, elle y entrait
  de 10,5 mm, soit plus que l'épaisseur de la plinthe. Elle est
  maintenant posée sur la tête : 5,0 mm, moins que la tête elle-même
  (9 mm).
- **Caméra dans le biscuit :** le biscuit de la tâche E n'avait pas de
  collision. Le corps `BiscuitBody` ajouté dans la composition règle le
  problème. `kitchen_blockout` n'est pas modifié ; ses propres tests
  l'utilisent toujours sans collision.
- **Interface sans affichage :** le nom de touche selon la disposition
  n'est pas disponible en headless. Il est calculé une fois, avec un repli
  sur le nom physique.

## Limites et contrôles manuels restants

- **Portée de 2 cm :** il faut s'approcher franchement (à 2/3 d'un corps
  de la cible). Le confort est à juger au clavier.
- La tête et la miette portée entrent de quelques millimètres dans un mur
  si l'on pousse de face : limite héritée de la tâche D.
- La pile de miettes au fond du refuge est peu visible depuis l'entrée.
- La réussite est un simple texte. Pas d'autre retour ni de son.
- Dans `kitchen_blockout.tscn` seul (tâche E), on peut toujours traverser
  le biscuit.
- À vérifier avec clavier, souris et écran : lisibilité de l'action
  proposée et des objectifs, compréhension du lâcher refusé, touche de
  lâcher affichée en AZERTY (« A »), sensation de marche forcée en
  portant, visibilité de la miette sur la tête.
