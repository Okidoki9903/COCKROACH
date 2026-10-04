# Reverse-engineering de *Les Fourmis* — kit d'instrumentation

Bible §4 : on reconstruit **algorithmes et paramètres** (caméra, mouvement multi-surfaces, échelle).
On n'extrait ni ne redistribue code ou assets du jeu. Rien ici ne doit être commité qui vienne des
fichiers du jeu, à part des **mesures** (CSV, valeurs numériques) et nos propres notes.

*Les Fourmis* (Empire of the Ants, 2024) tourne sous **Unreal Engine 5**. Ça change tout : pas besoin
de désassembler l'exécutable à la main dans x64dbg. Le moteur expose ses objets par réflexion, donc on
peut lire en jeu les vraies valeurs de la caméra et du mouvement, avec leurs noms.

## Ce qu'il faut sur le PC Windows

| Outil | Rôle |
|---|---|
| [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) (version expérimentale récente, compatible UE5) | Injection Lua + Live View des objets en jeu + dump des classes/headers |
| Python 3 | Lancer `analysis/analyze_frames.py` |
| RenderDoc (optionnel, phase 4) | Inspecter FOV / near plane / profondeur de champ d'une frame |

Pas besoin de Cheat Engine/x64dbg pour les phases 1-4 avec UE4SS.

## Phase 1 — Cartographie (≈30 min)

1. Trouver le dossier binaire du jeu : Steam → clic droit sur le jeu → *Gérer* → *Parcourir les fichiers
   locaux* → `<Projet>/Binaries/Win64/` (le dossier qui contient `<Projet>-Win64-Shipping.exe`).
2. Y dézipper UE4SS (fichiers `dwmapi.dll` + dossier `ue4ss/`).
3. Dans `ue4ss/UE4SS-settings.ini` : `GuiConsoleEnabled = 1`, `GuiConsoleVisible = 1`.
4. Lancer le jeu. Dans la fenêtre UE4SS :
   - onglet **Dumpers** → *Dump CXX Headers* et *Dump Objects & Properties* → on obtient la liste des
     classes du jeu (le PlayerController, le pawn fourmi, son composant de mouvement, la caméra).
   - onglet **Live View** → chercher `SpringArmComponent`, `CameraComponent`, `MovementComponent`,
     et la classe du pawn joueur. Noter les noms des classes custom (préfixe du projet).
5. M'envoyer : la liste des classes custom liées au joueur/caméra/mouvement + leurs propriétés
   (copier-coller depuis le dump). C'est avec ça que je complète la table `SNAPSHOT` du mod.

## Phases 2-4 — Mesures caméra & mouvement

Installer le mod (copie, crée `out/`, active dans `mods.txt` **et** `mods.json`) :

```
powershell -ExecutionPolicy Bypass -File reverse\install_probe.ps1
```

Structure UE4SS 3.x (experimental) — tout est sous `Binaries/Win64/ue4ss/` :

```
<Projet>/Binaries/Win64/dwmapi.dll
<Projet>/Binaries/Win64/ue4ss/UE4SS-settings.ini
<Projet>/Binaries/Win64/ue4ss/Mods/mods.txt + mods.json
<Projet>/Binaries/Win64/ue4ss/Mods/CockroachProbe/Scripts/main.lua
<Projet>/Binaries/Win64/ue4ss/Mods/CockroachProbe/out/      <- sorties (chemin absolu calculé par le script)
```

En jeu :

- **F7** — snapshot des paramètres (longueur spring arm, offsets, lag, FOV, vitesses, rayon capsule…).
- **F6** — démarrer/arrêter l'enregistrement image par image (~60 Hz).
- **F8** — marqueur : appuyer à chaque changement de situation, pour découper le CSV.
- **F9** — inspection : classes + toutes les propriétés du pawn, de ses composants, du controller
  et du camera manager → `inspect_*.txt` (brut, à garder dans `reverse/_private/`, jamais commité).

Protocole d'enregistrement (un seul fichier, un **F8** entre chaque cas) :

| # | Cas | Pourquoi |
|---|---|---|
| 0 | Immobile au sol, souris immobile | Offset caméra au repos |
| 1 | Marche en ligne droite, puis arrêt net | Vitesse, accélération, **lag caméra** (besoin de transitoires) |
| 2 | Virages serrés à la souris | Lag de rotation |
| 3 | Transition sol → mur | Comment l'up du pawn et la caméra basculent |
| 4 | Marche sur le mur | Offset caméra en vertical |
| 5 | Transition mur → plafond, marche au plafond | Cas tête en bas |
| 6 | Passage dans un espace étroit / contre un obstacle | Collision du spring arm |
| 7 | Passage sous un objet (feuille, caillou) | Surface « dessous » |

Puis :

```
python reverse/analysis/analyze_frames.py frames_XXXX.csv
```

Le script sort, segment par segment : offset caméra en repère local du pawn, distance, FOV,
spring arm, vitesse, type de surface (sol/mur/plafond) et une estimation de la constante de lag.

## Ce que je fais avec les résultats

Envoie-moi (ou commite dans `reverse/data/`) : `params_*.txt`, `frames_*.csv`, la sortie du script
et la liste des classes custom. J'en tire `docs/specs/camera.md` et `docs/specs/surface-movement.md`
(specs indépendantes du moteur, Bible phase 6) puis l'implémentation Bevy.

Note : si le mouvement mural est fait par un composant custom (probable), les noms de propriétés
ne seront pas ceux d'UE standard — `GetGravityDirection` et `CharacterMovement` renverront `nan`/`-1`.
C'est normal ; les vecteurs `pawn_up` restent fiables et suffisent pour reconstruire l'algorithme.

## État (4 octobre 2026) — session réalisée

- Jeu : Empire of the Ants, **UE 5.4** (confirmé par UE4SS), `Empire/Binaries/Win64`. UE4SS experimental
  `v3.0.1-1152-ge3ba1016`.
- Classes trouvées (module `/Script/Empire`) : `APlayerPawn` (BP_PlayerPawn), `UPlayerMovementController`
  (PawnMovementComponent custom) + DataAsset `UPlayerMovementData`, `UPlayerCameraController`
  (caméra « leash »), `UCineCameraComponent`. Le mod les lit (F7) et les enregistre (F6).
- Pièges rencontrés : `LoopAsync` + `ExecuteInGameThread` à 60 Hz **fait planter le jeu** → échantillonnage avec
  `LoopInGameThreadAfterFrames(1, …)`, arrêté par `CancelDelayedAction(handle)` (`return true` ne suffit pas
  dans cette version). Les rotations (`FRotator`) reviennent en `nan` → on enregistre les vecteurs avant/haut.
  `GetVelocity()` reste à 0 (mouvement custom) → vitesse dérivée de la position.
- Mesures : `reverse/data/` (c1 à c6 + `params_baseline.txt` + `NOTES.md`).
- Analyse : `python reverse/analysis/analyze_frames.py <csv> [--timeline|--extras]`, `reverse/analysis/fit_leash.py`.
- Specs : **`docs/specs/camera.md`**, **`docs/specs/surface-movement.md`**.
- Avant d'installer le mod : `pip install lupa` (vérification de syntaxe Lua automatique dans `install_probe.ps1`).
