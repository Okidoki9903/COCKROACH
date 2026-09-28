# Checklist de test

Version du moteur fixée : **Godot 4.7.2-stable, édition standard officielle**
(`4.7.2.stable.official.ed1daf0bf`). Rendu cible : Forward+ (Vulkan).

## Lancement

### Machine locale (avec écran)

1. Installer Godot 4.7.2-stable (édition standard, pas .NET).
2. Gestionnaire de projets → *Importer* → `project.godot` à la racine.
3. Lancer avec **F5** (scène principale), pas F6.

### Ligne de commande (conteneur ou CI)

```sh
G=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64

# 1. Importation : génère le cache .godot/ (ignoré par git)
$G --headless --path . --import

# 2. Exécution bornée, sans rendu : ~2 s puis sortie
$G --headless --path . --verbose --quit-after 120

# 3. Rendu réel avec capture (Xvfb + Vulkan logiciel lavapipe)
#    Paquets requis : xvfb, mesa-vulkan-drivers, libvulkan1
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
xvfb-run -a -s "-screen 0 1280x720x24" \
  $G --path . --write-movie /tmp/frames/f.png --fixed-fps 30 --quit-after 60
```

Sans pilote Vulkan, Godot bascule automatiquement vers OpenGL
(Compatibility), ce qui n'est **pas** le rendu cible. Vérifier que le journal
affiche la ligne `Vulkan … - Forward+`.

## Contrôles

Légende : **S** statique · **I** importation · **E** exécution · **V** visuel

| Type | Contrôle | 2026-09-28 (4.7.2) |
|---|---|---|
| S | Références de ressources, chemins et parents des nœuds cohérents | ✅ |
| I | Import sans erreur ni avertissement (code de sortie 0) | ✅ |
| E | Exécution sans erreur ni avertissement (code de sortie 0) | ✅ |
| E | `boot.tscn` charge `scale_test.tscn` (journal `--verbose`) | ✅ |
| V | Le repère cafard brun (3 cm) est visible en avant-plan | ✅ capture |
| V | La barre jaune de 10 cm est visible ; le repère fait environ un tiers de sa longueur | ✅ capture |
| V | Le meuble brun occupe l'arrière-plan et paraît gigantesque | ✅ capture |
| V | L'ombre portée du repère est visible et attachée à sa base | ✅ capture (après correction) |
| V | Pas d'objet coupé par le plan proche ; pas d'acné d'ombre | ✅ capture |
| V | Pas de scintillement : 55 images consécutives identiques au pixel près | ✅ caméra et scène statiques seulement |
| V | Scintillement en mouvement de caméra | ⏳ impossible à tester avant la tâche C |
| V | Rendu sur GPU réel, fenêtre interactive (F5) | ⏳ non exécuté (rendu logiciel seulement) |
| V | Contrôles dans l'éditeur (inspecteur, paramètres du projet) | ⏳ non exécutés (pas d'éditeur interactif) |

L'ombre du meuble tombe hors du champ de la caméra, par construction. Ce
n'est pas un contrôle attendu.

Capture de référence :
`docs/validation/scale_test_forward_plus_4.7.2.png` (Forward+, lavapipe,
1280×720, image 59).

## Contrôles dans l'éditeur (à faire sur une machine avec écran)

- [ ] `scale_test.tscn` s'ouvre sans ressource manquante.
- [ ] `CockroachMarker` : taille du maillage (0,012 ; 0,006 ; 0,03).
- [ ] *Projet → Paramètres → Application → Exécuter* : scène principale
      = `res://scenes/boot/boot.tscn`.
- [ ] Après sauvegarde dans l'éditeur, committer les attributs `uid=`
      ajoutés aux scènes.

## Fichiers générés par Godot

- `.godot/` : cache local, ignoré par `.gitignore`. Ne pas committer.
- `*.uid` à côté des scripts (ex. `scripts/boot/boot.gd.uid`) : **committer**.
- Attributs `uid=` ajoutés aux scènes lors d'une sauvegarde dans l'éditeur :
  **committer**.
- `*.import`, quand des assets seront ajoutés : **committer**.

## Étape B — entrées joueur

Automatique (à relancer après toute modification des entrées) :

```sh
$G --headless --path . res://scenes/tests/input_test_runner.tscn   # attendu : code 0, 57/57
```

Manuel, sur machine réelle : lancer `scenes/tests/input_test.tscn` (F6) et
lire le panneau en haut à gauche.

