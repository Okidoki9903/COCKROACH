# Humain et détection (tâche F)

Un humain provisoire suit une routine dans l'allée de la cuisine, repère
le cafard s'il reste exposé, cherche à la dernière position effectivement
vue, puis tente une capture annoncée. Pas de suspicion globale, pas de
piège, pas de lumière.

## Lancer et recommencer

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/levels/kitchen_threat.tscn        # jouer (F6 dans l'éditeur)
$G --headless --fixed-fps 60 --path . res://scenes/tests/threat_runner.tscn   # scénarios (≈ 10 min)
$G --fixed-fps 60 --path . res://scenes/tests/threat_runner.tscn -- --capture=/tmp/f   # séquence rendue
```

- **Fin de tentative :** capture (« Attrapé ! ») ou réussite des objectifs
  de la tâche G (« Sortie réussie : tentative terminée »). Un seul résultat
  est possible. Ensuite, l'humain, le cafard et les interactions s'arrêtent
  et la souris est libérée.
- **Recommencer :** le bouton de fin, ou Échap puis « Réinitialiser la
  session ». La scène entière est reconstruite, humain compris. Rien n'est
  sauvegardé.
- `kitchen_loop.tscn` lancée seule garde son comportement (tâche G) : sa
  réinitialisation n'est déléguée que si une scène englobante le demande
  (`KitchenLoop.external_reset`).

## Composition

`scenes/levels/kitchen_threat.tscn` instancie `kitchen_loop.tscn`, qui
n'est pas modifiée hormis la délégation du reset. S'y ajoutent :

| Nœud | Fichier | Rôle |
|---|---|---|
| `KitchenThreat` (racine) | `scripts/levels/kitchen_threat.gd` | Résultat terminal unique, arrêt, recommencer ; départ au fond du refuge |
| `HumanRoute` | (Marker3D) | 6 points de passage ; métadonnée `pause` ; l'orientation du marqueur donne le regard pendant la pause |
| `Human` | `scenes/threat/human.tscn`, `scripts/threat/human_brain.gd` | États, déplacement, capture |
| `Human/Perception` | `scripts/threat/human_perception.gd` | Rayons de vue sur le corps réel du cafard |
| (ressource) | `data/tuning/human_tuning.tres`, `scripts/threat/human_tuning.gd` | **Tous** les réglages de l'humain |
| `HumanCameraGuard` | `scripts/threat/human_camera_guard.gd` | Empêche la caméra du joueur d'entrer dans les pieds et les jambes |
| `ThreatCues` | `scripts/threat/threat_cues.gd` | Signal **joueur** : vibration des pas proches |
| `ThreatDebug` | `scripts/threat/threat_debug.gd` | **Diagnostic** (F3) : état, visibilité, confirmation, dernière position, recherche, zone |
| `Outcome` | (dans la scène) | Message de fin et bouton « Recommencer » |

## L'humain

- **Proportions réelles :** yeux à 1,60 m ; chaussures de 27 × 10 cm (bout
  clair pour lire l'orientation) ; jambes, torse et tête en boîtes. Le haut
  du corps sort du cadre de la caméra du cafard.
- **Collision :** capsule de jambes, rayon 10 cm, sur la **couche 8**.
  Masque 1 : les meubles l'arrêtent. Le cafard (masque 1) ne le touche
  pas : aucune poussée, aucune projection. Contact avec un pied = aucun
  effet.
- **Zones de passage** (`walk_areas`, rectangles x/z) :
  - l'allée : x 0,15 → 1,45, z 0,71 → 0,74 ;
  - un raccord : x 1,40 → 1,50, z 0,71 → 0,79 ;
  - la poche devant le frigo : x 1,45 → 1,88, z 0,77 → 1,13.

  Entre deux zones, l'humain passe par le point de jonction (1,47 ; 0,745)
  : lignes droites, pas de navigation. Le dessous des meubles, le refuge,
  le retrait sous l'îlot et le dessous de la chaise sont hors de portée.
- **Pieds reculés de 3 cm sous le corps :** face au plan de travail, le
  bout des chaussures s'arrête à la façade (z = 0,58) et n'entre pas dans
  le retrait de plinthe.

## Route (cycle de 15,9 s mesuré)

| Point | Position | Pause | Regard pendant la pause |
|---|---|---|---|
| W1 Plan | (1,35 ; 0,72) | 2,0 s | plan de travail (nord) |
| W2 Évier | (0,80 ; 0,72) | 2,5 s | nord |
| W3 Ouest | (0,25 ; 0,72) | 1,5 s | nord |
| W4 Évier | (0,80 ; 0,72) | 1,0 s | nord |
| W5 Plan | (1,35 ; 0,72) | 0,5 s | nord |
| W6 Frigo | (1,70 ; 0,90) | 2,5 s | nord (porte du frigo) |

Marche à 0,5 m/s ; en marchant, l'humain regarde dans la direction du
déplacement.

## États et transitions

```text
ROUTINE ──vu──▶ DOUBT ──confirmation = 100 %──▶ CONFIRMED ──non vu > 0,4 s──▶ SEARCH
   ▲              │ doute oublié (0 %)              │                          │
   └──────────────┘                                 │ vu, à portée,            │ recherche finie
   ▲                                                │ délai écoulé             │ (4 s sur place,
   │                                                ▼                          │  10 s au plus)
   │                                         CAPTURE_WINDUP ──0,7 s──▶ résolution
   │                                                                   │ échec → CONFIRMED (vu) / SEARCH
   └───────────────────────────────────────────────────────────────────┴─ réussite → capture (fin)
