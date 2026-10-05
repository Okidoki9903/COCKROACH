# COCKROACH — prototype (Rust / Bevy 0.19 + Avian 0.7)

Premier prototype jouable de la Bible (§8, étapes 1 à 3) : caméra à hauteur d'insecte et marche multi-surfaces,
implémentées d'après `docs/specs/camera.md` et `docs/specs/surface-movement.md`.

## Lancer

```
cd proto
cargo run --release
```

La première compilation prend plusieurs minutes (Bevy). Les suivantes sont rapides.

## Boucle de jeu (Bible §3)

Sortir du refuge (sous le meuble bas) → explorer → sentir le danger → fuir → se cacher → prendre une miette
→ la rapporter au refuge.

- **Objectif : une colonie de 12 cafards.** Les miettes (5 à la fois : sol, table, plan de travail, frigo,
  livres, boîte de conserve) se rapportent une par une au refuge ; porter ralentit (×0,8).
- **Colonie** (Bible §1, `src/colony.rs`) : les miettes remplissent la réserve ; chaque cafard mange
  (adulte 1 miette / 2 min, nymphe 1 / 4 min). Si la réserve couvre 2 miettes + 1 min de repas, une
  **oothèque** est pondue (au plus une toutes les 40 s) ; elle éclot en 30 s en **4 nymphes** (une de moins par
  niveau de menace : abri dérangé), qui deviennent adultes en 60 s. À réserve vide, une nymphe meurt de faim
  toutes les 20 s. Les membres de la colonie se promènent sous le meuble.
- **L'humain** entre dans la cuisine, patrouille ~45 s, puis sort ~25 s : c'est le moment de sortir. Sa tête
  change de couleur : beige = calme, jaune = remarque, orange = cherche, rouge = détecté.
- **Antennes** : le HUD indique les vibrations de ses pas (aucune → très fortes) et si son regard est sur toi.
- **Danger** : détecté au sol, il vient t'écraser (3 vies ; écrasé = retour au refuge sans la miette).
  Sur un mur, sous la table ou au plafond, il ne peut pas t'écraser.
- **Escalade de menace** (Bible §1), à chaque détection : 1 = il t'a vu ; 2 = pièges collants (3 s coincé) ;
  3 = insecticide (il te repère plus vite) ; 4 = désinsectiseur appelé, partie perdue.
- R / Start : rejouer après la fin. R en cours de partie : retour au refuge (la miette est lâchée).

## Commandes (identiques à Les Fourmis)

| Action | Manette | Clavier / souris |
|---|---|---|
| Marcher (vitesse ∝ inclinaison) | stick gauche | Z Q S D (W A S D en QWERTY) |
| Caméra | stick droit | souris (clic pour capturer, Échap pour libérer) |
| Courir | B (maintenir) | Maj gauche |
| Sauter | Y (maintenir puis relâcher) | Espace |
| Lâcher prise (mur / plafond) | appui bref sur Y | appui bref sur Espace |
| Distance caméra (proche / moyen / loin) | clic stick gauche | Tab ou M |
| Debug sondes | — | F1 |
| Replacer le cafard | — | R |

## Architecture

- `src/tuning.rs` : toutes les valeurs des specs (unités de Les Fourmis), avec `Tuning::scaled(rayon)`
  pour passer à l'échelle du cafard (1 u = 1 cm, rayon 1 cm).
- `src/walker.rs` : marche multi-surfaces (32 sondes, normale moyenne, réalignement de l'up, stick relatif à
  l'écran, course, saut chargé, lâcher prise, chute).
- `src/camera_rig.rs` : orbite libre en repère monde, pivot + laisse (v = A·d^P), bras, collision.
- `src/query.rs` : trait `SurfaceQuery` (rayon / sphère). En jeu il passe par Avian, dans les tests par un
  monde de boîtes analytique.
- `src/spec_tests.rs` : **tests d'acceptation** qui vérifient les chiffres mesurés sur Les Fourmis (vitesses,
  bascule sol → mur en ~0,2 s, plafond, arête convexe, saut, gravité, laisse caméra, collision…).
- `src/perception.rs` : perception humaine et suspicion 0-100 (`docs/specs/perception.md` §B), 7 tests.
- `src/human.rs` : humain (présence, patrouille, regard, réactions, écrasement).
- `src/colony.rs` : réserve, ponte, éclosion, croissance, famine (6 tests).
- `src/game_loop.rs` : refuge, miettes, colonie visible, vies, menace, pièges, victoire / défaite, HUD de jeu.
- `src/main.rs` : scène cuisine (sol, murs, plafond, table à pieds, meuble en surplomb, frigo, planche fine,
  boîte de conserve, livres, rampe), cafard provisoire, HUD.

```
cargo test --lib
```
