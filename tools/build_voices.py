#!/usr/bin/env python3
"""Builds every creature's voice (art/audio/voices/<key>_<take>.ogg) from real CC0 / public-domain
recordings, each species its own animal: a wolf's howl is an NPS wolf, a bear a Yellowstone grizzly,
a boar a wild pig, a crocodile an alligator; the beasts of myth are layered from the animals they
are made of (a chimera: lion, goat and snake; a basilisk: a serpent and a cock; a cerberus: three
hounds). The men are men. See art/CREDITS.md for every recording.

  python3 tools/build_voices.py --pool <conquest>/client/sounds --cc0 <cc0-public-domain-sounds> [--out art/audio/voices] [--demo <dir>]

The pools are hoffspot/conquest (its processed CC0 creature cuts, 48 kHz mp3) and
lavenderdotpet/cc0-public-domain-sounds (Warfork's player voices, The Motion Monkey's vocal pack).
Needs numpy, scipy and ffmpeg.
"""
import argparse, glob, os, subprocess, sys, tempfile
import numpy as np
from scipy import signal

SR = 44100
POOL = None
CC0 = None
_cache = {}

# ---------------------------------------------------------------- loading
def load(path):
    if path in _cache:
        return _cache[path]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    x = trim(x)
    _cache[path] = x
    return x

def pool(name, n=1):
    """The n-th (1-based, cycled) cut of a conquest family: pool("wolf-call", 2)."""
    files = sorted(glob.glob(os.path.join(POOL, f"{name}-[0-9].*.mp3")) + glob.glob(os.path.join(POOL, f"{name}-[0-9][0-9].*.mp3")))
    if not files:
        raise SystemExit(f"no {name} in {POOL}")
    return load(files[(n - 1) % len(files)])

def cc0(rel):
    return load(os.path.join(CC0, rel))

def warfork(name):
    return cc0(f"warfork-cc0/sounds/players/male/{name}.ogg")

def mm(name):
    return cc0(f"MMRetroArcadeSoundsPack1_0_5/Vocal/m4a/{name}.m4a")

# ---------------------------------------------------------------- processing
def trim(x, thr=0.004):
    a = np.abs(x)
    idx = np.where(a > thr * max(1e-9, a.max()))[0]
    if len(idx) == 0:
        return x
    s = max(0, idx[0] - int(0.01 * SR)); e = min(len(x), idx[-1] + int(0.08 * SR))
    return x[s:e]

def shift(x, r):
    """Pitch and speed together by ratio r (r < 1: deeper and slower), like a bigger throat."""
    if abs(r - 1.0) < 1e-3:
        return x
    n = int(len(x) / r)
    return signal.resample(x, n) if n > 8 else x

def stretch(x, r):
    """Longer by r at the same pitch (phase-vocoder-less: granular overlap-add)."""
    if abs(r - 1.0) < 1e-3:
        return x
    g = int(0.06 * SR); hop_in = g // 2; hop_out = int(hop_in * r)
    win = np.hanning(g)
    out = np.zeros(int(len(x) * r) + g)
    pos_in = 0; pos_out = 0
    while pos_in + g < len(x):
        out[pos_out:pos_out + g] += x[pos_in:pos_in + g] * win
        pos_in += hop_in; pos_out += hop_out
    return out[:pos_out]

def deep(x, r, keep=0.65):
    """A bigger throat: pitched down by r, then pulled back toward its own length (keep: how
    much of the slowing stays, 1.0 all of it), so a man slowed to a giant does not smear."""
    y = shift(x, r)
    want = len(x) * (1 + (1 / r - 1) * keep)
    return stretch(y, want / len(y))

def gain(x, g):
    return x * g

def env(x, a=0.005, r=0.05):
    x = x.copy(); na = int(a * SR); nr = int(r * SR)
    if na > 0 and na < len(x): x[:na] *= np.linspace(0, 1, na)
    if nr > 0 and nr < len(x): x[-nr:] *= np.linspace(1, 0, nr)
    return x

def fade_out(x, t):
    n = min(len(x), int(t * SR)); x = x.copy()
    x[-n:] *= np.linspace(1, 0, n) ** 1.5
    return x

