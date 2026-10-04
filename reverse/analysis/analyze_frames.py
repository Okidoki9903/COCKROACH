#!/usr/bin/env python3
"""Analyse un CSV produit par CockroachProbe (F6) et en tire les chiffres de la spec caméra/mouvement.

Usage :
  python analyze_frames.py frames.csv              résumé par segment (marqueur F8 + état de mouvement)
  python analyze_frames.py frames.csv --timeline   une ligne toutes les ~0.15 s (lecture rapide)
  python analyze_frames.py frames.csv --every N    idem, une ligne toutes les N images
  python analyze_frames.py frames.csv --extras     + gravité (chutes), vitesses de rotation caméra
                                                    (image par image), bascule de l'up, direction
                                                    du mouvement vue à l'écran sur les parois

Grandeurs (unités UE : 1 u = 1 cm, angles en degrés) :
  - vitesse réelle du pawn (FrameVelocity si dispo, sinon dérivée de la position)
  - accélération / freinage : temps pour passer de 10 % à 90 % de la vitesse de croisière
  - caméra : distance au pawn, hauteur, pitch, élévation, offset en repère local du pawn
  - laisse : excès de distance en mouvement, constante de temps τ du retour à l'arrêt (fit exponentiel)
  - rotation caméra (yaw/pitch, °/s) et bascule du "haut" du pawn (°/s) lors des changements de surface
  - surface : angle entre l'up du pawn et le haut du monde (0 = sol, ~90 = mur, ~180 = plafond)

Aucune dépendance hors bibliothèque standard.
"""
import csv
import math
import sys
from statistics import mean, median, pstdev

MODES = {0: "Idle", 1: "Walk", 2: "Run", 3: "Jump", 4: "Drop", 5: "Fall", 6: "ChargeJump",
         7: "FollowRail", 8: "Blocked", 9: "Drown", 10: "None"}


# ---------------------------------------------------------------- utilitaires vecteurs
def f(row, k):
    try:
        v = float(row[k])
        return v if math.isfinite(v) else None
    except (KeyError, ValueError, TypeError):
        return None


def v3(row, p):
    xs = [f(row, f"{p}_{a}") for a in "xyz"]
    return None if None in xs else xs


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def add(a, b):
    return [a[i] + b[i] for i in range(3)]


def scale(a, s):
    return [x * s for x in a]


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = norm(a)
    return scale(a, 1.0 / n) if n > 1e-9 else a


def angle_deg(a, b):
    na, nb = norm(a), norm(b)
    if na < 1e-9 or nb < 1e-9:
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(a, b) / (na * nb)))))


def yaw_deg(v):
    return math.degrees(math.atan2(v[1], v[0]))


def pitch_deg(v):
    return math.degrees(math.asin(max(-1.0, min(1.0, unit(v)[2]))))


def wrap180(a):
    return (a + 180.0) % 360.0 - 180.0


def summarize(name, vals, unit_=""):
    vals = [v for v in vals if v is not None]
    if not vals:
        return f"  {name:<34} n/a"
    return (f"  {name:<34} med={median(vals):9.3f}{unit_:<4} moy={mean(vals):9.3f}  "
            f"min={min(vals):9.3f}  max={max(vals):9.3f}  σ={pstdev(vals):7.3f}")


# ---------------------------------------------------------------- chargement
def load(path):
    with open(path, newline="") as fh:
        raw = list(csv.DictReader(fh))
    rows, last_t = [], None
    for r in raw:
        pawn, cam = v3(r, "pawn"), v3(r, "cam")
        fwd, right, up = v3(r, "pawn_fwd"), v3(r, "pawn_right"), v3(r, "pawn_up")
        if None in (pawn, cam, fwd, right, up):
            continue
        t = f(r, "game_t")
        if t is None or t < 0:
            t = f(r, "t")
        if last_t is not None and t <= last_t:  # image dupliquée (même tick de jeu)
            continue
        last_t = t
        d = sub(cam, pawn)
        mode = f(r, "move_mode")
        rows.append({
            "t": t, "marker": int(float(r["marker"])),
            "mode": int(mode) if mode is not None else -1,
            "pawn": pawn, "cam": cam, "fwd": fwd, "right": right, "up": up,
            "fvel": v3(r, "fvel"), "vel": v3(r, "vel"),
            "cam_fwd": v3(r, "cam_fwd"), "cam_up": v3(r, "cam_up"),
            "d": d, "dist": norm(d),
            "local": [dot(d, fwd), dot(d, right), dot(d, up)],
            "fov": f(r, "fov"), "focal": f(r, "focal"),
            "up_angle": angle_deg(up, [0, 0, 1]),
        })
    # Vitesse : FrameVelocity si non nulle, sinon dérivée centrée de la position.
    for i, r in enumerate(rows):
        a, b = rows[max(0, i - 1)], rows[min(len(rows) - 1, i + 1)]
        dt = b["t"] - a["t"]
        r["vel_fd"] = scale(sub(b["pawn"], a["pawn"]), 1.0 / dt) if dt > 0 else [0, 0, 0]
        r["speed"] = norm(r["vel_fd"])
        r["fspeed"] = norm(r["fvel"]) if r["fvel"] else None
    return rows


