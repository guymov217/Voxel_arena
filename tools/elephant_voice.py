#!/usr/bin/env python3
"""The elephant's and the mammoth's voices, made in code the way the animal makes them (no
recording of one is to be had): the vocal folds buzz at the foot of a pipe three metres long
(throat, nose and trunk), and everything heard comes of that.

- The folds: a puff of air a cycle, never two alike: each cycle a little late or early, a little
  big or small, now and then every other one weak (a growl an octave down), and in the wild
  parts the order breaks down altogether (the "chaos" of a real trumpet). A second buzz at an odd
  ratio comes in for a moment in the screams (two voices at once).
- The trunk: the pipe's own resonances, worked out from its length and its narrowing to the tip
  (a lossy, wet-walled tube; its many close peaks colour the sound as the pitch moves through
  them), and the throw of the sound from the nostrils into the air.
- The brass: a sound this loud runs ahead of itself down a pipe that long, its crests catching up
  with its troughs until each wave front stands up into a shock: the blare of a trombone at full
  blast, and of a trumpeting elephant (Gilbert, Dalmont, Potier & Reby 2014).
- The flutter of the trunk (a rattle of 20 to 35 a second), breath through the folds with each
  puff, and air rushing out of the nostrils.
- Under it: the rumble from the chest (a purr at 14 to 20 a second through the same trunk), the
  roar through the open mouth (in pain and in rage), and the breath out.
The mammoth is the same throat, bigger: a longer, wider pipe, a lower and slower buzz, more growl,
more roar and more rumble, a darker top.

  python3 tools/elephant_voice.py [--out art/audio/voices] [--demo <dir>] [--only elephant] [--style big|wild]

Needs numpy, scipy and ffmpeg, and build_voices.py beside it (the arena's room, the limiter).
"""
import argparse, os, re, subprocess, sys, tempfile, wave
import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(__file__))
import build_voices as bv

SR = bv.SR
OS = 4
FS = SR * OS        # the buzz and the shock waves are made at 176.4 kHz, then brought down
C = 350.0           # sound in the warm, wet air of a throat (m/s)
RHO = 1.14
NFFT = 1 << 17      # the pipes' responses: 0.74 s at FS, longer than any ringing in them

# ---------------------------------------------------------------- the shapes of things in time
def ease(keys, n, fs=FS):
    """[(t, v), ...] in seconds → n samples, eased from key to key (two keys at one time: a jump)."""
    t = np.arange(n) / fs
    ts = np.array([k[0] for k in keys], float)
    vs = np.array([k[1] for k in keys], float)
    if len(ts) == 1:
        return np.full(n, vs[0])
    i = np.clip(np.searchsorted(ts, t, side="right") - 1, 0, len(ts) - 2)
    t0, t1 = ts[i], ts[i + 1]
    u = np.clip((t - t0) / np.maximum(t1 - t0, 1e-9), 0.0, 1.0)
    u = u * u * (3 - 2 * u)
    return vs[i] + (vs[i + 1] - vs[i]) * u

def wander(n, hz, rng, fs=FS):
    """A random wander at about `hz` (unit RMS): the throat never holds anything dead steady."""
    cr = max(50.0, hz * 12.0)
    m = int(n / fs * cr) + 16
    w = signal.sosfiltfilt(signal.butter(2, hz / (cr / 2), output="sos"), rng.normal(0, 1, m))
    w /= np.std(w) + 1e-9
    return np.interp(np.arange(n) / fs * cr, np.arange(m), w)

def hiss(n, rng, lo, hi, fs=FS):
    x = signal.sosfilt(signal.butter(2, [lo, hi], btype="band", fs=fs, output="sos"), rng.normal(0, 1, n))
    return x / (np.std(x) + 1e-9)