def cut(x, t0, t1=None):
    s = int(t0 * SR); e = len(x) if t1 is None else int(t1 * SR)
    return env(x[s:e])

def lp(x, f, o=2):
    b, a = signal.butter(o, min(f, SR * 0.49) / (SR / 2), "low"); return signal.lfilter(b, a, x)

def hp(x, f, o=2):
    b, a = signal.butter(o, max(f, 20) / (SR / 2), "high"); return signal.lfilter(b, a, x)

def bp(x, f0, f1):
    return hp(lp(x, f1), f0)

def peak(x, f, q=2.0, db=6.0):
    """A bell boost (or cut) at f."""
    A = 10 ** (db / 40); w = 2 * np.pi * f / SR; al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]; a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x)

def drive(x, k=2.0):
    """Throat rasp: soft clipping."""
    return np.tanh(x * k) / np.tanh(k)

def growl(x, hz=28.0, depth=0.5):
    """Sub-harmonic pulsing (vocal-fry) over a sound."""
    t = np.arange(len(x)) / SR
    return x * (1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * hz * t)) ** 0.7)

def tremolo(x, hz, depth=0.6):
    t = np.arange(len(x)) / SR
    return x * (1 - depth * 0.5 * (1 - np.cos(2 * np.pi * hz * t)))

def room(x, size=0.4, mix=0.18, seed=1):
    """A hall: decaying noise convolved in."""
    rng = np.random.default_rng(seed)
    n = int(size * SR); t = np.arange(n) / SR
    ir = lp(rng.normal(0, 1, n) * np.exp(-t * (6.0 / size)), 5000)
    ir /= np.sqrt(np.sum(ir * ir)) + 1e-9
    wet = signal.fftconvolve(x, ir)[:len(x) + n]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry + wet * mix * 3.0

def mix(*parts):
    """Layers [(sound, offset_seconds, gain), ...] (or bare sounds)."""
    items = [p if isinstance(p, tuple) else (p, 0.0, 1.0) for p in parts]
    n = max(int(o * SR) + len(s) for s, o, g in items)
    out = np.zeros(n)
    for s, o, g in items:
        i = int(o * SR); out[i:i + len(s)] += s * g
    return out

def seq(*parts, gap=0.0):
    """One after another, with a gap (negative: overlapping)."""
    out = np.zeros(0)
    for p in parts:
        off = max(0.0, len(out) / SR + gap)
        out = mix((out, 0.0, 1.0), (p, off, 1.0))
    return out

def norm(x, p=0.9):
    m = np.max(np.abs(x)) if len(x) else 0
    return x * (p / m) if m > 1e-9 else x

def finish(x, p=0.9, hp_f=40):
    x = np.nan_to_num(hp(x, hp_f))
    # A gentle compressor: the loud bits tamed, the body brought up.
    e = np.sqrt(np.maximum(lp(x * x, 25), 0) + 1e-9); g = 1 / (0.35 + e * 2.0); x = x * g
    x = drive(norm(x, 0.95), 1.4)
    return np.nan_to_num(norm(env(x, 0.003, 0.03), p))

def noise(t, seed=0):
    return np.random.default_rng(seed).normal(0, 1, int(t * SR))

def thump(f=70.0, t=0.18, seed=0):
    """A chest beat / foot: a decaying low sine with a knock."""
    n = int(t * SR); tt = np.arange(n) / SR
    body = np.sin(2 * np.pi * (f * tt + 30 * np.exp(-tt * 25))) * np.exp(-tt * 14)
    knock = lp(noise(t, seed), 900) * np.exp(-tt * 60) * 0.5
    return (body + knock) * 0.8

def trumpet(t=1.2, f0=520.0, glide=(1.0, 1.35, 0.9), seed=0):
    """A brassy blare: a sawtooth with vibrato and breath, through two horn resonances."""
    n = int(t * SR); tt = np.arange(n) / SR
    k = np.interp(tt, [0, t * 0.35, t], glide)
    f = f0 * k * (1 + 0.025 * np.sin(2 * np.pi * 6.5 * tt + 1.0))
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(h * ph) / h for h in range(1, 14))
    rasp = bp(noise(t, seed), 800, 5000) * 0.35
    x = saw * (1 + 0.4 * rasp)
    x = peak(peak(x, 900, 1.6, 9), 2200, 2.0, 6)
    a = np.minimum(1, tt / 0.08) * np.minimum(1, (t - tt) / 0.25)
    return drive(x * a, 3.0)