# ---------------------------------------------------------------- analyses
def segments_by(rows, key):
    segs, cur = [], []
    for r in rows:
        if cur and key(r) != key(cur[-1]):
            segs.append(cur)
            cur = []
        cur.append(r)
    if cur:
        segs.append(cur)
    return segs


def rise_time(rows, target, lo=0.1, hi=0.9):
    """Temps entre lo*target et hi*target de vitesse (accélération)."""
    t_lo = t_hi = None
    for r in rows:
        if t_lo is None and r["speed"] >= lo * target:
            t_lo = r["t"]
        if t_hi is None and r["speed"] >= hi * target:
            t_hi = r["t"]
            break
    return (t_hi - t_lo) if (t_lo is not None and t_hi is not None) else None


def fit_exp_decay(ts, ys):
    """Fit y = A exp(-(t-t0)/τ) par régression de log(y). Retourne (τ, A, r²)."""
    pts = [(t, math.log(y)) for t, y in zip(ts, ys) if y > 1e-3]
    if len(pts) < 4:
        return None
    t0 = pts[0][0]
    xs = [p[0] - t0 for p in pts]
    ls = [p[1] for p in pts]
    mx, my = mean(xs), mean(ls)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx < 1e-12:
        return None
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ls)) / sxx
    if slope >= 0:
        return None
    icpt = my - slope * mx
    ss_tot = sum((y - my) ** 2 for y in ls)
    ss_res = sum((y - (icpt + slope * x)) ** 2 for x, y in zip(xs, ls))
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else 0
    return -1.0 / slope, math.exp(icpt), r2


def rest_distance(rows):
    idle = [r["dist"] for r in rows if r["mode"] == 0]
    return median(idle) if idle else median(r["dist"] for r in rows)


def leash_after_stop(rows, rest):
    """Après chaque passage mouvement -> Idle : fit du retour de la distance caméra vers le repos."""
    out = []
    for i in range(1, len(rows)):
        if rows[i]["mode"] == 0 and rows[i - 1]["mode"] in (1, 2):
            seg = []
            for r in rows[i - 1:]:
                if r["mode"] not in (0, rows[i - 1]["mode"]) or r["t"] - rows[i]["t"] > 3.0:
                    break
                if r is not rows[i - 1] and r["mode"] != 0:
                    break
                seg.append(r)
            ts = [r["t"] for r in seg]
            ys = [r["dist"] - rest for r in seg]
            fit = fit_exp_decay(ts, ys)
            out.append((rows[i]["t"], max(ys) if ys else None, fit))
    return out


def angular_rate(rows, vec_key, fn):
    rates = []
    for a, b in zip(rows, rows[1:]):
        dt = b["t"] - a["t"]
        if dt <= 0 or a[vec_key] is None or b[vec_key] is None:
            continue
        rates.append(fn(a[vec_key], b[vec_key]) / dt)
    return rates


def surface_label(up_angle):
    if up_angle is None:
        return "?"
    if up_angle < 30:
        return "sol"
    if up_angle < 150:
        return "mur"
    return "plafond"


# ---------------------------------------------------------------- sorties
def timeline(rows, every):
    t0 = rows[0]["t"]
    print(f"{'t':>6} {'mk':>2} {'mode':<6} {'v':>6} {'dist':>6} {'loc_av':>7} {'loc_dr':>7} {'loc_ht':>7} "
          f"{'cpitch':>6} {'cyaw':>7} {'pyaw':>7} {'surf':>6} {'cam_roll_vs_up':>8}")
    for i, r in enumerate(rows):
        if i % every:
            continue
        cf = r["cam_fwd"]
        roll = angle_deg(r["cam_up"], r["up"]) if r["cam_up"] else None
        print(f"{r['t'] - t0:6.2f} {r['marker']:2d} {MODES.get(r['mode'], '?'):<6} {r['speed']:6.1f} {r['dist']:6.1f} "
              f"{r['local'][0]:7.1f} {r['local'][1]:7.1f} {r['local'][2]:7.1f} "
              f"{pitch_deg(cf) if cf else float('nan'):6.1f} {yaw_deg(cf) if cf else float('nan'):7.1f} "
              f"{yaw_deg(r['fwd']):7.1f} {r['up_angle']:6.1f} "
              f"{roll if roll is not None else float('nan'):8.1f}")