# ---------------------------------------------------------------- the folds
def folds(f0, amp, rng, jit, shim, sub, oq, sk, fs=FS):
    """The buzz: one puff of air a cycle (a Rosenberg pulse: the folds part, the flow swells, they
    slam shut, they stay shut). Per sample: the pitch, the level, how much each cycle's length
    (jit) and size (shim) stray, the period doubling (sub: every other cycle late and weak), how
    long the folds stand open (oq) and how late in that the flow peaks (sk). Returns the flow and
    the opening (0 shut .. 1 wide) for the breath that goes with it."""
    n = len(f0)
    dur = n / fs
    st, pe, am, oo, ss = [], [], [], [], []
    t, k = 0.0, 0
    while t < dur:
        i = min(n - 1, int(t * fs))
        T = 1.0 / max(float(f0[i]), 5.0) * float(np.clip(1.0 + jit[i] * rng.normal(), 0.55, 1.6))
        s = float(sub[i])
        odd = k % 2 == 1
        T *= 1.0 + 0.11 * s * (-1.0 if odd else 1.0)
        a = float(amp[i]) * max(0.0, 1.0 + float(shim[i]) * rng.normal()) * ((1.0 - 0.62 * s) if odd else 1.0)
        st.append(t); pe.append(T); am.append(a)
        oo.append(float(np.clip(oq[i] * (1.0 + 0.05 * rng.normal()), 0.25, 0.95)))
        ss.append(float(np.clip(sk[i] + 0.04 * rng.normal(), 0.45, 0.92)))
        t += T; k += 1
    st, pe, am, oo, ss = map(np.array, (st, pe, am, oo, ss))
    tt = np.arange(n) / fs
    c = np.clip(np.searchsorted(st, tt, side="right") - 1, 0, len(st) - 1)
    u = (tt - st[c]) / pe[c]
    o = oo[c]; tp = o * ss[c]; tn = o - tp
    g = np.where(u < tp, 0.5 * (1 - np.cos(np.pi * u / tp)), np.where(u < o, np.cos(0.5 * np.pi * (u - tp) / tn), 0.0))
    return am[c] * g, g

# ---------------------------------------------------------------- the pipes
_pipes = {}
def pipe(sections, loss=1.6, damp=0.15, fs=FS):
    """The flow out of the open end of a pipe of cylinders [(length m, radius m), ...] (from the
    folds to the end) for a flow in at the folds: a transmission line with wet walls (losses with
    the root of the frequency, more in a narrow pipe), `damp` (Np/m) soaked up at every pitch alike
    (the folded, soft-walled nose and the folds letting go of some each cycle), and the open end's
    radiation load. Returned as an impulse response."""
    key = (tuple(sections), loss, damp, fs)
    if key in _pipes:
        return _pipes[key]
    f = np.fft.rfftfreq(NFFT, 1.0 / fs)
    f[0] = 0.5
    k = 2 * np.pi * f / C
    A = np.ones_like(k, complex); B = np.zeros_like(k, complex)
    Cc = np.zeros_like(k, complex); D = np.ones_like(k, complex)
    for L, r in sections:
        Zc = RHO * C / (np.pi * r * r)
        g = damp + loss * 3.0e-5 * np.sqrt(f) / r + 1j * k
        ch = np.cosh(g * L); sh = np.sinh(g * L)
        A, B, Cc, D = A * ch + B * sh / Zc, A * Zc * sh + B * ch, Cc * ch + D * sh / Zc, Cc * Zc * sh + D * ch
    a = sections[-1][1]
    beta = 0.6133 * k * a
    Zr = RHO * C / (np.pi * a * a) * (1j * beta) / (1 + 1j * beta)
    H = 1.0 / (Cc * Zr + D)
    H[0] = 0.0
    _pipes[key] = np.fft.irfft(H, NFFT)
    return _pipes[key]

def radiate(x, a, fs=FS):
    """From the open end into the air: rising 6 dB an octave up to where the opening is as wide
    as the wave is short (ka = 1), level above."""
    return signal.sosfilt(signal.butter(1, C / (2 * np.pi * a), btype="high", fs=fs, output="sos"), x)

def through(x, h):
    return signal.fftconvolve(x, h)[:len(x)]