| Contrôle | Attendu | Statut |
|---|---|---|
| Z/W seul, puis S, Q/A, D | (0 ; 1), (0 ; −1), (−1 ; 0), (1 ; 0) | ✅ simulé · ✅ X11 partiel · ⏳ clavier physique |
| Diagonale | longueur 1,00 | ✅ simulé · ✅ X11 · ⏳ clavier physique |
| Opposés | 0 | ✅ simulé · ✅ X11 (W+D+S) · ⏳ clavier physique |
| Relâcher tout | 0 | ✅ simulé · ✅ X11 · ⏳ clavier physique |
| Maj gauche, puis Maj droite | sprint ON | ✅ simulé (gauche) · ⏳ clavier physique (les deux) |
| E maintenu | interact +1 seulement | ✅ simulé (répétitions) · ✅ X11 · ⏳ clavier physique |
| A (AZERTY) ou Q (QWERTY) | drop +1, pas de déplacement | ✅ simulé · ✅ X11 (Q) · ⏳ AZERTY physique |
| Échap, puis E et ZQSD | PAUSED, compteurs et vecteur figés à 0 | ✅ simulé · ✅ X11 · ⏳ clavier physique |
| Échap à nouveau | running | ✅ simulé · ✅ X11 · ⏳ clavier physique |
| Z enfoncé + Alt+Tab, relâcher, revenir | PAUSED, vecteur 0, pas de reprise seule | ✅ simulé · ✅ X11 · ⏳ bureau réel |
| Scène principale (F5) | inchangée | ✅ rendu identique au pixel près |

## Étape C — caméra

Automatique :

```sh
$G --headless --path . res://scenes/tests/camera_test_runner.tscn   # attendu : code 0, 54/54
$G --headless --path . res://scenes/tests/input_test_runner.tscn    # non-régression B : 57/57
```

Manuel, sur machine réelle : lancer `scenes/tests/camera_test.tscn` (F6).

| Contrôle | Attendu | Statut |
|---|---|---|
| Souris à droite / en haut | la vue tourne à droite / regarde en haut | ✅ simulé · ✅ X11 · ⏳ souris physique |
| Tangage extrême | bloqué à −70° / +10°, jamais retourné | ✅ simulé · ⏳ souris physique |
| Boutons Mur, Coin, PassageEtroit | caméra rapprochée, aucun mur traversé | ✅ simulé · ✅ capture · ⏳ GPU réel |
| Tour complet contre un mur | pas de décor coupé, pas de tremblement gênant | ✅ simulé (0/576 image fautive) · ✅ capture · ⏳ confort réel |
| Obstacle retiré | retour progressif (≈ 0,4 s) | ✅ simulé |
| Échap | souris libre, vue figée, boutons cliquables | ✅ simulé · ✅ X11 · ⏳ souris physique |
| Échap à nouveau | souris capturée, **aucun saut** | ✅ simulé · ✅ X11 · ⏳ souris physique |
| Alt+Tab en bougeant la souris, retour | reste en pause, souris libre, pas de saut à la reprise | ✅ simulé · ✅ X11 · ⏳ bureau réel |
| Écran à plus de 60 Hz | rotation fluide | ⏳ non testable ici |
| Performance | 60 images/s sur la machine de référence | ⏳ non mesurée (rendu logiciel) |

## Étape D — locomotion

Automatique :

```sh
$G --headless --fixed-fps 60 --path . res://scenes/tests/movement_test_runner.tscn   # attendu : code 0, 47/47
$G --headless --path . res://scenes/tests/camera_test_runner.tscn                    # C : 54/54
$G --headless --path . res://scenes/tests/input_test_runner.tscn                     # B : 57/57
```

Manuel, sur machine réelle : lancer `scenes/tests/movement_test.tscn` (F6).

| Contrôle | Attendu | Statut |
|---|---|---|
| Z seul, puis Maj | 0,08 puis 0,16 m/s, visuel orienté vers l'avant | ✅ simulé · ✅ X11 · ⏳ clavier physique |
| Regarder vers le bas et avancer | même vitesse horizontale | ✅ simulé |
| Diagonale | pas plus vite que l'axe | ✅ simulé |
| Longer le mur, pousser dans le coin | ni vibration ni blocage | ✅ simulé · ✅ capture · ⏳ confort réel |
| Joint de sol (bouton Joint) | aucun accroc | ✅ simulé |
| Pente, puis PenteRaide | monte / ne monte pas | ✅ simulé · ✅ capture |
| Bord | chute puis atterrissage | ✅ simulé · ✅ capture · ⏳ confort caméra |
| Passage, SousMeuble | jamais bloqué, caméra sans clipping ni respiration | ✅ simulé · ✅ capture · ⏳ confort réel |
| Échap en marche, Alt+Tab en marche | arrêt net, rien de bloqué, pas de saut | ✅ simulé · ✅ X11 · ⏳ bureau réel |
| Tourner la caméra à l'arrêt | le cafard ne tourne pas | ✅ simulé |
| Confort global des vitesses | à juger | ⏳ |
| Écran à plus de 60 Hz | fluidité du suivi | ⏳ non testable ici |