# ---------------------------------------------------------------- the voices
V = {}
def voice(key):
    def deco(fn):
        V[key] = fn; return fn
    return deco

# The lion in the pool is inside the drake cuts (a lion's growl with a slowed bison or alligator);
# sped back up it is a lion's roar again, with the bison's bellow under it.
def lion_roar(i):
    return growl(drive(shift(pool("dragon-attack", i), 1.5), 1.6), 26, 0.35)

@voice("lion")
def lion(ev, i):
    if ev == "call":  # the roar, a heavy chest and a hall
        x = seq(lion_roar(i), gain(shift(pool("dragon-call", i), 1.45), 0.7), gap=-0.3)
        return room(peak(lp(x, 4500), 250, 1.2, 5), 0.5, 0.22)
    if ev == "hurt":
        return room(drive(shift(pool("big-cat-hurt", i), 0.72), 1.8), 0.3, 0.1)
    return room(fade_out(seq(lion_roar(i), shift(pool("dragon-death", i), 1.35), gap=-0.2), 1.2), 0.6, 0.25)

@voice("tiger")
def tiger(ev, i):
    if ev == "call":  # the puma's snarl and spit: sharper and hissier than the lion
        return room(peak(seq(shift(pool("big-cat-attack", i), 0.85), shift(pool("big-cat-call", i), 0.8), gap=-0.15), 1800, 1.5, 4), 0.35, 0.14)
    if ev == "hurt":
        return shift(pool("big-cat-hurt", i + 1), 0.85)
    return room(fade_out(shift(pool("big-cat-death", i), 0.85), 1.0), 0.4, 0.15)

@voice("bear")
def bear(ev, i):
    if ev == "call":  # a grizzly's roar
        return room(peak(pool("bear-attack", i), 180, 1.0, 4), 0.45, 0.16)
    if ev == "hurt":
        return pool("bear-hurt", i)
    return room(fade_out(pool("bear-death", i), 0.8), 0.5, 0.2)

@voice("gorilla")
def gorilla(ev, i):
    beats = mix(*[(thump(85, 0.16, k), 0.11 * k, 0.9 - 0.06 * k) for k in range(7)])
    if ev == "call":  # the chest beat, then a bellowing roar: a deep man's throat with a bear under it
        roar = mix(growl(deep(pool("human-rough-attack", i), 0.62), 32, 0.4), (shift(pool("bear-attack", i), 0.9), 0.05, 0.45))
        return room(seq(beats, drive(roar, 2.0), gap=-0.1), 0.5, 0.2)
    if ev == "hurt":
        return room(growl(deep(pool("human-rough-hurt", i), 0.68), 30, 0.3), 0.3, 0.1)
    return room(fade_out(mix(growl(deep(pool("human-rough-death", i), 0.6), 24, 0.4), (shift(pool("bear-death", i), 0.85), 0.3, 0.35)), 1.0), 0.6, 0.25)

@voice("wolf")
def wolf(ev, i):
    if ev == "call":  # the snarl, and on the third take a howl
        if i == 3:
            return room(cut(pool("wolf-call", 1), 0, 2.6), 0.6, 0.2)
        return room(seq(pool("wolf-attack", i), gain(pool("wolf-attack", i + 2), 0.8), gap=-0.1), 0.3, 0.1)
    if ev == "hurt":
        return pool("wolf-hurt", i)
    return room(fade_out(pool("wolf-death", i), 0.7), 0.4, 0.15)