def shock(x, sigma, f0, fs=FS):
    """Nonlinear propagation down the trunk: the crest of each wave runs a little faster than its
    trough, so the rising fronts steepen, the louder the more, into shocks at the loudest. sigma
    is the trunk's length over the distance a wave of pitch f0 at the loudest moment's level
    takes to turn into a shock (1.0: it just does at the tip; 2: a sawtooth by then)."""
    if sigma <= 0:
        return x
    x = x - signal.sosfiltfilt(signal.butter(1, 30, fs=fs, output="sos"), x)
    w = int(0.05 * fs)
    loud = np.sqrt(np.max(np.convolve(x * x, np.ones(w) / w, mode="valid")) * 2.0) + 1e-12
    n = np.arange(len(x), dtype=float)
    arr = np.maximum.accumulate(n - sigma / (2 * np.pi * f0 / fs * loud) * x) + n * 1e-9
    return np.interp(n, arr, x)

def down(x):
    """176.4 kHz to 44.1 kHz, with a clean filter (nothing above 20 kHz folds back)."""
    return signal.resample_poly(x, 1, OS, window=("kaiser", 8.0))

def _rms1(x):
    return x / (np.sqrt(np.mean(x * x)) + 1e-12)

# ---------------------------------------------------------------- the animals
# The pipes, folds to tip. The elephant's three metres: throat, nose, then the trunk narrowing to
# its two nostrils (taken together). The mouth, for the roar: the throat and an open mouth.
def trunk(s):
    return [(0.35 * s, 0.035 * s), (0.45 * s, 0.028 * s), (0.70 * s, 0.024 * s), (0.80 * s, 0.020 * s), (0.70 * s, 0.017 * s)]

def mouth(s):
    return [(0.35 * s, 0.035 * s), (0.30 * s, 0.045 * s), (0.18 * s, 0.055 * s), (0.08 * s, 0.065 * s)]

# f0: the trumpet's pitch (Hz); s: the size of the pipes; slow: how drawn out it all is; rum: the
# rumble's buzz (Hz); roar: the roar's pitch (share); growl: period doubling always in it; under:
# how loud the rumble under the calls; top: where the highs are rounded off; room: the arena's;
# damp: what the soft, folded walls of the nose and trunk soak up besides (Np/m; the trunk's many
# close peaks are blunted by it).
ELEPHANT = dict(key="elephant", f0=430.0, s=1.0, slow=1.0, rum=18.0, roar=1.0, growl=0.0, under=1.0, top=9000.0,
                room=(0.75, 0.16), damp=0.15, seed=100)
MAMMOTH = dict(key="mammoth", f0=300.0, s=1.18, slow=1.15, rum=14.0, roar=0.8, growl=0.22, under=1.5, top=6200.0,
               room=(0.95, 0.20), damp=0.15, seed=200)

def _keys(an, keys):
    return [(t * an["slow"], v) for t, v in keys]

