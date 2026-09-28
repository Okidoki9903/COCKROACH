# Instinct et lumière (tâche J)

Deux ajouts :

- **Indices d'instinct** : les événements de la menace deviennent lisibles
  à l'écran. C'est une alternative aux sons, qui n'ont jamais été
  écoutés.
- **Une lumière commandable** : elle est reliée à l'exposition du cafard
  et à la vitesse de confirmation de l'humain.

Hors du périmètre : suspicion globale, sauvegarde, population, vision à
travers les murs, suivi permanent de l'humain.

## Lancer

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/levels/kitchen_instinct.tscn   # lumière + instinct (F6 dans l'éditeur)
$G --path . res://scenes/levels/kitchen_threat.tscn     # instinct, sans lumière (comportement historique de l'IA)
timeout 600 $G --headless --fixed-fps 60 --path . res://scenes/tests/instinct_runner.tscn   # 37/37
```

- **Réglages** (Échap) : panneau « Indices d'instinct », à gauche des
  volumes. Ils valent pour la session (ils survivent à « Recommencer ») et
  ne sont pas enregistrés.
- **Diagnostic** (F3, masqué par défaut) : état de la lumière, niveau
  d'exposition et points du corps éclairés, multiplicateur en vigueur, et
  bouton **« Basculer la lumière (diagnostic) »**. Aucune touche de jeu
  n'a été ajoutée.

## Composants

| Fichier | Rôle |
|---|---|
| `scripts/threat/threat_cues.gd` (nœud `ThreatCues`, déjà présent depuis F) | **Présentation de l'instinct** : pas, fouille, annonce de capture, badge d'exposition. Écoute seulement des événements ; ne lit ni ne modifie l'état de l'IA. Le signal `felt` et `pulse` de F sont conservés. L'ancien texte « 〰 vibrations 〰 » est remplacé par l'indice directionnel, sans doublon. |
| `scripts/instinct/instinct_settings.gd` | Réglages d'accessibilité (statiques, session) |
| `scripts/instinct/instinct_settings_panel.gd` | Panneau des réglages en pause |
| `scenes/levels/kitchen_instinct.tscn` | Composition : scène **héritée** de `kitchen_threat.tscn`, plus la lumière. « Recommencer » recharge bien cette scène. |
| `scripts/instinct/exposure_light.gd` (`ExposureLight`) | **Contrôleur unique** : allume ou éteint ensemble la lampe rendue (`Lamp`, SpotLight3D) et la zone logique (`Zone`) |
| `scripts/instinct/exposure_zone.gd` (`ExposureZone`) | Niveau d'exposition : BASE ou INCREASED |
| `scripts/instinct/instinct_debug.gd` | Diagnostic F3 de la lumière et bouton de bascule |
| `scripts/threat/human_brain.gd` | `exposure` (optionnel) et `confirm_rate_multiplier()` : seule modification de l'IA |
| `scripts/threat/human_perception.gd` | Points du corps rendus partageables (`body_samples`), sans changement de comportement |
| `scripts/threat/human_tuning.gd`, `data/tuning/human_tuning.tres` | `lit_confirm_multiplier = 1.5` (**provisoire**) |
| `scenes/tests/instinct_runner.tscn` + `.gd` | 37 contrôles ; mode `--clip` pour la séquence |

`kitchen_threat.tscn` reçoit le nouvel instinct et le panneau de réglages,
mais pas de lumière. Les scènes de référence (`scale_test`,
`kitchen_blockout`, `kitchen_loop`) sont inchangées.

## Indices d'instinct

Chaque indice naît d'un événement réel, une fois. Sa direction est
**figée à l'événement** : elle ne suit jamais l'humain entre deux
événements, et rien ne s'affiche quand l'humain ne produit rien (immobile,
en doute). Aucune distance, aucune position exacte, aucun état de l'IA
n'est affiché. Les indices se distinguent **par leur forme et un mot**, pas
seulement par leur couleur.

| Indice | Événement | Portée | Direction | Durée (renforcé ×1,5) | Forme |
|---|---|---|---|---|---|
| Pas proche | `HumanBrain.footstep` (une foulée) | < 0,8 m du pas (`cue_range`, déjà en F) | secteur de 45° autour de l'écran, relatif au **regard** (0 = devant, 2 = droite, 4 = derrière, 6 = gauche) | 0,6 s | trois arcs « ))) » + « 〰 pas » |
| Fouille proche | `HumanBrain.inspecting` (arrivée au point de recherche, retournements du balayage) | < 0,8 m du corps de l'humain (`inspect_range`) | idem, vers le corps | 1,2 s | cercle pointillé avec « ? » + « fouille » |
| Attaque annoncée | `capture_started` | toujours | — | durée de l'annonce (0,7 s) | bandeau « ⚠ ATTAQUE — BOUGE ! » + barre qui se vide ; disque sombre qui remplit la zone rouge au sol |
| Esquive | `capture_resolved(false)` | — | — | 1,2 s | « ✓ ESQUIVÉ », sans barre |
| Annulée | fin de tentative pendant l'annonce | — | — | 1,2 s | « — ATTAQUE ANNULÉE » |
| Capture | `captured` → fin | — | — | — | écran de fin existant (« Attrapé ! ») ; les effets transitoires sont effacés |

- **Force du pas :** 1 − d / 0,8 m, comme les vibrations de F. Elle donne
  une opacité entre 0,35 et 1, jamais nulle et jamais éblouissante.
- **Animation normale :** une seule impulsion. L'indice grandit de 30 % et
  s'estompe sur sa durée, sans répétition ni clignotement.
- **Zone hors champ :** le bandeau ne dépend pas de la vue. Si la zone
  n'est pas dans le cadre de la caméra, il ajoute « zone hors champ :
  derrière / à gauche… ».
- **Annulation :** l'IA n'a pas d'autre annulation de l'annonce que la fin
  de tentative (sortie réussie pendant l'annonce). Pause et
  recommencement ne sont pas des annulations.
- **Le zone rouge au sol de F est conservée telle quelle.**

## Réglages accessibles

| Réglage | Valeurs | Effet |
|---|---|---|
| Intensité | 25 à 100 % | opacité et taille des indices de pas et de fouille ; **l'avertissement d'attaque n'est pas atténué** |
| Mouvement réduit | oui / non | aucune croissance ni fondu : l'indice apparaît fixe, reste sa durée, puis disparaît. Le bandeau d'attaque et sa barre restent (information essentielle, mouvement linéaire lent, sans pulsation). |
| Indices renforcés (sans son) | oui / non | indices 1,4× plus grands, opacité au moins 0,6, textes plus gros, durées ×1,5 |

## Modèle d'exposition

C'est une **approximation de jeu**, pas une mesure physique de
luminosité. Il y a deux niveaux explicites :

- **BASE** : lumière éteinte, cafard hors du disque, ou cafard couvert ;
- **INCREASED** : la zone est active, et au moins un des 3 points du corps
  (les mêmes que ceux regardés par l'humain) est à la fois dans le disque
  éclairé et en ligne directe avec la lampe (rayon sur la couche 1).

| Paramètre | Valeur |
|---|---|
| Lampe | SpotLight3D à (0,45 ; 1,50 ; 0,95), dirigée vers le sol, angle 14°, énergie 2,5, ombres |
| Disque utile | centre (0,45 ; 0,95), **rayon 0,30 m** (le cône rendu couvre environ 0,37 m ; son bord atténué n'est pas compté) |
| Occultation | rayon lampe → point du corps, couche 1 : l'assise de la chaise, un meuble ou un obstacle bloquent |
| État initial | allumée (`start_on`) |

**Couplage avec la confirmation** (`HumanBrain.confirm_rate_multiplier`) :

- quand le cafard est **vu** et **exposé**, la confirmation monte 1,5 fois
  plus vite ;
- sinon, elle monte à la vitesse historique.

Ce multiplicateur est centralisé dans `HumanTuning.lit_confirm_multiplier`
et reste **provisoire**.

- **Portée, champ, occultation de la vue :** inchangés. La lumière
  n'intervient qu'après `perception.update()`, sur les gains de
  confirmation. Elle ne fait jamais voir à travers un obstacle, et une
  lumière éteinte ne rend pas invisible.
- **Oubli :** vitesse inchangée.
- **Bascule pendant une confirmation engagée :** la valeur accumulée est
  conservée ; seule la vitesse change, dès le tick suivant. Il n'y a pas
  de remise à zéro.
- **Sans zone** (`exposure` vide : `kitchen_threat`, et toute scène
  antérieure) : multiplicateur 1, comportement historique.
- La lumière n'est jamais synchronisée automatiquement avec la cachette
  du joueur. Elle ne change que par son contrôleur (bouton de diagnostic
  ou script).

**Indicateur joueur :** « ☀ Exposé à la lumière », en haut à gauche, suit
l'état logique de la zone. Il ne signifie jamais « repéré ». « ⚠
ATTAQUE » est un bandeau distinct, en haut au centre. Le pourcentage de
confirmation reste réservé au diagnostic (F3).

## Cycle de vie

- **Pause :** le composant est pausable. Les indices ne vieillissent pas,
  la barre d'attaque et le disque sont figés. L'humain étant suspendu,
  aucun événement n'arrive, et la reprise ne rejoue rien.
- **Fin de tentative :** les indices, la barre et le disque sont effacés,
  le badge d'exposition est masqué. Seul « ATTAQUE ANNULÉE » peut
  s'afficher (fin pendant l'annonce).
- **Recommencer :** toute la scène est reconstruite. Connexions et nœuds
  restent en nombre constant (testé sur 4 redémarrages).

## Vérifications (2026-09-28)

`instinct_runner` : **37/37**.

| Contrôle | Résultat |
|---|---|
| `kitchen_threat` sans zone : multiplicateur 1, confirmation en 48 ticks (0,8 s) | OK |
| Lampe visible ⇔ zone active, 3 bascules ; lampe dirigée vers le sol | OK |
| Réglages de capture et de vue inchangés ; multiplicateur 1,5 | OK |
| À découvert : exposé allumé (3/3 points), pas éteint ; sous l'assise de la chaise (dans le disque) : non exposé ; hors disque : base | OK |
| Confirmation : éteint 48 ticks, allumé 32 ticks (0,53 s), sous l'assise jamais accélérée | OK |
| Exposé derrière un écran de 40 cm : invisible, confirmation 0 | OK |
| Bascule après 20 ticks (0,425) : valeur conservée, croissance monotone, confirmé à 39 ticks | OK |
| Pas à 0,3 m : droite → secteur 2, devant → 0, demi-tour → 6 ; force 0,62 ; pas à 1 m ignoré | OK |
| Humain déplacé tout près sans pas : aucun indice | OK |
| Cycle de routine réel : 6 pas, 5 proches → 5 indices | OK |
| Recherche réelle : 3 inspections → 3 indices de fouille, aucun indice de pas pendant l'inspection ; inspection lointaine ignorée ; humain immobile → rien | OK |
| Annonce : bandeau, disque qui se remplit, barre à 0,35 s après 20 ticks ; capture → tout effacé | OK |
| Esquive → « ESQUIVÉ », puis disparition ; sortie réussie pendant l'annonce → « ANNULÉE » | OK |
| Zone derrière la caméra : bandeau affiché, direction « derrière » | OK |
| Son coupé et mouvement réduit : indice fixe (opacité 0,76 et échelle 1 constantes) puis retiré ; l'annonce reste affichée | OK |
| Normal : une impulsion ; renforcé : 1,4×, opacité ≥ 0,6, 0,9 s ; intensité 25 % plus discrète | OK |
| Pause : indice et barre figés, aucun événement rejoué | OK |
| 4 redémarrages : connexions (pas 2, fouille 2, annonce 2, fin 2), 1 lumière, 2 disques par humain : inchangés | OK |

**Validité du test :** 7 défauts injectés, tous détectés :

- indice continu qui suit l'humain ;
- lumière sans occultation ;
- lumière qui rend visible ;
- lampe basculée sans la zone ;
- direction fixe dans le monde ;
- remise à zéro du doute à chaque changement d'exposition (la première
  version de cette mutation n'était pas détectable et a été corrigée) ;
- bandeau non effacé en fin de tentative.

**Non-régression :** avec les commandes documentées de chaque suite :

| Suite | Résultat |
|---|---|
| B (entrées) | 57/57 |
| C (caméra) | 54/54 |
| D (déplacement) | 47/47 |
| E (cuisine) | 52/52 |
| G (boucle de ressources) | 66/66 |
| F (humain) | 36/36 |
| Essais de capture | 7/7 |
| Audio | 27/27 |

La scène principale est identique au pixel près.

## Vues et séquences (rendu logiciel)

Toutes sont dans `docs/validation/instinct/`.

- `lumiere_zone_4.7.2.jpg` : vue de dessus de diagnostic, lumière
  éteinte puis allumée, avec le disque logique en cyan ; vues du cafard à
  découvert (badge présent) et sous l'assise (ombre, pas de badge). La
  flaque rendue et le disque coïncident, le bord atténué débordant un
  peu.
- `sequence_avec_son_4.7.2.jpg` et `sequence_sans_son_renforce_4.7.2.jpg` :
  9 images de la séquence approche → inspection → lumière → capture
  annoncée, vue du cafard, diagnostic masqué. La version sans son a le
  Master coupé (crête audio mesurée : silence) et les indices renforcés.
  - pas et esquive : réels, venus de l'IA ;
  - fouille : 3 inspections réelles ;
  - lumière : allumée par le contrôleur pendant que le cafard est couvert
    (pas de badge) ;
  - cafard ensuite à découvert dans la flaque (badge), confirmé puis
    capturé.
- `sequence_marqueurs.json` : les 17 indices montrés, avec leur temps et
  leur secteur. Ils sont identiques dans les deux versions.

Les deux vidéos AVI (640×360, 49 s, environ 25 Mo chacune) ne sont pas
versionnées. Elles se régénèrent avec le mode `--clip`
(`TEST_CHECKLIST.md`).

## Limites et contrôles manuels restants

- **Non évalué par un joueur :**
  - compréhension spontanée des arcs et du « ? » ;
  - surcharge visuelle ;
  - perception de l'exposition (badge et flaque de lumière) ;
  - lisibilité du bandeau en 0,7 s ;
  - possibilité de comprendre et d'esquiver **la première** capture.

  Les tests automatiques ne disent rien du confort du temps de réaction.
- **L'audio n'a toujours pas été écouté** (tâche I) : cela reste un
  contrôle non réalisé.
- La direction par secteurs de 45° peut surprendre près des frontières
  entre secteurs. Elle n'indique ni distance ni hauteur.
- Le disque logique est un cercle fixe ; la lumière rendue a un bord
  atténué. Dans l'anneau entre 0,30 et 0,37 m, le cafard est un peu
  éclairé à l'écran sans être « exposé ».
- Un seul point de lumière. Il n'y a pas de niveau intermédiaire, ni
  d'influence de la lumière de la pièce.
- Le mouvement réduit garde le remplissage du disque et la barre, deux
  mouvements linéaires lents jugés essentiels. À valider avec des joueurs
  sensibles au mouvement.
