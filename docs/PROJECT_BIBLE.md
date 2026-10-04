# COCKROACH — Project Bible
**Version 1.0 — 4 Octobre 2026**

Document unique de référence.  
Tout le contexte, la vision, le reverse-engineering, le pipeline assets et les prochaines actions.

---

## 1. VISION CONSOLIDÉE (VERROUILLÉE)

### Feeling principal
- Mix Exploration open-world + Survie / Infiltration + Gestion de colonie légère (style Sims light).
- Principalement **immersif + un peu angoissant**.
- Le côté drôle/absurde viendra surtout de la bande-son et des situations émergentes.
- Référence émotionnelle & visuelle exacte : **Toy Story** (rapport d’échelle extrême + vie secrète des petits êtres pendant que les géants vivent normalement).

### Joueur
- Tu incarnes **principalement un seul cafard** tout le temps.
- Commence **toujours seul**.
- Option coop (2 cafards) possible plus tard.
- Switch de personnage (style GTA 5) uniquement à un stade très avancé, quand la colonie est très nombreuse.

### Colonie
- Reproduction **principalement naturelle** (après certaines conditions).
- Couche de gestion légère : il faut de la nourriture + un abri correct pour que la colonie grandisse vraiment.
- Pas de micro-gestion lourde au début.

### Monde
- Commence par **une seule maison ultra-détaillée**.
- Expansion progressive : extérieur → autres maisons → quartier (avec vie humaine réaliste : parents, enfants qui courent, etc.).

### Humains
- Comportement réaliste et intentionnel (ils agissent pour leurs propres raisons, pas juste pour chasser le joueur).
- Détection réaliste (un cafard peut passer loin sans être vu).
- Escalade de menace progressive :
  1. Produits anti-cafards
  2. Produits plus forts
  3. Appel de désinfecteurs professionnels
- Les cafards doivent s’adapter.

### Style
- Photorealiste.
- Échelle extrêmement importante.
- Maison qui paraît gigantesque.

### Technique
- Reverse-engineering **le maximum de systèmes possibles** de *Les Fourmis* (Empire of the Ants) en Rust.
- Pipeline assets moderne avec IA (image-blaster + Blender MCP).

---

## 2. CORE FANTASY (une phrase)

« Tu es un cafard dans une maison humaine qui te paraît monstrueuse. Tu explores, tu survies, tu te caches, tu construis une colonie, pendant que les géants vivent leur vie normale… jusqu’à ce qu’ils se rendent compte de ta présence. »

---

## 3. CORE GAMEPLAY LOOP (cible)

SORTIR → EXPLORER → DÉTECTER LE DANGER → FUIR → SE CACHER → RÉCUPÉRER UNE RESSOURCE → RETOURNER AU REFUGE

(Avec suspicion humaine dynamique 0-100 qui évolue.)

---

## 4. REVERSE-ENGINEERING DE *LES FOURMIS*

### Objectif
Récupérer le **feeling exact** (pas juste l’inspiration) des systèmes critiques pour les réimplémenter proprement en Rust.

### Cadre légal
- Analyse runtime, instrumentation, reconstruction d’algorithmes = OK.
- Extraction/redistribution de code source ou assets protégés = non.

### Systèmes prioritaires (ordre)
1. **Caméra 3e personne à hauteur d’insecte** (le plus important)
2. **Mouvement multi-surfaces** (murs, plafond, dessous des objets)
3. Sensation d’échelle + vitesse relative
4. Perception limitée / détection
5. Simulation d’agents (plus tard)

### Structure pratique (6 phases)
**Phase 0 — Préparation**
- Jeu légalement possédé
- Outils : x64dbg / Cheat Engine, Process Hacker, RenderDoc, memory scanners

**Phase 1 — Cartographie de l’exécutable**
- Modules, signatures, structures (PlayerController, Camera, Movement…)

**Phase 2 — Reverse Caméra**
- Logger position/rotation/FOV/spring arm/collisions
- Cas : sol, vertical, plafond, espaces serrés
- Livrable : spécification précise de l’algorithme

**Phase 3 — Reverse Mouvement multi-surfaces**
- Normale de surface, gravity direction, raycasts, stickiness
- Livrable : algorithme de surface attachment

**Phase 4 — Échelle & Perception**
- Vitesses relatives, FOV, clipping, détection

**Phase 5 — Agents (plus tard)**

**Phase 6 — Reconstruction**
- Specs indépendantes du moteur → implémentation Rust (Bevy ou custom)

---

## 5. PIPELINE ASSETS (IA)

### Deux outils principaux