@voice("hyena")
def hyena(ev, i):
    yelp = pool("wolf-hurt", i)
    def giggle(n=7, r0=1.25, r1=1.7, k=0):  # the giggle: quick yelps climbing in pitch, "hee-hee-hee"
        bits = []
        for j in range(n):
            r = r0 + (r1 - r0) * j / max(1, n - 1)
            bits.append((cut(shift(yelp, r), 0, 0.13), 0.085 * j + 0.012 * ((j + k) % 2), 0.75 + 0.25 * j / n))
        return mix(*bits)
    def whoop():  # the whoop: a long rising "whooo-oop"
        a = stretch(cut(shift(yelp, 0.95), 0, 0.2), 4.0)
        b = stretch(cut(shift(yelp, 1.25), 0, 0.16), 2.0)
        return lp(seq(a, b, gap=-0.12), 3500)
    if ev == "call":
        return room(seq(whoop(), giggle(7 + i, 1.2, 1.55 + 0.1 * i, i), gap=0.05), 0.35, 0.12)
    if ev == "hurt":
        return seq(shift(pool("wolf-hurt", i + 1), 1.3), gain(giggle(4, 1.3, 1.5, i), 0.7), gap=-0.05)
    return room(fade_out(seq(shift(pool("wolf-death", i), 1.2), gain(giggle(5, 1.15, 0.95, i), 0.6), gap=-0.15), 0.8), 0.4, 0.15)

@voice("rat")
def rat(ev, i):
    if ev == "call":  # a giant rat: the squeaks a little down, with a hiss of teeth
        return seq(shift(pool("rat-call", i), 0.8), shift(pool("rat-attack", i), 0.75), gap=0.05)
    if ev == "hurt":
        return shift(pool("rat-hurt", i), 0.8)
    return fade_out(shift(pool("rat-death", i), 0.75), 0.6)

@voice("boar")
def boar(ev, i):
    if ev == "call":
        return seq(pool("boar-call", i), pool("boar-attack", i), gap=-0.05)
    if ev == "hurt":
        return pool("boar-hurt", i)
    return fade_out(pool("boar-death", i), 0.6)

@voice("bull")
def bull(ev, i):
    if ev == "call":  # the bellow: a cow's moo brought down to a bull, rasped, a snort before it
        snort = drive(bp(noise(0.25, i), 300, 2500) * np.exp(-np.arange(int(0.25 * SR)) / SR * 18), 2.0) * 0.5
        bellow = growl(drive(deep(pool("cow-moo", i), 0.72, 0.5), 2.2), 30, 0.3)
        return room(seq(snort, peak(bellow, 220, 1.2, 6), gap=0.05), 0.4, 0.15)
    if ev == "hurt":
        return drive(shift(cut(pool("cow-moo", i + 1), 0, 0.7), 0.8), 1.8)
    return room(fade_out(growl(shift(pool("cow-moo", i), 0.62), 22, 0.4), 1.2), 0.5, 0.2)

@voice("rhino")
def rhino(ev, i):
    if ev == "call":  # the rhino's squeal-grunt: a pig brought far down, over a deep rumble
        rumble = shift(pool("croc-call", i), 0.6)
        return room(mix(drive(shift(pool("boar-attack", i), 0.55), 1.8), (rumble, 0.0, 0.6)), 0.45, 0.16)
    if ev == "hurt":
        return drive(shift(pool("boar-hurt", i), 0.58), 1.6)
    return room(fade_out(mix(shift(pool("boar-death", i), 0.5), (shift(pool("croc-death", i), 0.7), 0.2, 0.5)), 1.0), 0.5, 0.2)

@voice("goat")
def goat(ev, i):
    if ev == "call":  # the bleat, with a goat's wobble
        return tremolo(shift(pool("sheep-bleat", i), 1.12), 9.0, 0.5)
    if ev == "hurt":
        return tremolo(shift(cut(pool("sheep-bleat", i + 1), 0, 0.5), 1.3), 10.0, 0.5)
    return fade_out(tremolo(shift(pool("sheep-bleat", i), 0.95), 7.0, 0.6), 0.7)