def blast(an, dur, pitch, level, rng, chaos=((0, 0.1),), sub=((0, 0.0),), biph=((0, 0.0),), biph_ratio=1.33,
          flutter=(28.0, 0.3), breath=0.18, sigma=1.2, onset_air=0.6):
    """A trumpet: the folds through the trunk, at full blast. Times in seconds, `pitch` in shares of
    the animal's pitch, `level` 0..1."""
    s = an["s"]
    n = int(dur * an["slow"] * FS)
    p = ease(_keys(an, pitch), n); lev = ease(_keys(an, level), n)
    wild = an.get("wild", 1.0)
    ch = np.clip(ease(_keys(an, chaos), n) * wild, 0, 1)
    sb = np.clip(ease(_keys(an, sub), n) + an["growl"] * lev, 0, 1)
    bi = np.clip(ease(_keys(an, biph), n), 0, 1)
    fl_hz, fl_dep = flutter[0], flutter[1] * wild
    rate = fl_hz / an["slow"] * (1 + 0.15 * wander(n, 1.5, rng))
    flut = 0.5 - 0.5 * np.cos(2 * np.pi * np.cumsum(rate) / FS)
    dep = fl_dep * np.clip(0.75 + 0.45 * wander(n, 1.2, rng), 0.1, 1.5)
    f = an["f0"] * p * (1 + 0.022 * wander(n, 2.5, rng)) * (1 + 0.010 * wander(n, 11.0, rng)) * (1 + 0.025 * dep * (flut - 0.5))
    amp = np.maximum(lev * (1 + 0.07 * wander(n, 7.0, rng)) * (1 - 0.85 * dep * flut), 0)
    ln = lev / max(1e-6, float(lev.max()))
    oq = 0.78 - 0.26 * ln; sk = 0.62 + 0.18 * ln
    U, g = folds(f, amp, rng, 0.004 + 0.07 * ch, 0.04 + 0.30 * ch, sb, oq, sk)
    if bi.max() > 0:
        U2, g2 = folds(f * biph_ratio * (1 + 0.03 * wander(n, 1.0, rng)), amp * bi * 0.8, rng,
                       0.012 + 0.10 * ch, 0.08 + 0.3 * ch, np.zeros(n), oq, sk)
        U = U + U2; g = np.maximum(g, g2)
    # Breath through the folds with each puff, more in the wild parts and at the very start (it
    # goes down the trunk too, but is not loud enough in itself to turn into shocks).
    tt = np.arange(n) / FS
    air = breath * wild + 0.45 * ch + onset_air * np.exp(-tt / 0.05)
    h = pipe(trunk(s), damp=an["damp"])
    y = shock(through(U, h), sigma * an.get("brass", 1.0), an["f0"])
    # The fronts stood up near the tip are rounded off a little by the last stretch of wet wall
    # (no front sharper than ~0.1 ms: a blare, not a click).
    y = signal.sosfilt(signal.butter(2, an.get("front", 6500.0), fs=FS, output="sos"), y)
    y = y + through(hiss(n, rng, 350, 7000) * (0.3 + 0.7 * g ** 1.5) * amp * air * 0.12, h)
    y = radiate(y, trunk(s)[-1][1])
    # Air rushing out of the nostrils (outside the pipe: a hiss over the blare).
    y = _rms1(y) + hiss(n, rng, 1800, 9000) * amp ** 1.5 * (0.03 + 0.10 * ch)
    return down(y)

def roar(an, dur, pitch, level, rng, f0=140.0, chaos=((0, 0.5),), sub=((0, 0.4),), flutter=(30.0, 0.45), breath=0.6):
    """The roar: the folds through the open mouth, loose and wild (pain, rage, the end)."""
    s = an["s"]
    n = int(dur * an["slow"] * FS)
    p = ease(_keys(an, pitch), n); lev = ease(_keys(an, level), n)
    wild = an.get("wild", 1.0)
    ch = np.clip(ease(_keys(an, chaos), n) * wild, 0, 1)
    sb = np.clip(ease(_keys(an, sub), n) + an["growl"], 0, 1)
    rate = flutter[0] / an["slow"] * (1 + 0.2 * wander(n, 2.0, rng))
    flut = 0.5 - 0.5 * np.cos(2 * np.pi * np.cumsum(rate) / FS)
    dep = flutter[1] * wild * np.clip(0.8 + 0.4 * wander(n, 1.5, rng), 0.1, 1.5)
    f = f0 * an["roar"] * p * (1 + 0.04 * wander(n, 3.0, rng)) * (1 + 0.04 * dep * (flut - 0.5))
    amp = np.maximum(lev * (1 + 0.1 * wander(n, 6.0, rng)) * (1 - 0.8 * dep * flut), 0)
    U, g = folds(f, amp, rng, 0.02 + 0.14 * ch, 0.10 + 0.4 * ch, sb, np.full(n, 0.6), np.full(n, 0.7))
    U = U + hiss(n, rng, 200, 5000) * (0.35 + 0.65 * g) * amp * (breath * wild + 0.4 * ch) * 0.35
    y = through(U, pipe(mouth(s), loss=1.2, damp=0.3))
    y = shock(y, 0.5, f0 * an["roar"])
    y = radiate(y, mouth(s)[-1][1])
    return down(_rms1(y))

