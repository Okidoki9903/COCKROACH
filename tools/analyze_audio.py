#!/usr/bin/env python3
"""Signal checks on audio recorded by Godot's movie writer (task I).

    python3 tools/analyze_audio.py <recording.wav|.avi> <markers.json> [--timeline out.png] [--export out.wav]

markers.json comes from scenes/tests/audio_runner.tscn (--probe or --clip):
labels, and every sound the presenter started (time, kind, distance to
the ears, dB, occluded). For each sound: onset delay after its event,
peak and RMS per channel, left/right difference. Also: whole-file peak,
samples at or above the limiter ceiling, ambience level, ambience energy
in the announce band.

This measures the signal only. It says nothing about timbre, comfort,
perceived localization or readability: those need someone listening.
Python standard library only (PIL, optional, for --timeline).
"""

import json
import math
import struct
import sys
import wave

WINDOWS = {"pas": 0.3, "fouille": 0.8, "annonce": 0.5, "raté": 0.4, "attrapé": 0.8, "réussite": 1.0}


def read_avi(path):
    """PCM track of an AVI written by Godot's movie writer (MJPEG + PCM)."""
    data = open(path, "rb").read()
    fmt = None
    chunks = []

    def walk(pos, end):
        nonlocal fmt
        while pos + 8 <= end:
            cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
            body = pos + 8
            if cid in (b"RIFF", b"LIST"):
                walk(body + 4, body + size)
            elif cid == b"strf" and size in (16, 18, 20) and fmt is None and struct.unpack("<H", data[body:body + 2])[0] in (1, 0xFFFE):
                fmt = struct.unpack("<HHIIHH", data[body:body + 16])
            elif cid[2:] == b"wb":
                chunks.append(data[body:body + size])
            pos = body + size + (size & 1)

    walk(0, len(data))
    _, ch, rate, _, _, bits = fmt
    return ch, bits // 8, rate, b"".join(chunks)


def read(path):
    if path.lower().endswith(".avi"):
        ch, width, rate, raw = read_avi(path)
    else:
        with wave.open(path) as w:
            ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    fmt = {2: "<h", 4: "<i"}[width]
    full = float(2 ** (8 * width - 1))
    vals = [v[0] / full for v in struct.iter_unpack(fmt, raw)]
    return rate, [vals[c::ch] for c in range(ch)]


def db(x):
    return 20.0 * math.log10(max(x, 1e-9))


def rms(x):
    return math.sqrt(sum(s * s for s in x) / max(len(x), 1))


def biquad(x, rate, kind, freq, q=0.707):
    w = 2.0 * math.pi * freq / rate
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
    else:
        b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b[0] / a0, b[1] / a0, b[2] / a0, a1 / a0, a2 / a0
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for s in x:
        o = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, o
        y.append(o)
    return y


def band(x, rate):
    """Announce band, 400-2000 Hz."""
    return biquad(biquad(x, rate, "hp", 400.0), rate, "lp", 2000.0)