def elephant_trumpet(i, r=1.0, t=None):
    # The trumpet: a horse's whinny brought down to an elephant's throat (its length kept),
    # blown hard through a brassy band; a short bright blast of a horn only at the start.
    whin = deep(pool("horse-whinny", i), 0.6 * r, 0.35)
    if t is not None:
        whin = cut(whin, 0, t)
    brass = drive(bp(whin, 260, 4200), 4.0)
    blast = trumpet(0.28, 520 * r, (0.9, 1.25, 1.2), i) * 0.3
    return peak(mix((brass, 0.0, 1.0), (blast, 0.0, 1.0)), 700, 1.2, 4)

def elephant_rumble(i, r=1.0):
    return lp(growl(shift(pool("croc-call", i), 0.55 * r), 14, 0.4), 220)

@voice("elephant")
def elephant(ev, i):
    if ev == "call":
        return room(mix(elephant_trumpet(i), (elephant_rumble(i), 0.0, 0.8)), 0.6, 0.2)
    if ev == "hurt":
        return room(mix(elephant_trumpet(i + 1, 1.1, 0.7), (elephant_rumble(i), 0.0, 0.5)), 0.4, 0.14)
    return room(fade_out(seq(elephant_trumpet(i, 0.92), gain(elephant_rumble(i, 0.9), 1.0), gap=-0.4), 1.3), 0.7, 0.24)

@voice("mammoth")
def mammoth(ev, i):
    # Deeper and heavier than the elephant: the trumpet lower, the rumble louder and longer.
    if ev == "call":
        return room(mix(elephant_trumpet(i, 0.78), (elephant_rumble(i, 0.8), 0.0, 1.1)), 0.8, 0.26)
    if ev == "hurt":
        return room(mix(elephant_trumpet(i + 1, 0.85, 0.8), (elephant_rumble(i, 0.8), 0.0, 0.8)), 0.5, 0.18)
    return room(fade_out(seq(elephant_trumpet(i, 0.72), gain(elephant_rumble(i, 0.7), 1.2), gap=-0.5), 1.6), 0.9, 0.3)

@voice("crocodile")
def crocodile(ev, i):
    if ev == "call":  # an alligator's bellow and a hiss
        return room(peak(seq(pool("croc-call", i), pool("croc-attack", i), gap=-0.2), 120, 1.0, 5), 0.4, 0.14)
    if ev == "hurt":
        return pool("croc-hurt", i)
    return room(fade_out(pool("croc-death", i), 0.8), 0.5, 0.18)

@voice("python")
def python(ev, i):
    if ev == "call":  # a long, heavy hiss: a great snake
        return seq(shift(pool("snake-call", i), 0.78), shift(pool("snake-attack", i), 0.8), gap=-0.1)
    if ev == "hurt":
        return shift(pool("snake-hurt", i), 0.8)
    return fade_out(shift(pool("snake-death", i), 0.75), 0.8)

@voice("basilisk")
def basilisk(ev, i):
    # The king of serpents, hatched from a cock's egg: a cock's crow brought down to a croak over a hiss.
    crow = growl(drive(shift(pool("rooster", i), 0.48), 1.8), 40, 0.35)
    if ev == "call":
        return room(mix(shift(pool("snake-call", i), 0.7), (crow, 0.25, 0.9)), 0.5, 0.2)
    if ev == "hurt":
        return room(mix(shift(pool("snake-hurt", i), 0.7), (cut(crow, 0, 0.5), 0.0, 0.8)), 0.3, 0.1)
    return room(fade_out(mix(shift(pool("snake-death", i), 0.65), (shift(crow, 0.85), 0.1, 0.8)), 1.0), 0.6, 0.22)

@voice("scorpion")
def scorpion(ev, i):
    # A rasp of stridulation (a rattle) and a cockroach's hiss, brought down to a giant's.
    rattle = shift(pool("skeleton-call", i), 1.3)
    hiss = drive(shift(pool("spider-attack", i), 0.6), 1.6)
    if ev == "call":
        return mix((rattle, 0.0, 0.7), (hiss, 0.15, 1.0))
    if ev == "hurt":
        return mix((shift(pool("spider-hurt", i), 0.6), 0, 1.0), (shift(pool("skeleton-hurt", i), 1.3), 0, 0.5))
    return fade_out(mix((shift(pool("spider-death", i), 0.6), 0, 1.0), (pool("skeleton-death", i), 0.2, 0.5)), 0.8)