SEARCH ──confirmation = 100 %──▶ CONFIRMED
```

- **ROUTINE** : suit les points, fait des pauses. La première image où le
  cafard est vu fait passer en DOUBT.
- **DOUBT** : l'humain s'arrête et tourne la tête vers l'endroit vu. La
  confirmation monte de 1/0,8 par seconde de vue et redescend de 1/1,5
  par seconde sans vue.
- **CONFIRMED** : s'approche de la dernière position connue, par le point
  accessible le plus proche, jusqu'à 32 cm. Il lance une capture si le
  cafard est vu, à moins de 40 cm, et si le délai de 1 s après un échec
  est écoulé.
- **SEARCH** : va au point accessible le plus proche de la dernière
  position connue, regarde vers elle en balayant ±45° pendant 4 s, puis
  reprend la routine au point le plus proche. La recherche dure 10 s au
  plus, même si le cafard reste caché.
- **CAPTURE_WINDUP** : l'humain s'arrête ; la zone rouge au sol est visible
  pendant 0,7 s.
- La **pause** existante suspend tout : l'humain est pausable, comme le
  reste du jeu.

## Perception

- 3 points sur le corps réel du cafard : centre, tête et queue à ±13 mm,
  à 4 mm du sol.
- Rayon depuis les yeux (1,60 m, 8 cm devant le corps) vers chaque point.
  Il est occulté par les collisions du décor (couche 1). Aucun point n'est
  placé artificiellement au-dessus des meubles.
- Champ de vision de ±60° autour du regard horizontal ; portée de 1,6 m à
  l'horizontale ; angle mort de 15 cm sous le corps.
- Sensibilité constante (pas de lumière ni de suspicion). Confirmation
  après **0,8 s** de vue continue.
- **Dernière position connue :** mise à jour **seulement** aux ticks où le
  cafard est vu. L'humain ne suit jamais un déplacement caché.
- **Entrée du refuge :** les 4 premiers centimètres de la cavité sont
  visibles depuis l'allée, à travers l'ouverture de 6 cm. Au-delà
  d'environ 8 cm, le plafond du refuge cache le cafard. C'est pourquoi la
  tentative démarre au **fond** du refuge (x = −0,11).

## Capture

- Portée de **0,40 m**, du centre de l'humain au cafard, à l'horizontale.
- Point visé **figé** au début de l'annonce : la position du cafard, plus
  60 % du déplacement qu'il est en train de faire (`lead`). Aucun suivi
  pendant le geste.
- Zone de **3,5 cm** de rayon autour de ce point. L'annonce dure **0,7 s**.
- À la résolution, quatre conditions : le cafard est dans la zone,
  l'humain est à portée, et rien n'arrête une main venant d'en haut, ni au
  point visé ni à la position du cafard (rayon vertical de 0,6 m). Le
  dessous des meubles, de la chaise et le refuge protègent donc.
- Échec : délai de 1 s, puis CONFIRMED si le cafard est vu, sinon SEARCH.

### Fenêtres de fuite (0,7 s d'annonce)

| Situation au début de l'annonce | Réaction | Résultat |
|---|---|---|
| Cafard immobile | Partir dans n'importe quelle direction : 5,2 cm en 0,7 s à la marche | S'échappe (> 3,5 cm) si la réaction vient dans les 0,3 s environ |
| Cafard qui marche tout droit | Continuer tout droit | **Pris** : la visée anticipe 60 % du trajet |
| Cafard qui marche | S'arrêter, ou tourner de 90° | S'échappe (≥ 3,4 cm du point visé) |
| Cafard qui sprinte (sans charge) tout droit | Continuer | S'échappe : 11 cm parcourus, visée à 6,7 cm |
| Cafard au bord d'une couverture | Y entrer (1,5 cm suffit sous l'assise de la chaise) | Capture bloquée |

En portant une miette, le cafard marche : la bonne réaction est de
**changer de mouvement**. Continuer tout droit à la marche, c'est être
pris.

**Fenêtres de passage dans la routine :** quand l'humain fait face au plan
de travail, son champ (±60°) ne couvre pas la nourriture ; quand il marche
vers l'est, il tourne le dos au refuge.
- **Nourriture :** du départ de W1 vers l'ouest jusqu'à la fin de la pause
  en W3, environ 6 s. Le trajet aller, prise, retour dure environ 4 s.
- **Refuge :** du départ de W3 vers l'est jusqu'à la fin de la pause au
  frigo, environ 7 s. La traversée chargée depuis la brèche ouest dure
  environ 5,6 s.

## Signal pour le joueur (≠ diagnostic)

- **Pas :** `HumanBrain.footstep(position, force)` à chaque foulée
  (0,45 m). Ces mêmes événements serviront à la tâche audio I.
- **ThreatCues :** un pas à moins de **0,8 m** du cafard fait apparaître
  brièvement « 〰 vibrations 〰 ». La force diminue avec la distance. Pas
  de direction, pas de position, pas de silhouette à travers les murs.
- **Zone rouge au sol** pendant l'annonce de capture.
- Le reste (état, visibilité, dernière position, zone, recherche) est du
  **diagnostic**. Il n'est visible qu'avec F3 et masqué au lancement de
  cette scène.

## Caméra et humain

L'humain n'est pas dans le masque de collision du bras de la caméra : il
ferait sauter la caméra à chaque pas. Des corps physiques attachés aux
pieds ont été essayés, mais leur position suivait mal les pieds visibles
(jusqu'à 4 cm d'écart). `HumanCameraGuard` agit donc après la caméra, à
chaque image : si la caméra est dans une chaussure ou une jambe visible,
elle est avancée vers le cafard jusqu'à en sortir. Si le pivot lui-même
est dans une chaussure (pied passant sur le cafard), cette pièce est
masquée tant que la caméra s'y trouve.

## Réglages (`data/tuning/human_tuning.tres`)

| Groupe | Réglage | Valeur |
|---|---|---|
| Déplacement | marche / approche / rotation | 0,5 m/s / 0,6 m/s / 5 rad/s |
| | arrivée / foulée | 3 cm / 0,45 m |
| Perception | yeux / portée / demi-angle / angle mort | 1,60 m / 1,6 m / 60° / 0,15 m |
| | confirmation / oubli / perte | 0,8 s / 1,5 s / 0,4 s |
| Recherche | sur place / maximum / balayage | 4 s / 10 s / ±45° |
| Capture | portée / rayon / annonce / anticipation / délai | 0,40 m / 3,5 cm / 0,7 s / 60 % / 1,0 s |
| Signal joueur | portée des vibrations | 0,8 m |

## Limites

- **Lisibilité non évaluée par un joueur.** Le haut du corps est hors
  cadre : on voit arriver des chaussures et des jambes. Le doute (humain
  qui s'arrête et se tourne) n'a pas de signal propre pour le joueur.
- **Vue du cafard pendant la recherche :** caché dans le retrait de
  plinthe, avec l'humain juste à côté, la caméra est ramenée tout près du
  cafard et **aucune partie de l'humain n'est visible**. Seules les
  vibrations le trahissent (voir `validation/threat/sequence_vue_cafard_4.7.2.jpg`,
  images 007 à 011). C'est un point à traiter avec l'audio (I) et les
  indices visuels (J).

Captures : `validation/threat/sequence_diagnostic_4.7.2.jpg` (vue de dessus
de diagnostic : haut du corps, plan de travail, caisson et assise masqués ;
anneau cyan = cafard, tige magenta = dernière position connue) et
`validation/threat/sequence_vue_cafard_4.7.2.jpg` (ce que voit le joueur).
- **Capture :** contre un cafard qui marche tout droit, l'anticipation de
  60 % rend la fuite en ligne droite inefficace ; c'est voulu, mais la
  règle doit être comprise. À valider en jeu.
- Les pieds peuvent passer visuellement sur le cafard (aucune collision
  entre eux). La caméra est protégée, mais l'image peut surprendre.
- Déplacements en lignes droites entre zones. Pas de contournement général
  d'obstacles : la route et les zones sont réglées pour ce niveau.
- Les vibrations restent un texte provisoire, en attendant l'audio (I) et
  les indices visuels (J).
- Rendu logiciel uniquement ; la scène tourne à environ la moitié du temps
  réel en headless. Aucune mesure de performance.
