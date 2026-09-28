# Checklist de test — Étape A (socle)

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

## Historique

| Date | Environnement | Godot | Résultat |
|---|---|---|---|
| 2026-09-28 | Conteneur distant | Absent | Bloqué ; contrôle statique seul |
| 2026-09-28 | Conteneur distant, Xvfb + lavapipe | 4.7.2-stable | Import et exécution OK ; ombre du repère invisible → corrigée ; capture validée |

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
"$DEST/Godot_v${GODOT_VERSION}-stable_linux.x86_64" --version
```