def rumble(an, dur, level, rng, fall=0.15, chaos=0.06):
    """The rumble: the folds slow (14 to 20 a second) through the trunk; under 40 Hz it is felt
    more than heard, what carries is the purr of its pulses through the trunk's low peaks."""
    s = an["s"]
    d = dur * an["slow"]
    n = int(d * FS)
    lev = ease(_keys(an, level), n)
    tt = np.arange(n) / FS
    f = an["rum"] * (1 - fall * tt / d) * (1 + 0.05 * wander(n, 1.0, rng))
    amp = np.maximum(lev * (1 + 0.12 * wander(n, 3.0, rng)), 0)
    U, g = folds(f, amp, rng, np.full(n, 0.03 + chaos), np.full(n, 0.08 + chaos), np.zeros(n), np.full(n, 0.55), np.full(n, 0.65))
    U = U + hiss(n, rng, 60, 900) * g * amp * 0.15
    y = through(U, pipe(trunk(s), damp=an["damp"]))
    y = radiate(y, trunk(s)[-1][1])
    y = signal.sosfilt(signal.butter(2, 900, fs=FS, output="sos"), y)
    return down(_rms1(y))

def exhale(an, dur, level, rng):
    """Breath out through the trunk: the pipe's hollow whoosh."""
    s = an["s"]
    n = int(dur * an["slow"] * FS)
    lev = ease(_keys(an, level), n)
    y = through(hiss(n, rng, 150, 6000) * lev, pipe(trunk(s), damp=an["damp"]))
    y = radiate(y, trunk(s)[-1][1])
    return down(_rms1(y))

# ---------------------------------------------------------------- the takes
def _mix(an, parts, room=None):
    """[(sound, at seconds, gain), ...] laid out (times drawn out by a big animal's slowness),
    then the arena's room."""
    items = [(x, at * an["slow"], g) for x, at, g in parts]
    n = max(int(at * SR) + len(x) for x, at, g in items)
    out = np.zeros(n)
    for x, at, g in items:
        i = int(at * SR)
        out[i:i + len(x)] += x * g
    size, wet = room or an["room"]
    wet *= an.get("wet", 1.0)
    return bv.arena_room(out, size * an["slow"], wet, seed=an["seed"])