## Étape E — blockout de cuisine

Automatique :

```sh
$G --headless --fixed-fps 60 --path . res://scenes/tests/kitchen_route_runner.tscn   # attendu : code 0, 52/52
```

Manuel, sur machine réelle : lancer `scenes/levels/kitchen_blockout.tscn` (F6).
F3 masque le panneau ; Échap libère la souris pour les boutons.

| Contrôle | Attendu | Statut |
|---|---|---|
| Première sortie du refuge | on comprend où sortir et vers où aller | ✅ capture · ⏳ joueur réel |
| Route directe, aller et retour, marche puis sprint | ≈ 20 s / 10 s, destination visible en route | ✅ automatisé · ✅ capture · ⏳ joueur réel |
| Route couverte, aller et retour | ≈ 30 s / 15 s, jamais bloqué, caméra sans clipping | ✅ automatisé · ✅ séquence · ⏳ confort réel |
| Bascule par la brèche du milieu | possible dans les deux sens | ✅ automatisé |
| Détour vers l'eau | accessible, retour possible | ✅ automatisé |
| Pieds de meuble, pied de chaise, coins | pas d'accroc, visuel qui ne traverse pas | ✅ automatisé (0 pénétration) · ⏳ joueur réel |
| Rotations de caméra dans les endroits étroits | rapprochements acceptables | ⏳ confort réel |
| Retour au refuge depuis la nourriture | repère visible, chemin compris | ✅ capture (prise murale) · ⏳ joueur réel |
| Tunnel sous les meubles | pas monotone au point de gêner | ⏳ jugement manuel |

## Historique

| Date | Environnement | Godot | Résultat |
|---|---|---|---|
| 2026-09-28 | Conteneur distant | Absent | Bloqué ; contrôle statique seul |
| 2026-09-28 | Conteneur distant, Xvfb + lavapipe | 4.7.2-stable | Import et exécution OK ; ombre du repère invisible → corrigée ; capture validée |
| 2026-09-28 | Conteneur distant, Xvfb + xdotool | 4.7.2-stable | Tâche B : 57/57 simulés, contrôles X11 OK, aucune régression du rendu |
| 2026-09-28 | Conteneur distant, Xvfb + lavapipe + xdotool | 4.7.2-stable | Tâche C : 54/54 ; défaut de dégagement près des murs → corrigé ; B 57/57 ; référence identique |
| 2026-09-28 | Conteneur distant, Xvfb + lavapipe + xdotool | 4.7.2-stable | Tâche D : 47/47 ; marge 1 mm → 0,2 mm, latence d'entrée et respiration caméra corrigées ; B 57/57, C 54/54 ; référence identique |
| 2026-09-28 | Conteneur distant, Xvfb + lavapipe | 4.7.2-stable | Tâche E : 52/52 ; deux repères de lisibilité ajoutés ; B 57/57, C 54/54, D 47/47 ; référence identique |

## Script d'installation pour un environnement distant

À placer dans le *Setup script* de l'environnement cloud, qui s'exécute à la
création de chaque session. Il n'a pas été exécuté sous cette forme : ce
sont les commandes utilisées manuellement le 2026-09-28, regroupées.

```sh
set -e
GODOT_VERSION=4.7.2
DEST=/home/user/tools/godot/$GODOT_VERSION
BASE=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable
ZIP=Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
mkdir -p "$DEST" && cd "$DEST"
curl -sSLO "$BASE/SHA512-SUMS.txt"
curl -sSLO "$BASE/$ZIP"
grep " $ZIP\$" SHA512-SUMS.txt | sha512sum -c -
unzip -oq "$ZIP"
apt-get update -q && apt-get install -y -q xvfb mesa-vulkan-drivers libvulkan1
# Optionnel, pour piloter la fenêtre sous Xvfb : xdotool x11-utils imagemagick
"$DEST/Godot_v${GODOT_VERSION}-stable_linux.x86_64" --version
```
