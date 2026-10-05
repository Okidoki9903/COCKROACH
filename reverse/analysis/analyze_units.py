#!/usr/bin/env python3
"""Analyse un units_*.csv (CockroachProbe, F6) : réactions des unités au joueur.

Usage : python analyze_units.py units_XXXX.csv [--all]

Pour chaque unité : changements d'état de comportement avec la distance au joueur à cet instant, la cible
poursuivie (chased_unit / chased_general) et la transition qui a provoqué le changement. Puis, pour les
passages vers Chase / Fight / Flee, statistiques de distance (= portée de réaction effective).
Sans --all, les unités du clan du joueur (clan 0) sont ignorées.
"""
import csv
import math
import sys
from collections import defaultdict
from statistics import median

STATES = ["None", "AttackNest", "Chase", "Die", "Fight", "Follow", "Gather", "Idle", "Jump", "MoveFreely",
          "Patrol", "RangeAttack", "FlyHarass", "Flee", "FlyTransport", "Transported", "Invading", "Duel"]
TRANSITIONS = ["None", "EffectOverride", "FailedToReachLocation", "TargetDead", "NewTarget", "TargetDoneFighting",
               "TargetOutOfReach", "TargetOutOfOpponents", "CanRangeAttackTarget", "Respawning", "FinishedFight",
               "ResourceNearby", "LandedFromJump", "ReachedTarget", "InvalidData", "Initialization",
               "ReceivedMoveOrder", "ReceivedChaseOrder", "ReceivedAttackNestOrder", "ReceivedPatrolOrder",
               "ReceivedFollowOrder", "ReceivedTransportedOrder", "RangeSupportFightingAlly", "Killed",
               "UpgradeUpgraded"]
UNIT_TYPES = {1: "T1WarriorAnt", 4: "T1WorkerAnt", 7: "T1GunnerAnt", 10: "T1WarriorTermite", 13: "T1WorkerTermite",
              16: "T1GunnerTermite", 19: "Ladybug", 20: "Aphid", 21: "T1NestGuard", 22: "T2NestGuard", 24: "Wall",
              25: "Snail", 27: "RoseChafer", 28: "DorBeetle", 29: "Hornet", 30: "MantisBig", 31: "MantisSmall",
              35: "Firebug", 45: "Rhino", 47: "SpiderSmall", 48: "SpiderBig", 50: "Paussus", 51: "PotatoBeetle"}
CATEGORIES = ["Warrior", "Worker", "Special", "Predator", "Support", "NestDefense", "None"]


def name(table, i):
    return table[i] if 0 <= i < len(table) else str(i)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    show_all = "--all" in sys.argv
    by_unit = defaultdict(list)
    markers = {}
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            try:
                row = {k: float(v) for k, v in r.items() if v not in ("", "nan")}
            except ValueError:
                continue
            if "game_t" not in row:
                continue
            uid = int(row["id"])
            by_unit[uid].append(row)
            markers.setdefault(int(row["marker"]), row["game_t"])
    t0 = min(min(r["game_t"] for r in rows) for rows in by_unit.values())
    print(f"# {path}")
    print("# marqueurs F8 : " + ", ".join(f"{m}@{t - t0:.1f}s" for m, t in sorted(markers.items())))

    reactions = defaultdict(list)
    for uid, rows in sorted(by_unit.items()):
        first = rows[0]
        clan = int(first["clan"])
        if clan == 0 and not show_all:
            continue
        utype = int(first["type"])
        print(f"\n## unité {uid} : {UNIT_TYPES.get(utype, utype)} ({name(CATEGORIES, int(first['category']))}), "
              f"clan {clan}, détection {first.get('detection_range', 'nan')}, fight_radius {first.get('fight_radius', 'nan')}")
        dmin = min(rows, key=lambda r: r["dist"])
        print(f"   distance min au joueur : {dmin['dist']:.0f} u à t={dmin['game_t'] - t0:.1f}s ; "
              f"plage {rows[0]['dist']:.0f} → {rows[-1]['dist']:.0f}")
        prev = None
        for r in rows:
            key = (int(r["state"]), int(r.get("chased_unit", -1)), int(r.get("chased_general", -1)))
            if prev is None or key != prev:
                st = name(STATES, key[0])
                tr = name(TRANSITIONS, int(r.get("transition", 0)))
                print(f"   t={r['game_t'] - t0:6.1f}s  {st:<11} dist={r['dist']:6.0f}  chased_unit={key[1]:>3} "
                      f"chased_general={key[2]:>3}  transition={tr}  mk={int(r['marker'])}")
                if prev is not None and key[0] != prev[0] and st in ("Chase", "Fight", "Flee", "RangeAttack"):
                    reactions[st].append(r["dist"])
                prev = key

    print("\n## Distances au joueur lors des passages en réaction")
    for st, ds in reactions.items():
        print(f"   {st:<11} n={len(ds)}  médiane={median(ds):.0f} u  min={min(ds):.0f}  max={max(ds):.0f}")


if __name__ == "__main__":
    main()
