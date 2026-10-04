# COCKROACH — prototype (Rust / Bevy 0.19 + Avian 0.7)

Premier prototype jouable de la Bible (§8, étapes 1 à 3) : caméra à hauteur d'insecte et marche multi-surfaces,
implémentées d'après `docs/specs/camera.md` et `docs/specs/surface-movement.md`.

## Lancer

```
cd proto
cargo run --release
```

La première compilation prend plusieurs minutes (Bevy). Les suivantes sont rapides.

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
- `src/main.rs` : scène cuisine (sol, murs, plafond, table à pieds, meuble en surplomb, frigo, planche fine,
  boîte de conserve, livres, rampe), cafard provisoire, HUD.

```
cargo test --lib
```
