#!/usr/bin/env python3
"""Analyse un CSV produit par CockroachProbe (F6) et en tire une spec caméra/mouvement.

Usage : python analyze_frames.py frames_XXXX.csv [--by-marker]

Pour chaque segment (marqueur F8) :
  - offset caméra dans le repère local du pawn (avant / droite / haut)
  - distance caméra-pawn, FOV, longueur du spring arm
  - vitesse du pawn
  - angle entre l'up du pawn et le monde (0 = sol, ~90 = mur, ~180 = plafond)
  - estimation du lag caméra (constante de temps du suivi)

Aucune dépendance hors bibliothèque standard.
"""
import csv
import math
import sys
from collections import defaultdict
from statistics import mean, median, pstdev


def f(row, k):
    try:
        v = float(row[k])
        return v if math.isfinite(v) else None
    except (KeyError, ValueError):
        return None


def v3(row, p):
    xs = [f(row, f"{p}_{a}") for a in "xyz"]
    return None if None in xs else xs


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    return math.sqrt(dot(a, a))


def summarize(name, vals, unit=""):
    vals = [v for v in vals if v is not None]
    if not vals:
        return f"  {name:<28} n/a"
    return (f"  {name:<28} med={median(vals):9.3f}{unit}  moy={mean(vals):9.3f}  "
            f"min={min(vals):9.3f}  max={max(vals):9.3f}  σ={pstdev(vals):7.3f}")


def surface_label(up_angle):
    if up_angle is None:
        return "?"
    if up_angle < 30:
        return "sol"
    if up_angle < 150:
        return "mur"
    return "plafond"


def lag_time_constant(rows):
    """Estime τ du suivi caméra : la cible idéale est pawn + offset médian local ;
    on régresse d(cam)/dt ≈ (cible - cam)/τ."""
    num = den = 0.0
    for a, b in zip(rows, rows[1:]):
        dt = b["t"] - a["t"]
        if dt <= 0:
            continue
        err = sub(a["target"], a["cam"])
        dcam = [(b["cam"][i] - a["cam"][i]) / dt for i in range(3)]
        num += dot(err, err)
        den += dot(err, dcam)
    if den <= 1e-9:
        return None
    return num / den


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    with open(path, newline="") as fh:
        raw = list(csv.DictReader(fh))

    segments = defaultdict(list)
    for r in raw:
        pawn, cam = v3(r, "pawn"), v3(r, "cam")
        fwd, right, up = v3(r, "pawn_fwd"), v3(r, "pawn_right"), v3(r, "pawn_up")
        if None in (pawn, cam, fwd, right, up):
            continue
        d = sub(cam, pawn)
        vel = v3(r, "vel")
        segments[int(float(r["marker"]))].append({
            "t": f(r, "t"),
            "pawn": pawn, "cam": cam, "fwd": fwd, "right": right, "up": up,
            "local": [dot(d, fwd), dot(d, right), dot(d, up)],
            "dist": norm(d),
            "speed": norm(vel) if vel else None,
            "fov": f(r, "fov"),
            "arm": f(r, "arm_len"),
            "up_angle": math.degrees(math.acos(max(-1.0, min(1.0, up[2])))),
        })

    print(f"# Analyse {path}  ({sum(len(s) for s in segments.values())} frames)\n")
    for m in sorted(segments):
        rows = segments[m]
        if len(rows) < 2:
            continue
        lf = median(r["local"][0] for r in rows)
        lr = median(r["local"][1] for r in rows)
        lu = median(r["local"][2] for r in rows)
        for r in rows:
            r["target"] = [r["pawn"][i] + lf * r["fwd"][i] + lr * r["right"][i] + lu * r["up"][i]
                           for i in range(3)]
        ua = median(r["up_angle"] for r in rows)
        print(f"## Segment marker={m}  frames={len(rows)}  surface≈{surface_label(ua)} ({ua:.1f}°)")
        print(summarize("offset local avant", [r["local"][0] for r in rows], "u"))
        print(summarize("offset local droite", [r["local"][1] for r in rows], "u"))
        print(summarize("offset local haut", [r["local"][2] for r in rows], "u"))
        print(summarize("distance cam-pawn", [r["dist"] for r in rows], "u"))
        print(summarize("spring arm", [r["arm"] if r["arm"] and r["arm"] >= 0 else None for r in rows], "u"))
        print(summarize("FOV", [r["fov"] if r["fov"] and r["fov"] > 0 else None for r in rows], "°"))
        print(summarize("vitesse pawn", [r["speed"] for r in rows], "u/s"))
        tau = lag_time_constant(rows)
        print(f"  {'lag caméra τ (≈1/LagSpeed)':<28} " + (f"{tau:.4f}s" if tau else "n/a"))
        print()


if __name__ == "__main__":
    main()