**image-blaster** (https://github.com/neilsonnn/image-blaster)
- Input : 1 image
- Output en ~5 min : Gaussian splat (environnement) + meshes objets dynamiques + audio
- Idéal pour générer rapidement des pièces de maison photoréalistes

**Blender MCP + AI (GPT-6.1 Sol / Astra ou Claude)**
- Input : multi-vues + prompts
- L’IA contrôle Blender directement
- Idéal pour le cafard et les objets interactifs prioritaires (contrôle total)

### Recommandation Claude vs Astra
- **Claude** : excellent pour image-blaster, planification, prompts structurés, long contexte.
- **Astra / GPT-6.1 Sol** : très fort actuellement sur Blender MCP pour la construction de modèles détaillés.
- **Recommandation pragmatique** :  
  Utilise **Claude** comme cerveau principal (planning + image-blaster).  
  Teste **Astra** en parallèle sur Blender MCP. Garde celui qui donne les meilleurs résultats sur tes assets.

### Ordre d’utilisation des outils
1. image-blaster → environnement de base (cuisine)
2. Blender MCP → cafard + objets critiques
3. Itération et nettoyage dans Blender
4. Import dans le prototype Rust

---

## 6. ORDRE DES PREMIÈRES ACTIONS (en jours)

### Jour 1
- Installer les outils de reverse (x64dbg ou Cheat Engine + RenderDoc)
- Lancer *Les Fourmis* et commencer la cartographie de base (Phase 0 + début Phase 1)
- Installer image-blaster + Claude
- Faire un premier test image-blaster avec une photo de cuisine réelle

### Jour 2
- Continuer reverse caméra (Phase 2) : logger les valeurs principales
- Nettoyer / organiser les assets sortis d’image-blaster dans Blender
- Décider Claude vs Astra sur un premier test Blender MCP simple

### Jour 3
- Finaliser reverse caméra + commencer reverse mouvement multi-surfaces
- Créer le premier modèle de cafard via Blender MCP (même s’il n’est pas parfait)
- Mettre en place un projet Rust minimal (Bevy recommandé) avec un placeholder

### Jour 4
- Implémenter une première version de la caméra dans Rust basée sur les specs extraites
- Tester le feeling avec le placeholder dans l’environnement image-blaster
- Noter les écarts avec *Les Fourmis*

### Jour 5+
- Itérer sur mouvement multi-surfaces
- Améliorer le cafard et les objets prioritaires
- Continuer à enrichir la cuisine (cachettes, évier, frigo, poubelle…)

---

## 7. PROMPTS UTILES (premiers)

### Pour image-blaster
```
Blast this kitchen photo into a fully explorable 3D environment. 
Prioritize realistic scale for a cockroach (1 unit ≈ 1 cm). 
Generate dynamic meshes for fridge, sink, trash can, cabinets and possible hiding spots. 
Keep lighting natural and slightly dark. Output ready for Blender import.
```

### Pour Blender MCP (cafard)
```
Use Blender MCP to build a detailed, photorealistic cockroach matching these multi-view references.
Work in stages: 
1. Accurate blockout with correct proportions
2. Body segments, legs, antennae
3. Fine surface details and materials (chitin, slight gloss)
Keep the model clean, game-ready, and isolated with neutral studio lighting.
Enable Material Preview and frame the entire model so I can inspect it from all angles.
Save as a separate .blend file.
```

### Pour reverse (notes à prendre)
- Camera offset X/Y/Z
- Spring arm length
- Collision radius
- FOV
- Interpolation speed
- Behavior on vertical surfaces and upside-down

---

## 8. HARNESS / STRUCTURE TECHNIQUE CIBLE (Rust)

- Moteur recommandé pour le prototype : **Bevy**
- Systèmes prioritaires à implémenter dans l’ordre :
  1. Player controller (placeholder)
  2. Camera system (specs extraites)
  3. Surface walking / multi-surface movement
  4. Basic environment loading (GLB / splat si possible)
  5. Simple suspicion variable (0-100)
  6. Basic hide / detect logic

---

## 9. RÈGLES D’OR DU PROJET

1. Feeling avant beaux assets.
2. Ne jamais construire tout le jeu avant de savoir si le core est amusant.
3. Reverse-engineering = reconstruction d’algorithmes et de paramètres, pas copie de code.
4. Une maison ultra-détaillée d’abord, le reste plus tard.
5. Itération : Construire → Tester → Observer → Corriger → Améliorer.

---

## 10. PROCHAINE ACTION IMMÉDIATE

**Aujourd’hui (Jour 1) :**
1. Installer les outils de reverse.
2. Installer image-blaster + Claude.
3. Faire un premier blast d’une photo de cuisine.
4. Lancer *Les Fourmis* et commencer à cartographier.

Quand tu as fait ça, reviens ici et on passe au Jour 2 avec les résultats concrets.