def report(path, rows):
    dur = rows[-1]["t"] - rows[0]["t"]
    print(f"# Analyse {path}")
    print(f"  {len(rows)} images uniques sur {dur:.2f} s de jeu ({len(rows) / dur:.1f} Hz)\n")

    rest = rest_distance(rows)
    focal = [r["focal"] for r in rows if r["focal"]]
    fov = [r["fov"] for r in rows if r["fov"] and r["fov"] > 0]
    print("## Caméra au repos (Idle)")
    idle = [r for r in rows if r["mode"] == 0] or rows
    print(summarize("distance cam-pawn", [r["dist"] for r in idle], "u"))
    print(summarize("hauteur cam (le long de up pawn)", [r["local"][2] for r in idle], "u"))
    print(summarize("élévation cam vue du pawn", [math.degrees(math.asin(max(-1, min(1, r["local"][2] / r["dist"]))))
                                                 for r in idle if r["dist"] > 0], "°"))
    print(summarize("pitch caméra", [pitch_deg(r["cam_fwd"]) for r in idle if r["cam_fwd"]], "°"))
    print(summarize("FOV (camera manager)", fov, "°"))
    print(summarize("focale CineCamera", focal, "mm"))
    print()

    print("## Segments (marqueur F8 × état de mouvement)")
    for seg in segments_by(rows, lambda r: (r["marker"], r["mode"])):
        if len(seg) < 3:
            continue
        d = seg[-1]["t"] - seg[0]["t"]
        ua = median(r["up_angle"] for r in seg)
        print(f"### marker={seg[0]['marker']} mode={MODES.get(seg[0]['mode'], '?')} "
              f"t=[{seg[0]['t'] - rows[0]['t']:.2f}, {seg[-1]['t'] - rows[0]['t']:.2f}] ({d:.2f}s, {len(seg)} img) "
              f"surface≈{surface_label(ua)} ({ua:.1f}°)")
        steady = seg[len(seg) // 3:] if len(seg) > 6 else seg
        print(summarize("vitesse (dérivée position)", [r["speed"] for r in seg], "u/s"))
        print(summarize("vitesse croisière (2/3 fin)", [r["speed"] for r in steady], "u/s"))
        print(summarize("distance cam-pawn", [r["dist"] for r in seg], "u"))
        print(summarize("excès laisse (dist - repos)", [r["dist"] - rest for r in seg], "u"))
        print(summarize("offset local avant", [r["local"][0] for r in seg], "u"))
        print(summarize("offset local droite", [r["local"][1] for r in seg], "u"))
        print(summarize("offset local haut", [r["local"][2] for r in seg], "u"))
        yr = angular_rate(seg, "cam_fwd", lambda a, b: wrap180(yaw_deg(b) - yaw_deg(a)))
        if yr:
            print(summarize("vitesse yaw caméra", [abs(x) for x in yr], "°/s"))
        ur = angular_rate(seg, "up", angle_deg)
        if ur and max(ur) > 5:
            print(summarize("vitesse bascule up pawn", ur, "°/s"))
        if seg[0]["mode"] in (1, 2):
            target = median(r["speed"] for r in steady)
            rt = rise_time(seg, target)
            print(f"  {'accélération 10→90 %':<34} " + (f"{rt:.3f} s (cible {target:.1f} u/s)" if rt else "n/a"))
        print()

    print("## Laisse caméra après arrêt (fit dist-repos = A·exp(-t/τ))")
    print(f"  distance de repos = {rest:.2f} u")
    for t, peak, fit in leash_after_stop(rows, rest):
        if fit:
            tau, a, r2 = fit
            print(f"  arrêt à t={t - rows[0]['t']:.2f}s : excès max {peak:.2f} u, τ = {tau:.3f} s "
                  f"(vitesse de rappel ≈ {1 / tau:.2f} /s), A = {a:.2f}, r² = {r2:.3f}")
        else:
            print(f"  arrêt à t={t - rows[0]['t']:.2f}s : fit impossible (excès max {peak})")


# ---------------------------------------------------------------- analyses complémentaires
def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def fit_quadratic_accel(ts, zs):
    """Moindres carrés z = a + b t + c t² ; retourne 2c (accélération)."""
    n = len(ts)
    s = [sum(t ** p for t in ts) for p in range(5)]
    y = [sum(z * t ** p for t, z in zip(ts, zs)) for p in range(3)]
    m = [[n, s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]

    def det(a):
        return (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    d = det(m)
    if abs(d) < 1e-12:
        return None
    mc = [[m[i][0], m[i][1], y[i]] for i in range(3)]
    return 2 * det(mc) / d


def extras(rows):
    t0 = rows[0]["t"]
    print("\n## Gravité (segments Jump/Fall, fit z(t) quadratique)")
    for seg in segments_by(rows, lambda r: r["mode"]):
        if seg[0]["mode"] not in (3, 5) or len(seg) < 8:
            continue
        ts = [r["t"] - seg[0]["t"] for r in seg]
        acc = fit_quadratic_accel(ts, [r["pawn"][2] for r in seg])
        vh = [math.hypot(b["pawn"][0] - a["pawn"][0], b["pawn"][1] - a["pawn"][1]) / (b["t"] - a["t"])
              for a, b in zip(seg, seg[1:]) if b["t"] > a["t"]]
        damp = (vh[0] - vh[-1]) / ts[-1] if ts[-1] > 0 else 0
        print(f"  {MODES[seg[0]['mode']]:<4} t={seg[0]['t'] - t0:6.2f} durée={ts[-1]:.2f}s  accel_z={acc:8.1f} u/s²  "
              f"v_horiz {vh[0]:.0f}→{vh[-1]:.0f} (≈{damp:.0f} u/s² de freinage)")

    print("\n## Rotation caméra : vitesse angulaire (norme yaw+pitch) quand elle tourne")
    rates = []
    for a, b in zip(rows, rows[1:]):
        dt = b["t"] - a["t"]
        if dt <= 0 or not a["cam_fwd"] or not b["cam_fwd"]:
            continue
        dy = wrap180(yaw_deg(b["cam_fwd"]) - yaw_deg(a["cam_fwd"])) / dt
        dp = (pitch_deg(b["cam_fwd"]) - pitch_deg(a["cam_fwd"])) / dt
        w = math.hypot(dy, dp)
        if w > 5:
            rates.append(w)
    if rates:
        rates.sort()
        print(f"  {len(rates)} images en rotation ; médiane {median(rates):.1f} °/s ; p90 {rates[int(0.9 * len(rates))]:.1f} °/s ; "
              f"max {rates[-1]:.1f} °/s")
        pitches = [pitch_deg(r["cam_fwd"]) for r in rows if r["cam_fwd"]]
        print(f"  pitch caméra min {min(pitches):.1f}° / max {max(pitches):.1f}°")
    else:
        print("  (pas de rotation)")

    print("\n## Bascule de l'up du pawn (images où il tourne de plus de 30 °/s)")
    ur = [r for r in angular_rate(rows, "up", angle_deg) if r > 30]
    if ur:
        ur.sort()
        print(f"  {len(ur)} images ; médiane {median(ur):.0f} °/s ; p90 {ur[int(0.9 * len(ur))]:.0f} °/s ; max {ur[-1]:.0f} °/s")
        per_u = []
        for a, b in zip(rows, rows[1:]):
            dist = norm(sub(b["pawn"], a["pawn"]))
            ang = angle_deg(a["up"], b["up"])
            if dist > 0.5 and ang and ang > 1:
                per_u.append(ang / dist)
        if per_u:
            print(f"  angle par unité parcourue (médiane) : {median(per_u):.2f} °/u → rayon d'arc ≈ "
                  f"{180 / math.pi / median(per_u):.1f} u")

    print("\n## Direction du mouvement à l'écran sur les parois (fenêtres de 0,5 s, surface > 55°)")
    i = 0
    while i < len(rows):
        j = i
        while j < len(rows) and rows[j]["t"] - rows[i]["t"] < 0.5:
            j += 1
        s, i = rows[i:j], j
        if len(s) < 3:
            continue
        r = s[len(s) // 2]
        if r["up_angle"] < 55 or r["mode"] != 1 or not r["cam_fwd"]:
            continue
        d = sub(s[-1]["pawn"], s[0]["pawn"])
        v = norm(d) / (s[-1]["t"] - s[0]["t"])
        if v < 20:
            continue
        u = unit(d)
        cf, cu = r["cam_fwd"], r["cam_up"]
        cr = unit(cross(cu, cf))
        print(f"  t={r['t'] - t0:6.2f} surf={r['up_angle']:5.1f}° v={v:6.1f}  écran: droite={dot(u, cr):+.2f} "
              f"haut={dot(u, cu):+.2f}  avant_pawn·dir={dot(r['fwd'], u):+.2f}  cam_fwd·normale={dot(cf, r['up']):+.2f}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # console Windows (cp1252) : σ, °, →
    path = sys.argv[1]
    rows = load(path)
    if len(rows) < 3:
        print("Pas assez de données exploitables.")
        sys.exit(1)
    if "--timeline" in sys.argv or "--every" in sys.argv:
        every = 6
        if "--every" in sys.argv:
            every = int(sys.argv[sys.argv.index("--every") + 1])
        else:
            hz = len(rows) / max(1e-6, rows[-1]["t"] - rows[0]["t"])
            every = max(1, round(hz * 0.15))
        timeline(rows, every)
    else:
        report(path, rows)
        if "--extras" in sys.argv:
            extras(rows)


if __name__ == "__main__":
    main()