def main():
    args = sys.argv[1:]
    timeline = export = None
    if "--timeline" in args:
        timeline = args[args.index("--timeline") + 1]
    if "--export" in args:
        export = args[args.index("--export") + 1]
    rate, (left, right) = read(args[0])
    markers = json.load(open(args[1], encoding="utf-8"))
    n = len(left)
    print("fichier : %d Hz, 2 canaux, %.2f s" % (rate, n / rate))
    peak = max(max(abs(s) for s in left), max(abs(s) for s in right))
    ceiling = 10 ** (-1.0 / 20.0)
    over = sum(1 for s in left + right if abs(s) >= ceiling)
    full = sum(1 for s in left + right if abs(s) >= 0.9999)
    print("crête globale %.1f dBFS ; échantillons ≥ −1 dBFS : %d ; ≥ 0 dBFS : %d" % (db(peak), over, full))

    amb = [m for m in markers if m.get("label", "").startswith("ambiance seule")]
    amb_band = None
    if amb:
        a0 = int(amb[0]["t"] * rate)
        seg_l, seg_r = left[a0:a0 + rate], right[a0:a0 + rate]
        amb_band = rms(band([(a + b) / 2 for a, b in zip(seg_l, seg_r)], rate)[rate // 10:])
        print("ambiance seule : RMS G %.1f / D %.1f dBFS, crête %.1f dBFS ; (G+D)/2 bande 400–2000 Hz %.1f dBFS" % (
            db(rms(seg_l)), db(rms(seg_r)), db(max(abs(s) for s in seg_l + seg_r)), db(amb_band)))

    print()
    print("%-7s %-9s %6s %6s %5s | %7s %7s | %7s %7s | %6s | %s" % ("t (s)", "son", "d (m)", "dB", "occ.", "crête G", "crête D", "RMS G", "RMS D", "G−D", "attaque après l'événement"))
    label = ""
    rows = []
    for m in markers:
        if "label" in m:
            label = m["label"]
            continue
        k = m["kind"]
        i0 = int(m["t"] * rate)
        i1 = min(i0 + int(WINDOWS.get(k, 0.5) * rate), n)
        sl, sr = left[i0:i1], right[i0:i1]
        pl, pr = max(abs(s) for s in sl), max(abs(s) for s in sr)
        # Onset: first sample within 20 dB of the sound's own peak and
        # twice above what played in the 50 ms before.
        pre = max((abs(s) for s in left[max(i0 - rate // 20, 0):i0] + right[max(i0 - rate // 20, 0):i0]), default=0.0)
        thr = max(pre * 2.0, max(pl, pr) * 0.1, 1e-4)
        onset = next((i for i in range(i1 - i0) if max(abs(sl[i]), abs(sr[i])) > thr), None)
        rl, rr = rms(sl), rms(sr)
        rows.append((m, label, db(rl), db(rr)))
        print("%7.2f %-9s %6.2f %+6.1f %5s | %7.1f %7.1f | %7.1f %7.1f | %+6.1f | %s   [%s]" % (
            m["t"], k, m["d"], m["db"], "oui" if m["occluded"] else "non", db(pl), db(pr), db(rl), db(rr), db(rl) - db(rr),
            "%.0f ms" % (onset * 1000.0 / rate) if onset is not None else "—", label))
        if k == "annonce" and amb_band:
            b = db(rms(band([(a + c) / 2 for a, c in zip(sl, sr)], rate)))
            print("        annonce (G+D)/2, bande 400–2000 Hz : %.1f dBFS, soit %+.1f dB au-dessus de l'ambiance" % (b, b - db(amb_band)))

    if export:
        # 16-bit stereo copy, decimated by 2 (low-passed first) when 48 kHz.
        step = 2 if rate >= 44100 else 1
        l2, r2 = left, right
        if step == 2:
            l2 = biquad(biquad(left, rate, "lp", rate / 4.4), rate, "lp", rate / 4.4)[::2]
            r2 = biquad(biquad(right, rate, "lp", rate / 4.4), rate, "lp", rate / 4.4)[::2]
        with wave.open(export, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(rate // step)
            w.writeframes(b"".join(struct.pack("<hh", int(max(-1, min(1, a)) * 32767), int(max(-1, min(1, b)) * 32767)) for a, b in zip(l2, r2)))
        print("\nexporté : %s (%d Hz, 16 bits, stéréo)" % (export, rate // step))

    if timeline:
        draw(timeline, rate, left, right, markers)


def draw(path, rate, left, right, markers):
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    n = len(left)
    width, lane = 1600, 110
    img = Image.new("RGB", (width, lane * 2 + 170), (250, 250, 248))
    d = ImageDraw.Draw(img)
    d.font = font
    per = max(n // width, 1)
    for c, ch in enumerate((left, right)):
        mid = 30 + lane * c + lane // 2
        d.text((4, 30 + lane * c + 2), "G" if c == 0 else "D", fill=(60, 60, 60))
        for x in range(width):
            seg = ch[x * per:(x + 1) * per]
            if not seg:
                break
            p = max(abs(s) for s in seg)
            h = int(max(db(p) + 60.0, 0.0) / 60.0 * (lane // 2 - 4))
            d.line([(x, mid - h), (x, mid + h)], fill=(40, 90, 160))
        d.line([(0, mid), (width, mid)], fill=(200, 200, 200))
    colors = {"pas": (90, 90, 90), "fouille": (30, 140, 60), "annonce": (220, 120, 0), "raté": (160, 0, 160), "attrapé": (200, 0, 0), "réussite": (0, 120, 200)}
    y_text = 30 + lane * 2 + 8
    row = 0
    for m in markers:
        x = int(m["t"] * rate / per)
        if "label" in m:
            d.line([(x, 20), (x, 30 + lane * 2)], fill=(170, 170, 170))
            d.text((x + 2, y_text + 15 * (row % 10)), m["label"], fill=(80, 80, 80))
            row += 1
        else:
            col = colors.get(m["kind"], (0, 0, 0))
            d.line([(x, 24), (x, 30 + lane * 2)], fill=col, width=2)
            d.text((x + 2, 8 + 10 * ((1 if m["kind"] in ("annonce", "fouille") else 0))), m["kind"], fill=col)
    for s in range(0, int(n / rate) + 1, 5):
        x = int(s * rate / per)
        d.text((x + 2, 30 + lane * 2 - 12), "%d s" % s, fill=(120, 120, 120))
    img.save(path)


if __name__ == "__main__":
    main()