def call(an, i):
    r = np.random.default_rng(an["seed"] + 10 + i)
    U = an["under"]
    if i == 1:
        # The trumpet: up with a blat, held with the trunk's rattle in it, a growl in the middle,
        # down at the end.
        t = blast(an, 1.55, [(0, .62), (.05, .9), (.11, 1.1), (.2, 1.04), (.45, 1.0), (.75, 1.03), (1.2, .97), (1.38, .86), (1.55, .58)],
                  [(0, 0), (.03, .55), (.1, 1), (.6, .92), (1.1, .95), (1.35, .7), (1.55, 0)], r,
                  chaos=[(0, .7), (.09, .15), (.5, .08), (.62, .35), (.72, .1), (1.3, .25), (1.55, .7)],
                  sub=[(0, 0), (.55, 0), (.6, .7), (.78, .6), (.82, 0)], flutter=(28, .3), sigma=1.3)
        ru = rumble(an, 1.4, [(0, 0), (.3, 1), (.9, .7), (1.4, 0)], r)
        return _mix(an, [(t, 0.0, 1.0), (ru, 1.15, 0.22 * U)])
    if i == 2:
        # Two blasts: a short one, then the long one, which jumps up a step in the middle.
        a = blast(an, 0.5, [(0, .7), (.06, 1.08), (.3, 1.05), (.5, .75)], [(0, 0), (.04, .85), (.35, .8), (.5, 0)], r,
                  chaos=[(0, .6), (.07, .12), (.4, .2), (.5, .6)], flutter=(30, .25), sigma=1.0)
        b = blast(an, 1.25, [(0, .75), (.07, 1.12), (.3, 1.1), (.45, 1.1), (.45, 1.27), (.68, 1.25), (.68, 1.08), (1.0, 1.0), (1.25, .62)],
                  [(0, 0), (.05, .7), (.12, 1), (.9, .95), (1.1, .6), (1.25, 0)], r,
                  chaos=[(0, .5), (.1, .1), (.43, .3), (.5, .1), (.66, .3), (.72, .1), (1.1, .4), (1.25, .7)],
                  sub=[(0, 0), (.85, 0), (.92, .6), (1.05, .5), (1.12, 0)], flutter=(32, .25), sigma=1.4)
        ru = rumble(an, 1.2, [(0, 0), (.3, 1), (1.2, 0)], r)
        return _mix(an, [(a, 0.0, 0.85), (b, 0.6, 1.0), (ru, 1.55, 0.2 * U)])
    # A roar that breaks into a trumpet, two voices at once for a moment, rattling.
    ro = roar(an, 0.5, [(0, .85), (.15, 1.15), (.5, 1.05)], [(0, 0), (.06, 1), (.35, .8), (.5, 0)], r, f0=150,
              chaos=[(0, .5)], sub=[(0, .3)])
    t = blast(an, 1.35, [(0, .7), (.07, 1.05), (.35, 1.02), (.6, 1.06), (1.0, .95), (1.2, .82), (1.35, .6)],
              [(0, 0), (.05, .8), (.12, 1), (.9, .9), (1.2, .55), (1.35, 0)], r,
              chaos=[(0, .5), (.1, .15), (.7, .1), (1.2, .4), (1.35, .8)],
              biph=[(0, 0), (.3, 0), (.38, .55), (.58, .5), (.66, 0)], biph_ratio=1.34, flutter=(24, .4), sigma=1.2)
    ru = rumble(an, 1.3, [(0, 0), (.4, 1), (1.3, 0)], r)
    return _mix(an, [(ro, 0.0, 0.5), (t, 0.3, 1.0), (ru, 1.35, 0.22 * U)])

def hurt(an, i):
    r = np.random.default_rng(an["seed"] + 30 + i)
    if i == 1:
        # A shriek of a trumpet, high and torn, two voices in it, over a short roar.
        t = blast(an, 0.58, [(0, .85), (.05, 1.3), (.25, 1.24), (.45, 1.12), (.58, .8)], [(0, 0), (.03, 1), (.4, .85), (.58, 0)], r,
                  chaos=[(0, .6), (.07, .3), (.3, .45), (.58, .85)], biph=[(0, 0), (.14, 0), (.18, .6), (.34, .5), (.4, 0)],
                  biph_ratio=1.42, flutter=(35, .3), breath=0.3, sigma=1.1)
        ro = roar(an, 0.42, [(0, 1), (.42, .8)], [(0, 0), (.04, 1), (.42, 0)], r, f0=170, chaos=[(0, .6)])
        return _mix(an, [(t, 0.0, 1.0), (ro, 0.02, 0.35)], room=(0.55, 0.13))
    if i == 2:
        # Two sharp cries.
        a = blast(an, 0.24, [(0, .9), (.04, 1.32), (.24, 1.0)], [(0, 0), (.025, 1), (.15, .8), (.24, 0)], r,
                  chaos=[(0, .5), (.24, .7)], flutter=(34, .2), breath=0.3, sigma=1.0)
        b = blast(an, 0.38, [(0, .9), (.05, 1.38), (.2, 1.3), (.38, .85)], [(0, 0), (.03, 1), (.25, .8), (.38, 0)], r,
                  chaos=[(0, .5), (.1, .3), (.38, .8)], sub=[(0, 0), (.2, .5), (.38, .5)], flutter=(34, .3), breath=0.3, sigma=1.1)
        return _mix(an, [(a, 0.0, 0.85), (b, 0.3, 1.0)], room=(0.55, 0.13))
    # A roar of pain with a squeal over it.
    ro = roar(an, 0.6, [(0, 1.1), (.2, 1.15), (.6, .8)], [(0, 0), (.04, 1), (.4, .8), (.6, 0)], r, f0=165,
              chaos=[(0, .6), (.6, .8)], sub=[(0, .45)])
    t = blast(an, 0.45, [(0, .95), (.05, 1.4), (.3, 1.3), (.45, .95)], [(0, 0), (.04, .9), (.3, .8), (.45, 0)], r,
              chaos=[(0, .5), (.45, .8)], flutter=(36, .35), breath=0.35, sigma=0.9)
    return _mix(an, [(ro, 0.0, 0.75), (t, 0.05, 0.8)], room=(0.55, 0.13))