@voice("spider")
def spider(ev, i):
    # A dry chitter of wing snaps, fast, with high chirps: nothing of the scorpion's rasp.
    chit = shift(pool("spider-call", i), 1.15)
    if ev == "call":
        return seq(chit, gain(shift(pool("bats-call", i), 0.55), 0.5), shift(pool("spider-call", i + 1), 1.0), gap=-0.05)
    if ev == "hurt":
        return mix(shift(pool("bats-hurt", i), 0.6), (shift(pool("spider-hurt", i), 1.2), 0.0, 0.6))
    return fade_out(seq(shift(pool("spider-death", i), 1.1), gain(shift(pool("bats-death", i), 0.6), 0.5), gap=-0.2), 0.6)

@voice("ostrich")
def ostrich(ev, i):
    # The ostrich booms like a lion (an owl's hoot brought far down) and hisses.
    boom = peak(growl(shift(pool("owl", i), 0.5), 20, 0.3), 110, 1.0, 8)
    if ev == "call":
        return room(seq(boom, gain(shift(pool("snake-hurt", i), 1.2), 0.5), gap=-0.1), 0.5, 0.18)
    if ev == "hurt":
        return shift(pool("gull", i), 0.75)
    return room(fade_out(seq(shift(pool("gull", i + 1), 0.65), gain(shift(boom, 0.9), 0.8), gap=-0.1), 0.9), 0.5, 0.2)

@voice("griffin")
def griffin(ev, i):
    # An eagle's screech (a gull brought down) ending in a big cat's snarl.
    screech = peak(shift(pool("gull", i), 0.72), 2200, 1.5, 5)
    if ev == "call":
        return room(seq(screech, gain(shift(pool("big-cat-call", i), 0.9), 0.8), gap=-0.2), 0.6, 0.22)
    if ev == "hurt":
        return mix(shift(pool("gull", i + 1), 0.7), (shift(pool("big-cat-hurt", i), 0.9), 0.05, 0.5))
    return room(fade_out(seq(shift(screech, 0.85), gain(shift(pool("big-cat-death", i), 0.9), 0.8), gap=-0.3), 1.0), 0.7, 0.25)

@voice("cerberus")
def cerberus(ev, i):
    # Three hounds at once, each its own depth, in a cavern.
    def three(fam, k, rs=(0.62, 0.78, 0.95), offs=(0.0, 0.12, 0.22)):
        return mix(*[(shift(pool(fam, k + j), rs[j]), offs[j], 1.0 - 0.15 * j) for j in range(3)])
    if ev == "call":
        return room(seq(three("wolf-attack", i), gain(three("dog-bark", i, (0.6, 0.75, 0.9), (0.0, 0.18, 0.3)), 0.9), gap=-0.1), 0.9, 0.3)
    if ev == "hurt":
        return room(three("wolf-hurt", i), 0.5, 0.2)
    return room(fade_out(three("wolf-death", i, (0.6, 0.75, 0.9), (0.0, 0.3, 0.55)), 1.0), 1.0, 0.3)

@voice("hydra")
def hydra(ev, i):
    # Many serpents hissing over one another, over a deep reptile bellow.
    def hisses(fam, k):
        return mix(*[(shift(pool(fam, k + j), r), o, g) for j, (r, o, g) in enumerate([(0.7, 0.0, 1.0), (0.9, 0.15, 0.8), (1.1, 0.28, 0.7), (0.8, 0.45, 0.8)])])
    if ev == "call":
        return room(mix(hisses("snake-call", i), (growl(shift(pool("croc-call", i), 0.65), 20, 0.4), 0.2, 0.9)), 0.8, 0.28)
    if ev == "hurt":
        return room(mix(hisses("snake-hurt", i), (shift(pool("croc-hurt", i), 0.75), 0.0, 0.8)), 0.4, 0.15)
    return room(fade_out(mix(hisses("snake-death", i), (shift(pool("croc-death", i), 0.6), 0.1, 1.0)), 1.4), 0.9, 0.3)

