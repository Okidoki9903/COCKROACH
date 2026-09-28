#!/usr/bin/env python3
"""Provisional sounds for COCKROACH (task I), synthesized locally.

Python standard library only, fixed seeds: running it again gives the same
files, byte for byte. Output: assets/audio/*.wav, mono, 16 bit, 44.1 kHz.
The sounds are original works of this project, computed from sines and
seeded noise: no sample, no recording, no third-party material, so no
third-party licence applies. The repository has no licence file yet; the
sounds follow whatever licence its author chooses for it.

    python3 tools/gen_audio.py

Every sound is normalized to a fixed peak (dBFS, in PEAKS) to keep the
headroom documented in docs/AUDIO.md.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")

# Peak of each file, dBFS. Leaves room for overlaps (see docs/AUDIO.md).
PEAKS = {
    "step_a": -9.0, "step_b": -9.0, "step_c": -9.0,
    "rustle": -6.0,
    "capture_announce": -8.0,
    "capture_miss": -6.0,
    "capture_caught": -6.0,
    "outing_success": -12.0,
    "kitchen_hum": -18.0,
}


# --- building blocks ------------------------------------------------------------

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def biquad(x, kind, freq, q):
    """RBJ cookbook biquad; kind is 'lp', 'hp' or 'bp' (constant peak)."""
    w = 2.0 * math.pi * freq / RATE
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for s in x:
        o = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, o
        y.append(o)
    return y


def sweep_bp(x, f0, f1, q):
    """Band-pass whose centre moves from f0 to f1 (state-variable filter)."""
    y = []
    low = band = 0.0
    n = len(x)
    for i, s in enumerate(x):
        f = f0 * (f1 / f0) ** (i / max(n - 1, 1))
        k = 2.0 * math.sin(math.pi * f / RATE)
        low += k * band
        high = s - low - band / q
        band += k * high
        y.append(band)
    return y


def env_exp(n, attack, tau):
    a = max(int(attack * RATE), 1)
    return [(i / a) if i < a else math.exp(-(i - a) / (tau * RATE)) for i in range(n)]


def thump(n, f0, f1, tau, phase=0.0):
    """Sine whose pitch glides from f0 to f1, exponential decay."""
    out = []
    ph = phase
    for i in range(n):
        f = f1 + (f0 - f1) * math.exp(-i / (0.04 * RATE))
        ph += 2.0 * math.pi * f / RATE
        out.append(math.sin(ph) * math.exp(-i / (tau * RATE)))
    return out


def mix(*parts):
    n = max(len(p) for p, _, _ in parts)
    out = [0.0] * n
    for p, gain, offset in parts:
        o = int(offset * RATE)
        for i, s in enumerate(p):
            if o + i < n:
                out[o + i] += s * gain
    return out


def pad(x, seconds):
    return x + [0.0] * max(int(seconds * RATE) - len(x), 0)


def mul(a, b):
    return [p * q for p, q in zip(a, b)]


def fade_out(x, seconds):
    n = int(seconds * RATE)
    for i in range(n):
        x[-1 - i] *= i / n
    return x


def normalize(x, peak_db):
    m = max(abs(s) for s in x) or 1.0
    g = 10 ** (peak_db / 20.0) / m
    return [s * g for s in x]


def write(name, x):
    x = normalize(x, PEAKS[name])
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, s)) * 32767))) for s in x))
    print("%-18s %5.2f s  peak %.0f dBFS" % (name, len(x) / RATE, PEAKS[name]))


# --- sounds ----------------------------------------------------------------------

def step(seed):
    """A shoe landing on tiles, heard from the floor: heel, then sole."""
    rng = random.Random(seed)
    n = int(0.26 * RATE)
    body = thump(n, rng.uniform(95, 110), rng.uniform(48, 56), 0.055)
    # Heel click: short, mid-band, what makes the step readable on small
    # speakers (the thump alone is below what laptops reproduce).
    click = mul(biquad(biquad(noise(n, rng), "bp", rng.uniform(700, 900), 0.9), "lp", 3500, 0.7), env_exp(n, 0.001, 0.012))
    sole = mul(biquad(noise(n, rng), "lp", rng.uniform(450, 600), 0.7), env_exp(n, 0.004, 0.035))
    return fade_out(mix((body, 1.0, 0.0), (click, 2.2, 0.0), (sole, 1.6, rng.uniform(0.045, 0.06))), 0.03)


def rustle():
    """Cloth: grains of band-passed noise over 0.7 s (trousers when the
    human turns or bends to look)."""
    rng = random.Random(21)
    n = int(0.75 * RATE)
    src = biquad(biquad(noise(n, rng), "hp", 1800, 0.7), "lp", 6500, 0.7)
    envl = [0.0] * n
    for _ in range(26):
        c = rng.uniform(0.03, 0.62)
        w = rng.uniform(0.012, 0.05)
        g = rng.uniform(0.3, 1.0)
        for i in range(n):
            t = i / RATE
            envl[i] += g * math.exp(-((t - c) / w) ** 2)
    shape = [math.sin(math.pi * min(i / n, 1.0)) ** 0.5 for i in range(n)]
    return fade_out(mul(mul(src, envl), shape), 0.05)


def capture_announce():
    """The hand coming down: a band-passed rush rising in pitch, 0.45 s,
    audible at once, that stops short before the resolution sound."""
    rng = random.Random(33)
    n = int(0.45 * RATE)
    rush = sweep_bp(noise(n, rng), 350, 1900, 2.2)
    # Clear from the first 15 ms (it is the warning), then swelling.
    grow = [min(i / (0.015 * RATE), 1.0) * (0.45 + 0.55 * (i / n) ** 1.6) for i in range(n)]
    low = thump(n, 70, 60, 10.0)
    low_env = [0.25 * (i / n) ** 2 for i in range(n)]
    return fade_out(mix((mul(rush, grow), 1.0, 0.0), (mul(low, low_env), 1.0, 0.0)), 0.02)


def capture_miss():
    """Flat hand slapping the floor, empty: bright, short."""
    rng = random.Random(44)
    n = int(0.35 * RATE)
    slap = mul(biquad(noise(n, rng), "hp", 900, 0.7), env_exp(n, 0.0005, 0.018))
    body = thump(n, 190, 150, 0.04)
    return fade_out(mix((slap, 1.0, 0.0), (body, 0.5, 0.0)), 0.05)


def capture_caught():
    """Cupped hand closing over the cockroach: dull, lower and longer than
    the miss, with a muffled resonance. No crunch."""
    rng = random.Random(55)
    n = int(0.7 * RATE)
    hit = mul(biquad(noise(n, rng), "lp", 700, 0.7), env_exp(n, 0.002, 0.03))
    body = thump(n, 120, 62, 0.12)
    cup = mul(biquad(noise(n, rng), "bp", 260, 6.0), env_exp(n, 0.01, 0.18))
    return fade_out(mix((hit, 1.2, 0.0), (body, 1.0, 0.0), (cup, 3.0, 0.01)), 0.1)


def outing_success():
    """Soft two-note end of attempt (not positional)."""
    n = int(0.9 * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        a = math.sin(2 * math.pi * 587.33 * t) * math.exp(-t / 0.35)
        b = math.sin(2 * math.pi * 880.0 * t) * math.exp(-(t - 0.16) / 0.45) if t >= 0.16 else 0.0
        att = min(t / 0.005, 1.0) * (min((t - 0.16) / 0.005, 1.0) if t >= 0.16 else 1.0)
        out.append(a * min(t / 0.005, 1.0) + b * att)
    return fade_out(out, 0.1)


def kitchen_hum():
    """Fridge hum, 4 s seamless loop: mains harmonics plus a quiet, dense
    bed of partials, all periodic over 4 s (whole numbers of cycles)."""
    rng = random.Random(66)
    seconds = 4.0
    n = int(seconds * RATE)
    partials = [(50.0, 0.35), (100.0, 1.0), (150.0, 0.25), (200.0, 0.18), (300.0, 0.06)]
    for _ in range(70):
        f = round(rng.uniform(60.0, 900.0) * seconds) / seconds
        partials.append((f, 0.02 * rng.uniform(0.3, 1.0) * (120.0 / f) ** 0.5))
    phases = [rng.uniform(0, 2 * math.pi) for _ in partials]
    out = [0.0] * n
    for (f, a), p in zip(partials, phases):
        w = 2 * math.pi * f / RATE
        for i in range(n):
            out[i] += a * math.sin(w * i + p)
    # Slow breathing of the compressor, also periodic over 4 s.
    return [s * (0.85 + 0.15 * math.sin(2 * math.pi * 0.5 * i / RATE)) for i, s in enumerate(out)]


def main():
    os.makedirs(OUT, exist_ok=True)
    write("step_a", step(1))
    write("step_b", step(2))
    write("step_c", step(3))
    write("rustle", rustle())
    write("capture_announce", capture_announce())
    write("capture_miss", capture_miss())
    write("capture_caught", capture_caught())
    write("outing_success", outing_success())
    write("kitchen_hum", kitchen_hum())


if __name__ == "__main__":
    main()