def death(an, i):
    r = np.random.default_rng(an["seed"] + 50 + i)
    U = an["under"]
    if i == 1:
        # A long trumpet that sags and breaks, then the groan, the rumble and the last breath.
        t = blast(an, 1.9, [(0, .7), (.08, 1.05), (.5, .98), (1.0, .88), (1.5, .72), (1.9, .5)],
                  [(0, 0), (.06, 1), (.8, .85), (1.5, .55), (1.9, 0)], r,
                  chaos=[(0, .5), (.1, .15), (.8, .3), (1.4, .6), (1.9, .9)], sub=[(0, 0), (.85, 0), (1.0, .6), (1.5, .6), (1.6, .2)],
                  flutter=(30, .35), sigma=1.1)
        gr = roar(an, 1.3, [(0, 1), (1.3, .62)], [(0, 0), (.15, 1), (.8, .6), (1.3, 0)], r, f0=110, chaos=[(0, .4), (1.3, .75)])
        ru = rumble(an, 1.6, [(0, 0), (.3, 1), (1.6, 0)], r, fall=0.25)
        ex = exhale(an, 0.7, [(0, 0), (.08, 1), (.7, 0)], r)
        return _mix(an, [(t, 0.0, 1.0), (gr, 1.6, 0.55), (ru, 2.2, 0.3 * U), (ex, 3.3, 0.18)], room=(0.9, 0.2))
    if i == 2:
        # Two trumpets, the second weaker and lower, breaking down; the groan and the rumble.
        a = blast(an, 0.85, [(0, .7), (.07, 1.12), (.4, 1.08), (.85, .8)], [(0, 0), (.05, 1), (.6, .9), (.85, 0)], r,
                  chaos=[(0, .5), (.1, .15), (.6, .3), (.85, .7)], flutter=(30, .3), sigma=1.2)
        b = blast(an, 1.25, [(0, .7), (.08, .95), (.5, .85), (1.0, .65), (1.25, .5)], [(0, 0), (.06, .75), (.7, .55), (1.25, 0)], r,
                  chaos=[(0, .5), (.1, .3), (.6, .6), (1.25, .95)], sub=[(0, 0), (.3, .7), (.9, .7)], flutter=(24, .45), breath=0.3, sigma=0.8)
        gr = roar(an, 1.0, [(0, .9), (1.0, .6)], [(0, 0), (.2, 1), (1.0, 0)], r, f0=100, chaos=[(0, .5), (1.0, .8)])
        ru = rumble(an, 1.7, [(0, 0), (.4, 1), (1.7, 0)], r, fall=0.3)
        return _mix(an, [(a, 0.0, 1.0), (b, 0.95, 0.9), (gr, 1.9, 0.45), (ru, 2.0, 0.32 * U)], room=(0.9, 0.2))
    # A scream, two voices, falling apart into a deep groan; the rumble and the breath out.
    t = blast(an, 1.3, [(0, .8), (.06, 1.25), (.4, 1.18), (.9, .95), (1.3, .62)], [(0, 0), (.04, 1), (.9, .8), (1.3, 0)], r,
              chaos=[(0, .6), (.1, .3), (.9, .55), (1.3, .9)], biph=[(0, 0), (.2, 0), (.28, .6), (.62, .55), (.7, 0)],
              biph_ratio=1.38, flutter=(33, .35), breath=0.3, sigma=1.0)
    gr = roar(an, 1.5, [(0, 1.05), (.6, .9), (1.5, .58)], [(0, 0), (.12, 1), (.9, .65), (1.5, 0)], r, f0=120,
              chaos=[(0, .45), (1.5, .8)], sub=[(0, .5)])
    ru = rumble(an, 1.5, [(0, 0), (.3, 1), (1.5, 0)], r, fall=0.25)
    ex = exhale(an, 0.6, [(0, 0), (.07, 1), (.6, 0)], r)
    return _mix(an, [(t, 0.0, 1.0), (gr, 1.05, 0.6), (ru, 1.9, 0.3 * U), (ex, 3.0, 0.16)], room=(0.9, 0.2))