@voice("chimera")
def chimera(ev, i):
    # Lion, goat and serpent, one after another.
    if ev == "call":
        return room(seq(lion_roar(i), tremolo(shift(pool("sheep-bleat", i), 0.95), 9.0, 0.5), shift(pool("snake-attack", i), 0.85), gap=-0.1), 0.6, 0.22)
    if ev == "hurt":
        return mix(tremolo(shift(cut(pool("sheep-bleat", i + 1), 0, 0.6), 1.1), 10.0, 0.5), (shift(pool("big-cat-hurt", i), 0.75), 0.0, 0.7))
    return room(fade_out(seq(lion_roar(i), gain(tremolo(shift(pool("sheep-bleat", i), 0.8), 7.0, 0.6), 0.8), shift(pool("snake-death", i), 0.8), gap=-0.2), 1.2), 0.7, 0.25)

@voice("manticore")
def manticore(ev, i):
    # A lion's body with a man's face: the roar and a man's cry in one throat.
    if ev == "call":
        return room(mix(lion_roar(i), (growl(deep(pool("human-rough-attack", i), 0.75), 35, 0.3), 0.1, 0.9)), 0.6, 0.22)
    if ev == "hurt":
        return mix(shift(pool("human-rough-hurt", i), 0.8), (shift(pool("big-cat-hurt", i), 0.75), 0.0, 0.6))
    return room(fade_out(mix(deep(pool("human-rough-death", i), 0.72), (shift(pool("dragon-death", i), 1.35), 0.3, 0.8)), 1.2), 0.7, 0.25)

@voice("dragon")
def dragon(ev, i):
    if ev == "call":  # the drake's roar, with the fire's breath after it
        return room(seq(pool("dragon-call", i), pool("dragon-attack", i), gain(pool("dragon-breath", i), 0.5), gap=-0.3), 1.0, 0.3)
    if ev == "hurt":
        return room(pool("dragon-hurt", i), 0.5, 0.18)
    return room(fade_out(pool("dragon-death", i), 1.2), 1.1, 0.32)

# The men.
@voice("man")
def man(ev, i):
    # Six takes an event, so a man struck again and again is not heard crying the one cry.
    if ev == "effort":
        return [pool("human-attack", 1), mm("Attack3"), pool("human-attack", 4), mm("Attack5"), pool("human-attack", 2), mm("Attack7")][i - 1]
    if ev == "grunt":
        return [warfork("pain25"), mm("Hit3"), warfork("pain50"), mm("Hit5"), mm("Hit1"), mm("Hit9")][i - 1]
    if ev == "pain":
        return [pool("human-hurt", 1), warfork("pain75"), mm("Hit8"), pool("human-hurt", 3), mm("Hit14"), pool("human-hurt", 4)][i - 1]
    if ev == "scream":
        return [warfork("pain100"), mm("Hit12"), pool("human-rough-hurt", 2), pool("human-hurt", 2), mm("Hit16"), pool("human-rough-hurt", 4)][i - 1]
    return fade_out([warfork("death"), pool("human-death", 1), mm("Death2"), pool("human-death", 2), mm("Death3"), pool("human-death", 3)][i - 1], 0.5)

# The giants of myth (bosses): each his own throat.
@voice("cyclops")
def cyclops(ev, i):
    if ev == "call":  # a huge, slow man's bellow
        return room(growl(drive(deep(pool("human-rough-attack", i), 0.55), 1.8), 24, 0.35), 0.8, 0.28)
    if ev == "hurt":
        return room(deep(pool("human-rough-hurt", i), 0.6), 0.5, 0.18)
    return room(fade_out(deep(pool("human-rough-death", i), 0.55), 1.2), 0.9, 0.3)

@voice("giant")
def giant(ev, i):
    if ev == "call":  # Polyphemus: deeper still, with a heavy breath
        breath = drive(shift(pool("breath", i), 0.5), 1.5) * 0.5
        return room(seq(cut(breath, 0, 0.6), growl(deep(pool("human-attack", i), 0.45), 18, 0.45), gap=-0.1), 1.0, 0.3)
    if ev == "hurt":
        return room(growl(deep(pool("human-hurt", i), 0.48), 20, 0.3), 0.6, 0.2)
    return room(fade_out(growl(deep(pool("human-death", i), 0.45), 16, 0.4), 1.5), 1.1, 0.32)

