#!/usr/bin/env python3
"""The elephant's and the mammoth's voices, made in code (no recording needed): the trumpet is a
harsh brass blare through the trunk, its pitch jumping up at the start, wavering and breaking into
a lower register as it goes, with the breath roaring through it; under it, the rumble from the
chest. The mammoth is the same throat, bigger: lower, longer, more rumble.

  python3 tools/elephant_voice.py [--out art/audio/voices] [--demo <dir>]

Uses the helpers of build_voices.py (numpy, scipy, ffmpeg).
"""
import argparse, os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from build_voices import SR, noise, lp, bp, peak, drive, room, mix, seq, fade_out, finish, write_ogg, norm

def _wobble(t, hz, seed, depth):
    """A slow random drift (the throat never holds a note dead steady)."""
    n = int(t * SR)
    w = lp(noise(t + 0.5, seed)[:n], hz, 1)
    return 1 + depth * w / (np.max(np.abs(w)) + 1e-9)

def blare(t, f0, contour, seed, rough=0.5, breath=0.35):
    """One trumpet blast: `contour` is [(time share, pitch ratio)...] across its length."""
    n = int(t * SR); tt = np.arange(n) / SR
    k = np.interp(tt / t, [c[0] for c in contour], [c[1] for c in contour])
    f = f0 * k * _wobble(t, 7.0, seed, 0.035) * (1 + 0.02 * np.sin(2 * np.pi * 5.5 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    # A bright, pressed-lip buzz: many strong harmonics.
    buzz = sum(np.sin(h * ph) / h ** 0.7 for h in range(1, 22))
    # The register break: an octave down (the fold flapping at half its rate) now and then.
    sub_amt = np.clip(lp(noise(t + 0.5, seed + 7)[:n], 3.0, 1) * 6.0, 0, 1) * rough
    sub = np.sin(0.5 * ph) + 0.5 * np.sin(1.5 * ph)
    x = buzz * (1 - 0.4 * sub_amt) + sub * sub_amt * 1.4
    # Breath roaring through the trunk, strongest in the bright band.
    air = bp(noise(t, seed + 3)[:n], 900, 5200)
    x = x / (np.max(np.abs(x)) + 1e-9) + air / (np.max(np.abs(air)) + 1e-9) * breath
    # The trunk: a long pipe, its resonances at ~600, 1400 and 2900 Hz.
    x = peak(peak(peak(x, 600, 1.4, 8), 1400, 1.8, 7), 2900, 2.2, 5)
    a = np.minimum(1, tt / 0.035) * np.minimum(1, (t - tt) / 0.18) * (0.85 + 0.15 * _wobble(t, 4.0, seed + 11, 1.0))
    return drive(x * a, 3.2)

def rumble(t, f0, seed):
    """The chest: a deep growling throb under the trumpet."""
    n = int(t * SR); tt = np.arange(n) / SR
    f = f0 * _wobble(t, 2.0, seed, 0.08) * (1 - 0.15 * tt / t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = sum(np.sin(h * ph) / h for h in range(1, 9))
    x = lp(x * (1 + 0.6 * np.sin(2 * np.pi * 11 * tt)), 260)
    a = np.minimum(1, tt / 0.12) * np.minimum(1, (t - tt) / 0.4)
    return drive(x * a, 1.6)

def call(i, r=1.0, big=1.0):
    f0 = (430 + 35 * i) * r
    t = (1.25 + 0.15 * i) * (1 + 0.35 * (big - 1))
    tr = blare(t, f0, [(0, 0.72), (0.08, 1.12), (0.3, 1.0), (0.65, 1.04), (0.85, 0.9), (1, 0.7)], seed=10 + i)
    ru = rumble(t + 0.6, 30 * r, 20 + i)
    return room(mix((tr, 0.0, 1.0), (ru, 0.0, 0.55 * big)), 0.6 + 0.2 * (big - 1), 0.2)

def hurt(i, r=1.0, big=1.0):
    f0 = (560 + 40 * i) * r
    t = 0.55 + 0.08 * i
    tr = blare(t, f0, [(0, 0.85), (0.12, 1.25), (0.5, 1.1), (1, 0.75)], seed=30 + i, rough=0.8, breath=0.5)
    return room(mix((tr, 0.0, 1.0), (rumble(t + 0.3, 34 * r, 40 + i), 0.0, 0.4 * big)), 0.45, 0.15)

def death(i, r=1.0, big=1.0):
    f0 = (440 + 30 * i) * r
    t = 1.5 * (1 + 0.3 * (big - 1))
    tr = blare(t, f0, [(0, 0.8), (0.1, 1.08), (0.4, 0.95), (0.75, 0.62), (1, 0.42)], seed=50 + i, rough=0.9, breath=0.45)
    groan = rumble(1.6 * big, 26 * r, 60 + i)
    return room(fade_out(seq(tr, groan, gap=-0.5), 1.0), 0.75, 0.25)

VOICES = {
    "elephant": dict(r=1.0, big=1.0),
    "mammoth": dict(r=0.72, big=1.4),
}
EVENTS = {"call": call, "hurt": hurt, "death": death}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "art", "audio", "voices"))
    ap.add_argument("--demo", default="")
    a = ap.parse_args()
    for key, kw in VOICES.items():
        demo = []
        for ev, fn in EVENTS.items():
            for i in (1, 2, 3):
                x = finish(fn(i, **kw), 0.9)
                write_ogg(x, os.path.join(a.out, f"{key}_{ev}_{i}.ogg"))
                demo.append(x)
        if a.demo:
            os.makedirs(a.demo, exist_ok=True)
            d = np.concatenate([np.concatenate([x, np.zeros(int(0.4 * SR))]) for x in demo])
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libmp3lame", "-q:a", "3", os.path.join(a.demo, f"demo_{key}.mp3")], input=d.astype(np.float32).tobytes(), check=True)
        print(key, "ok")

if __name__ == "__main__":
    main()
