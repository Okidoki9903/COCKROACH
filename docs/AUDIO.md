# Audio de la menace (tâche I)

Première couche audio : faire comprendre, **depuis la caméra du cafard**,
l'approche, la recherche et la tentative de capture de l'humain. Il n'y a
ni musique, ni voix, ni suspicion, ni nouvelle menace. Les indices visuels
existants sont conservés (zone rouge, « vibrations », message de fin) : le
son n'est jamais le seul moyen de percevoir une capture.

> **Écoute humaine : non faite.** Toutes les vérifications ci-dessous
> portent sur les événements et le signal (chargement, routage, niveaux,
> différences entre canaux). Timbre, confort, localisation perçue et
> lisibilité à l'oreille **ne sont pas validés**.

## Jouer et régler le volume

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64
$G --path . res://scenes/levels/kitchen_threat.tscn      # F6 dans l'éditeur ; casque conseillé
```

- **Volume :** Échap (pause), puis trois curseurs sous le menu de pause :
  - « Général » (bus Master) ;
  - « Humain » (bus Threat) ;
  - « Ambiance » (bus Ambience).

  Ils vont de 0 à 100 % du niveau nominal, jamais au-delà, pour garder la
  marge. 0 % coupe le bus. Les réglages valent pour la session : ils
  survivent à « Recommencer », mais ne sont pas enregistrés.
- **Diagnostic :** F3 liste, sous l'état de l'humain, les 6 derniers sons
  émis, avec leur type, leur distance aux oreilles, leur niveau et
  l'éventuelle occultation. C'est un contrôle des événements : il ne
  remplace pas l'écoute et reste masqué par défaut.

## Fichiers

| Fichier | Rôle |
|---|---|
| `scripts/audio/threat_audio.gd` (`ThreatAudio`, nœud `ThreatAudio` de `kitchen_threat.tscn`) | Présentation : écoute les événements, place l'écouteur, joue les sons |
| `scripts/audio/audio_settings.gd` (`AudioSettings`, nœud `AudioSettings`) | Curseurs de volume, visibles en pause seulement |
| `default_bus_layout.tres` | Bus Master (limiteur), Threat, Ambience |
| `assets/audio/*.wav` (+ `.import`) | 9 sons provisoires |
| `tools/gen_audio.py` | Générateur de ces sons |
| `tools/analyze_audio.py` | Analyse du signal enregistré (niveaux, canaux, attaque, frise) |
| `scripts/threat/human_brain.gd` | **Un seul ajout :** le signal `inspecting(point)` |
| `scripts/threat/threat_debug.gd` | Liste des derniers sons dans le diagnostic F3 |
| `scenes/tests/audio_runner.tscn` + `.gd` | Contrôles (27) ; modes `--probe` et `--clip` pour le signal |
| `scenes/tests/capture_trials_runner.tscn` + `.gd` | Essais de capture documentés dans `HUMAN_AI.md` (7) |

## Événements → sons

`ThreatAudio` n'écoute que des événements. Il ne lit pas l'état de l'IA et
ne le modifie pas. Chaque événement donne **au plus un son**, et rien ne
joue entre deux événements : un humain immobile est silencieux, même en
doute. Il n'y a pas de sonar.

| Événement (existant sauf mention) | Son | Source (position) |
|---|---|---|
| `HumanBrain.footstep` (chaque foulée de 0,45 m, environ 1 par seconde en marche) | pas : talon puis semelle, 3 variantes | la chaussure qui se pose, à 3,5 cm du sol |
| `HumanBrain.inspecting` (**ajouté**) : arrivée au point de recherche, puis chaque retournement du balayage (3 fois par recherche complète) | froissement de tissu | les jambes de l'humain, à 0,5 m |
| `HumanBrain.capture_started` | annonce : souffle montant de la main, 0,45 s, audible dès 15 ms | 25 cm au-dessus du point visé |
| `HumanBrain.capture_resolved(false)` | raté : claque de la main sur le sol, claire et brève | le point visé |
| `KitchenThreat.outcome("capture")` | attrapé : coup sourd de main refermée, plus grave et plus long que le raté, sans craquement | le point visé |
| `KitchenThreat.outcome("reussite")` | deux notes douces (non positionnel) | — |

Une capture réussie ne joue pas le son « raté » : son retour est le son
final, émis une seule fois.

## Provenance et licence des sons

Les 9 fichiers sont **synthétisés localement** par `tools/gen_audio.py`,
en Python standard uniquement : sinusoïdes, bruit à graine fixe et filtres
(biquad, filtre d'état). Il n'y a ni échantillon, ni enregistrement, ni
téléchargement, ni fichier tiers : aucune licence tierce ne s'applique. Le
dépôt n'a pas encore de fichier de licence ; les sons suivront celle que
son auteur choisira. Relancer le script redonne les mêmes fichiers octet
pour octet (vérifié par empreinte MD5).

| Fichier | Durée | Crête | Contenu |
|---|---|---|---|
| `step_a/b/c.wav` | 0,26 s | −9 dBFS | coup grave glissant de 100 à 50 Hz, clic de talon vers 800 Hz, semelle filtrée |
| `rustle.wav` | 0,75 s | −6 dBFS | grains de bruit filtré entre 1,8 et 6,5 kHz |
| `capture_announce.wav` | 0,45 s | −8 dBFS | bruit passe-bande montant de 350 à 1 900 Hz |
| `capture_miss.wav` | 0,35 s | −6 dBFS | claque aiguë, 18 ms, et corps à 190 Hz |
| `capture_caught.wav` | 0,70 s | −6 dBFS | coup sourd à 120 → 62 Hz et résonance étouffée à 260 Hz |
| `outing_success.wav` | 0,90 s | −12 dBFS | ré (587 Hz) puis la (880 Hz) |
| `kitchen_hum.wav` | 4,0 s, **boucle** | −18 dBFS | ronronnement de frigo : 50/100/150 Hz et partiels, tous périodiques sur 4 s |

Import Godot : WAV compressé QOA (réglage par défaut). La boucle
`kitchen_hum` est réglée dans son `.import` (`edit/loop_mode=2`).

**Variation :** pour les pas, le froissement et le raté, la hauteur varie
de ±6 % et le volume de ±1,5 dB. Le générateur aléatoire a une graine
fixe (`random_seed`), donc les essais se répètent à l'identique.

## Écouteur

- Un `AudioListener3D` placé **sur le cafard**, à 12 mm au-dessus de son
  origine (hauteur du pivot de caméra). Il est mis à jour à chaque tick
  physique et à chaque image, après la caméra.
- Il est orienté par le **lacet du regard** (`CameraRig.yaw`) seulement.
  L'inclinaison de la caméra et sa distance (rapprochée contre un mur ou
  sous un meuble) n'y changent rien.
- Aucune modification de la caméra.

## Spatialisation et occultation

Tous les réglages sont exportés sur le nœud `ThreatAudio`.

| Réglage | Valeur | Effet |
|---|---|---|
| Modèle | distance inverse | −6 dB par doublement de distance |
| `step_unit_size` / `body_unit_size` | 0,30 m / 0,40 m | pleine intensité à cette distance |
| `max_distance` | 2,6 m | silencieux au-delà (toute la cuisine est à portée) |
| `max_db` des lecteurs | 0 dB | jamais d'amplification au contact |
| `panning_strength` | 1,5 (× 0,5 du projet) | écart gauche/droite d'environ 10 dB pour un pas de côté à 0,3 m |
| `occlusion_db` / `occlusion_cutoff_hz` | −6 dB / 2,5 kHz | si un rayon oreilles → source touche le décor (couche 1) |
| Doppler | désactivé | |

L'occultation est **bornée** : derrière la plinthe ou sous un meuble, un
pas est assourdi et filtré, jamais muet. Elle est calculée une fois, au
début de chaque son.

## Bus et niveaux

| Bus | Envoi | Effet | Contenu |
|---|---|---|---|
| Master | — | limiteur dur, plafond −1 dBFS | tout |
| Threat | Master | — | pas, froissement, annonce, raté, attrapé, réussite |
| Ambience | Master | — | ronronnement (lecteur à −16 dB) |

**Marge :** les fichiers sont normalisés entre −6 et −18 dBFS, et les
lecteurs ne dépassent jamais 0 dB. La crête mesurée est de −7,0 dBFS sur
la sonde et de −9,3 dBFS sur le scénario. Aucun échantillon n'atteint le
plafond de −1 dBFS.

**L'ambiance ne masque pas l'annonce.** Le ronronnement est grave (moins
de 900 Hz) et bas : −42 dBFS RMS. Dans la bande de l'annonce
(400–2 000 Hz), l'ambiance est à −63,6 dBFS ; l'annonce, à 0,24 m, est
**30 dB** au-dessus.

## Cycle de vie

- **Pause** (le jeu existant) : les lecteurs de l'humain sont pausables.
  Godot suspend un son en cours (`stream_paused`, léger fondu) et le
  reprend là où il était. Aucun événement n'est produit en pause, puisque
  l'humain est suspendu : rien ne s'accumule, et la reprise ne produit pas
  de rafale. L'ambiance continue pendant la pause, pour pouvoir régler son
  volume. Un son déclenché dans le tick même de la pause ne démarre qu'à
  la reprise : observé, joué une seule fois.
- **Fin de tentative :** au premier `outcome`, les lecteurs de l'humain
  s'arrêtent et un seul retour final joue. Tout événement ultérieur est
  ignoré.
- **Recommencer :** la scène entière est reconstruite. L'ancienne
  présentation, avec ses lecteurs et son écouteur, est libérée, et la
  nouvelle devient l'écouteur courant. Aucune source ni connexion n'est
  dupliquée (testé sur 5 redémarrages).

## Vérifications (2026-09-28)

### Automatiques, sans rendu

`audio_runner` : **27/27**.

```sh
$G --headless --fixed-fps 60 --path . res://scenes/tests/audio_runner.tscn
```

| Contrôle | Résultat |
|---|---|
| Bus, envois, limiteur ; 9 sons chargés ; routage des lecteurs ; boucle d'ambiance | OK |
| Écouteur courant = celui du cafard ; caméra de 0,012 à 0,125 m, écouteur toujours à 12 mm au-dessus du cafard | OK |
| Écouteur tourné par le lacet (4 orientations), pas par l'inclinaison (−60°) | OK |
| Cycle de routine : 6 événements de pas → 6 sons, dans le même tick ; 675 ticks immobile → 0 son ; rien d'autre que des pas | OK |
| Humain arrêté en doute, face au cafard : silencieux | OK |
| Recherche : 3 inspections → 3 froissements, humain arrêté en recherche | OK |
| Pause pendant un froissement, puis pendant l'annonce : son suspendu (avance de 0,012 s, le fondu, pendant 250 ms réelles ; l'ambiance avance de 0,28 s), 0 son émis en pause, 0 dans les 10 ticks après la reprise | OK |
| Capture : 1 annonce, 1 « attrapé », 0 « raté » ; autres lecteurs arrêtés ; plus aucun son pendant 2 s | OK |
| Capture esquivée : 1 « raté », la tentative continue | OK |
| Sortie réussie : un seul retour final | OK |
| 5 redémarrages : 8 lecteurs, 2 connexions aux pas (vibrations + audio), inchangés ; ancienne présentation libérée ; un son par pas | OK |
| Occultation derrière la plinthe, directe à découvert ; bornée à −6 dB | OK |

**Validité du test :** 7 défauts injectés un par un, tous détectés :
- double connexion aux pas ;
- écouteur sur la caméra ;
- lecteurs non pausables ;
- sons non arrêtés à la fin ;
- froissement sur chaque pas ;
- lecteurs laissés hors de la scène ;
- son d'échec joué aussi lors d'une capture réussie.

Le sixième n'était pas détecté au premier essai : le comptage se limitait
au runner. Il porte maintenant sur tout l'arbre.

**Règles de capture inchangées :** `capture_trials_runner` donne **7/7**
(réglages identiques, et 6 essais au résultat attendu, voir
`HUMAN_AI.md`). `threat_runner` donne **36/36**, sans modification.

### Signal enregistré (movie writer, rendu logiciel)

Le movie writer de Godot mixe l'audio image par image, de façon
déterministe, et l'enregistre en stéréo 48 kHz. Ce n'est pas une écoute.

```sh
# Sonde calibrée : WAV + marqueurs
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
  $G --fixed-fps 60 --write-movie /tmp/p/probe.png --path . res://scenes/tests/audio_runner.tscn -- --probe=/tmp/p
python3 tools/analyze_audio.py /tmp/p/probe.wav /tmp/p/markers.json --timeline /tmp/p/frise.png
# Scénario vu et entendu du cafard (AVI MJPEG + PCM), 640×360 via un override.cfg temporaire :
#   [display] window/size/window_width_override=640, window_height_override=360, window/stretch/mode="canvas_items"
... $G --fixed-fps 30 --write-movie /tmp/c/clip.avi --path . res://scenes/tests/audio_runner.tscn -- --clip=/tmp/c
python3 tools/analyze_audio.py /tmp/c/clip.avi /tmp/c/markers.json --timeline /tmp/c/frise.png --export /tmp/c/clip.wav
```

**Sonde** (`validation/audio/sonde_analyse.txt`, `sonde_frise_4.7.2.png`) :
sans variation aléatoire, humain arrêté, un son à la fois.

| Cas | RMS G / D (dBFS) | G − D |
|---|---|---|
| Ambiance seule | −42,3 / −42,3 | 0 |
| Pas à 0,30 m à droite (regard nord) | −36,9 / −26,7 | −10,3 dB |
| Pas à 0,30 m à gauche | −27,4 / −37,2 | +9,8 dB |
| Pas à 1,20 m à droite | −42,9 / −41,1 (crête −32,0 contre −11,3 à 0,30 m) | −1,8 dB |
| Même pas à droite, regard **sud** | −26,8 / −37,2 | **+10,4 dB (inversé)** |
| Même pas, regard **vers** lui | −28,9 / −28,9 | 0 |
| Pas à droite, **caméra à 2 cm** | −37,2 / −26,7 | −10,5 dB (identique à caméra normale) |
| Pas à 0,30 m derrière la plinthe (occulté) | −32,9 / −40,7 | crête −19,7 contre −12,3 à découvert, même disposition |

- **Proche/loin :** −21 dB de crête entre 0,3 et 1,2 m.
- **Gauche/droite :** environ ±10 dB, inversé quand le regard tourne de
  180°.
- **Distance de caméra :** sans effet mesurable (±0,3 dB).
- **Occultation :** environ −7 dB en crête, avec perte d'aigus.
- **Attaque :** 21 à 37 ms après l'événement (1 à 2 ticks : les lecteurs
  3D démarrent au tick physique suivant) ; 69 ms pour le froissement, dont
  les grains montent progressivement.

**Scénario** (`validation/audio/`) :
- `scenario_menace_stereo_4.7.2.wav` : 41,9 s, stéréo, 24 kHz, 16 bits ;
- `scenario_frise_4.7.2.png` : frise G/D avec les événements ;
- `scenario_images_4.7.2.jpg` : 6 images de la caméra du cafard ;
- `scenario_analyse.txt` et `scenario_marqueurs.json`.

La vidéo complète (AVI de 20 Mo) n'est pas versionnée : elle se
régénère avec la commande ci-dessus. Le scénario utilise l'IA réelle et
les commandes du joueur, sans téléportation après la mise en place.

| Temps | Moment | Ce que mesure le signal |
|---|---|---|
| 0–12,7 s | Caché sous les meubles, face au mur ; l'humain approche de derrière à droite, s'arrête à l'évier à 0,33 m, repart, repasse | 5 pas, **tous occultés** (−5 à −6 dB), crêtes de −20 à −33 dBFS ; côté variable selon la position (±2 à 4 dB) |
| 12,7–17,4 s | Sortie par la brèche pendant la pause au frigo ; l'humain revient et repère le cafard | pas non occultés, de plus en plus proches |
| 18,5 s | Annonce pendant la fuite au sprint | annonce −11,5 dBFS de crête ; **raté** à 19,2 s (esquive réelle) |
| 20,1 / 21,1 / 23,1 s | Recherche juste à côté du retrait de plinthe ; **l'humain n'est pas à l'image** | 3 froissements, occultés, crêtes −28 à −31 dBFS (ambiance : crête −35,7, et une autre bande de fréquences) |
| 24–38 s | Retour à la routine, pas qui s'éloignent puis reviennent | pas de 0,23 à 1,02 m |
| 38,6 s | Cafard immobile à découvert : annonce | annonce centrée (la main est au-dessus du cafard) |
| 39,3 s | Capture | « attrapé » −9,3 dBFS de crête, puis silence de l'humain ; message « Attrapé ! » à l'écran |

Synchronisation : chaque son commence 15 à 63 ms après son événement.
Deux attaques sont mal mesurées, parce qu'un son précédent masque le seuil
de détection : l'annonce à 18,46 s (juste après un pas) et le premier
froissement.

## Limites et contrôles restants

- **À écouter (casque puis haut-parleurs), non fait :**
  - timbre et crédibilité des sons synthétiques ;
  - confort (répétition des pas, niveau du ronronnement) ;
  - localisation perçue gauche/droite et devant/derrière ;
  - lisibilité de l'annonce et différence raté/attrapé ;
  - audibilité des froissements près de la cachette ;
  - utilité réelle pour le joueur.
- **Devant/derrière :** la stéréo seule ne les distingue pas (pas de
  HRTF). Un pas devant et un pas derrière donnent le même équilibre.
- **Pas espacés :** environ un pas par seconde à 0,5 m/s, avec une
  foulée de 0,45 m, qui est une règle de l'IA et n'a pas été changée. Un
  humain qui s'arrête devient silencieux, comme demandé ; le doute
  (arrêt, regard) n'a pas de son propre.
- L'occultation est un rayon unique au début de chaque son : elle ne
  suit pas un son long si le cafard passe derrière un obstacle pendant
  qu'il joue.
- L'ambiance est un seul ronronnement non positionnel ; il n'y a pas de
  réverbération.
- À la fermeture, Godot signale une fuite d'un flux en lecture (« 2
  ObjectDB instances leaked », `kitchen_hum.wav`). C'est reproduit avec
  un simple `AudioStreamPlayer` en boucle, sans ce projet : comportement
  du moteur quand on quitte pendant une lecture en boucle, sans effet en
  jeu.
- Les pilotes audio réels (PulseAudio, ALSA) ne sont pas exercés : le
  conteneur n'a que le pilote factice et le mixage du movie writer.