@voice("minotaur")
def minotaur(ev, i):
    # The bull's head on a man: a bellow and a man's grunt in one.
    if ev == "call":
        return room(mix(growl(drive(deep(pool("cow-moo", i), 0.62, 0.5), 2.0), 28, 0.35), (deep(pool("human-rough-attack", i), 0.7), 0.1, 0.9)), 0.7, 0.25)
    if ev == "hurt":
        return room(mix(deep(pool("human-rough-hurt", i), 0.72), (drive(shift(cut(pool("cow-moo", i + 1), 0, 0.6), 0.75), 1.6), 0.0, 0.6)), 0.4, 0.15)
    return room(fade_out(mix(deep(pool("human-rough-death", i), 0.68), (growl(shift(pool("cow-moo", i), 0.55), 20, 0.4), 0.2, 0.8)), 1.3), 0.8, 0.28)

@voice("troll")
def troll(ev, i):
    if ev == "call":
        return room(seq(pool("troll-call", i), pool("troll-attack", i), gap=-0.2), 0.7, 0.25)
    if ev == "hurt":
        return room(pool("troll-hurt", i), 0.4, 0.15)
    return room(fade_out(pool("troll-death", i), 1.0), 0.8, 0.28)

@voice("titan")
def titan(ev, i):
    # A voice like weather: a man's cry far down, thunder rolling under it.
    thunder = lp(pool("thunder", i), 400)
    if ev == "call":
        return room(mix(growl(drive(deep(pool("human-rough-attack", i), 0.5), 1.6), 14, 0.3), (cut(thunder, 0, 1.6), 0.1, 0.7)), 1.2, 0.35)
    if ev == "hurt":
        return room(mix(deep(pool("human-rough-hurt", i), 0.52), (cut(thunder, 0, 0.8), 0.0, 0.5)), 0.7, 0.22)
    return room(fade_out(mix(deep(pool("human-rough-death", i), 0.48), (cut(thunder, 0, 2.5), 0.3, 0.8)), 1.8), 1.4, 0.38)

EVENTS = {"man": ["effort", "grunt", "pain", "scream", "death"]}
# The longest a cut may run (seconds): a fight has no time for an aria.
LIMIT = {"call": 3.2, "hurt": 1.2, "death": 4.5}

def limit(x, ev):
    n = int(LIMIT.get(ev, 1.5) * SR)
    return fade_out(x[:n], 0.35) if len(x) > n else x
TAKES = 3
TAKES_OF = {"man": 6}

# ---------------------------------------------------------------- output
def write_ogg(x, path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav = f.name
    y = np.clip(x, -1, 1).astype(np.float32)
    import wave, struct
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.unlink(wav)

def main():
    global POOL, CC0
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool", required=True); ap.add_argument("--cc0", required=True)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "art", "audio", "voices"))
    ap.add_argument("--demo", default=""); ap.add_argument("--only", default="")
    a = ap.parse_args()
    POOL, CC0 = a.pool, a.cc0
    os.makedirs(a.out, exist_ok=True)
    if a.demo:
        os.makedirs(a.demo, exist_ok=True)
    for key, fn in V.items():
        if a.only and key not in a.only.split(","):
            continue
        demo = []
        for ev in EVENTS.get(key, ["call", "hurt", "death"]):
            for i in range(1, TAKES_OF.get(key, TAKES) + 1):
                x = finish(limit(fn(ev, i), ev))
                write_ogg(x, os.path.join(a.out, f"{key}_{ev}_{i}.ogg"))
                if a.demo and (ev in ("call", "death") or key == "man" or i == 1):
                    demo.append(x)
        print(key, "ok", flush=True)
        if a.demo:
            d = np.zeros(0)
            for x in demo:
                d = np.concatenate([d, x, np.zeros(int(0.45 * SR))])
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libmp3lame", "-q:a", "3", os.path.join(a.demo, f"demo_{key}.mp3")], input=d.astype(np.float32).tobytes(), check=True)

if __name__ == "__main__":
    main()