EVENTS = {"call": call, "hurt": hurt, "death": death}
ANIMALS = {"elephant": ELEPHANT, "mammoth": MAMMOTH}
# The game's voices are the "big" style (picked by ear over the wild one): the same throats, tamer
# and bigger, as a film would have them: less of the wildness (chaos, rattle, breath), a rounder
# blare, a little lower, more rumble under it and more of the arena around it. "--style wild" makes
# the rougher, more lifelike set.
BIG = dict(wild=0.55, brass=0.85, pitch=0.94, under=1.4, wet=1.35)
# How loud each animal's takes are (LUFS): the elephant as the other big beasts; the mammoth set
# down (at full level it was deafening, user).
LEVEL = {"elephant": -14.0, "mammoth": -16.0}

def styled(an, style):
    if style != "big":
        return an
    return dict(an, wild=BIG["wild"], brass=BIG["brass"], f0=an["f0"] * BIG["pitch"], under=an["under"] * BIG["under"], wet=BIG["wet"])

def lufs(x):
    """Integrated loudness (EBU R128, ffmpeg's meter) of a take."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    os.unlink(path)
    found = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
    return float(found[-1]) if found else -70.0

def level(x, target, limit=0.89):
    """A take brought to `target` LUFS, its peaks held under `limit` by a look-ahead limiter (the
    brass's sharp fronts would otherwise set the level of the whole)."""
    g = 1.0
    y = x
    for _ in range(4):
        y = bv.ff(x * g, "alimiter=limit=%.3f:attack=2:release=60:level=disabled:asc=1" % limit)
        l = lufs(y)
        if abs(l - target) < 0.3:
            break
        g *= 10 ** ((target - l) / 20)
    return y

def make(an, ev, i):
    """One take, finished: the top rounded off (the mammoth's darker), through the limiter, at the
    animal's loudness."""
    bv.HQ = True
    x = EVENTS[ev](an, i)
    x = signal.sosfiltfilt(signal.butter(2, an["top"], fs=SR, output="sos"), x)
    return level(bv.finish(x, 0.89), LEVEL[an["key"]])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "art", "audio", "voices"))
    ap.add_argument("--demo", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--style", default="big", choices=["big", "wild"])
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for key, an in ANIMALS.items():
        if a.only and key != a.only:
            continue
        an = styled(an, a.style)
        demo = []
        for ev in EVENTS:
            for i in (1, 2, 3):
                x = make(an, ev, i)
                bv.write_ogg(x, os.path.join(a.out, f"{key}_{ev}_{i}.ogg"))
                demo.append(x)
        if a.demo:
            os.makedirs(a.demo, exist_ok=True)
            d = np.concatenate([np.concatenate([x, np.zeros(int(0.4 * SR))]) for x in demo])
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libmp3lame", "-q:a", "3",
                            os.path.join(a.demo, f"demo_{key}.mp3")], input=d.astype(np.float32).tobytes(), check=True)
        print(key, "ok")

if __name__ == "__main__":
    main()
