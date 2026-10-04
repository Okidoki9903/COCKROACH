#!/usr/bin/env python3
"""Ajuste le modèle de laisse caméra sur les CSV mesurés (voir docs/specs/camera.md §3).

Modèle : point de suivi F rappelé vers le pivot T = pawn + 20·up à la vitesse A·|T-F|^P (u/s),
|T-F| borné par la laisse L (marche/idle, course) ; caméra = F - cam_fwd·300.
Usage : python fit_leash.py   (lit reverse/data/c1..c6)
"""
import itertools
import sys
from statistics import median

import analyze_frames as A

FILES = ["c1_walk_straight", "c2_run_straight", "c3_run", "c5_ground_to_wall", "c6_wall_stick_dirs"]


def simulate(rows, a_=2.3, p=4 / 3, l_walk=30.0, l_run=100.0, arm=300.0, offs=20.0):
    f = None
    errs = []
    for a, b in zip(rows, rows[1:]):
        t = A.add(b["pawn"], A.scale(b["up"], offs))
        dt = b["t"] - a["t"]
        if f is None:
            f = A.add(a["cam"], A.scale(a["cam_fwd"], arm))
            continue
        e = A.sub(t, f)
        d = A.norm(e)
        if d > 1e-6:
            f = A.add(f, A.scale(e, min(d, a_ * d ** p * dt) / d))
        lim = l_run if b["mode"] == 2 else l_walk
        e = A.sub(t, f)
        d = A.norm(e)
        if d > lim:
            f = A.sub(t, A.scale(e, lim / d))
        pred = A.sub(f, A.scale(b["cam_fwd"], arm))
        # images où la collision raccourcit le bras : hors modèle de laisse
        if A.dot(A.sub(t, b["cam"]), b["cam_fwd"]) < arm - 3 and A.norm(A.sub(b["cam"], t)) < arm - 3:
            continue
        errs.append(A.norm(A.sub(pred, b["cam"])))
    errs.sort()
    return median(errs), errs[int(0.9 * len(errs))]


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    data = {fn: A.load(f"../data/{fn}.csv") for fn in FILES}
    grid = itertools.product([2.0, 2.3, 2.6, 3.0, 3.5, 4.0], [1.0, 1.1, 1.2, 1.33], [25.0, 30.0, 35.0], [70.0, 85.0, 100.0])
    res = []
    for a_, p, lw, lr in grid:
        score = sum(simulate(rows, a_, p, lw, lr)[1] for rows in data.values())
        res.append((score, a_, p, lw, lr))
    res.sort()
    print("Top 5 (somme des p90 d'erreur de position caméra, u) :")
    for score, a_, p, lw, lr in res[:5]:
        print(f"  A={a_:.2f} P={p:.2f} L_marche={lw:.0f} L_course={lr:.0f}  score={score:.2f}")
    _, a_, p, lw, lr = res[0]
    print("\nDétail du meilleur :")
    for fn, rows in data.items():
        m, p90 = simulate(rows, a_, p, lw, lr)
        mn, pn = simulate(rows, 1e6, 1.0, lw, lr)  # « sans retard » (suivi instantané)
        print(f"  {fn:<20} erreur méd={m:5.2f} p90={p90:5.2f} u   | sans retard méd={mn:5.2f} p90={pn:6.2f}")


if __name__ == "__main__":
    main()
