#!/usr/bin/env python3
"""The score of the rise trailer, written to the cut (tools/make_rise_trailer.py hands it the cue
sheet: where the acts turn, where each cut, card, kill and slow motion falls). Made from nothing,
so it is the game's own and free to use anywhere.

    python tools/rise_score.py <cues.json> <out.wav>

Three acts, as a trailer score goes: a cold open (a heartbeat in the dark, a low drone, the crowd
far off), the rise (a pulse of low strings and taiko on every downbeat, a horn calling), the battle
(the full drum line, the choir of men on D minor, the strings at sixteenths), the climax (all of
it, a roll of toms into every bar), then a silence of a breath and one great hit on the title,
ringing out under the end card. Every kill lands on a sub boom and a braam; under every slow
motion the music sinks, muffled and down in pitch, and comes back up after; a whoosh under every
cut and a shimmer under every card. Needs numpy."""
import json
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import war_drums as wd  # noqa: E402

SR = wd.SR
rng = np.random.default_rng(2027)


def env_exp(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def band(x, lo, hi):
    """A band-pass in the frequency domain (soft edges)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(X * g, len(x))


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def heartbeat():
    """Lub-dub: two low thumps, the second softer."""
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for at, a in ((0.0, 1.0), (0.22, 0.7)):
        k = t - at
        m = k >= 0
        f = 48.0 * (1.0 + 0.6 * np.exp(-np.maximum(k, 0) * 30.0))
        ph = 2 * np.pi * np.cumsum(np.where(m, f, 0.0)) / SR
        out += np.where(m, np.sin(ph) * np.exp(-np.maximum(k, 0) * 11.0), 0.0) * a
    return np.tanh(out * 1.8)


def sub_boom(dur=3.2):
    """The cinematic hit under a kill: a sine falling from 90 to 32 Hz, driven, with a crack of
    noise on top and a long dark tail."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 32.0 + 58.0 * np.exp(-t * 9.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env_exp(n, 1.3)
    crack = band(rng.standard_normal(n), 300.0, 4000.0) * env_exp(n, 30.0) * 0.5
    return np.tanh((body + crack) * 2.2)


def braam(dur=2.6, root=36.71):
    """Low brass, the trailer horn: detuned saws on D1, D2 and A2, the filter opening as it swells
    and closing as it dies, driven hard."""
    n = int(dur * SR)
    x = np.zeros(n)
    for mult, a in ((1.0, 1.0), (2.0, 0.8), (3.0, 0.45), (4.0, 0.25)):
        for d in (-0.004, 0.0, 0.005):
            x += wd.saw(root * mult, n, detune=d, vib=0.002) * a
    att = np.minimum(1.0, np.arange(n) / (0.12 * SR))
    rel = np.exp(-np.maximum(0, np.arange(n) - int(0.9 * SR)) / SR * 2.2)
    x = wd.lowpass(x * att * rel, 700.0)
    return np.tanh(norm(x) * 2.6)


def whoosh(dur=0.7, up=True):
    """Air past the lens under a cut: noise through a band that sweeps up (or down)."""
    n = int(dur * SR)
    nz = rng.standard_normal(n)
    out = np.zeros(n)
    steps = 12
    seg = n // steps
    for i in range(steps):
        fc = 300.0 * (2.0 ** ((i if up else steps - 1 - i) * 0.45))
        s = band(nz[i * seg:(i + 1) * seg + seg], fc * 0.6, fc * 1.8)[:seg]
        out[i * seg:i * seg + len(s)] += s
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return norm(out * e)


def riser(dur):
    """Tension climbing into a hit: noise swelling and brightening, a saw sliding up an octave,
    cut dead at the end."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    nz = band(rng.standard_normal(n), 400.0, 9000.0) * k ** 2.2
    f = 73.42 * (2.0 ** (k * 1.0))
    ph = np.cumsum(f) / SR
    sw = 2.0 * (ph - np.floor(ph + 0.5)) * k ** 1.6
    return norm(nz * 0.7 + wd.lowpass(sw, 2500.0) * 0.5)


def reverse_swell(dur=1.4):
    """A cymbal played backwards into a hit."""
    n = int(dur * SR)
    c = band(rng.standard_normal(n), 3000.0, 14000.0) * env_exp(n, 3.0)
    return norm(c[::-1])


def shimmer(dur=1.6):
    """A bright ringing under a card: high bowed metal."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in (1174.66, 1760.0, 2349.32):
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * (1.0 + 0.3 * np.sin(2 * np.pi * 5.3 * t))
    att = np.minimum(1.0, t / 0.25)
    return norm(x * att * env_exp(n, 2.4))


def ostinato_note(freq, dur):
    """One staccato note of the low strings."""
    n = int(dur * SR)
    x = wd.saw(freq, n, detune=0.0) + wd.saw(freq, n, detune=0.004) + 0.5 * wd.saw(freq * 2.0, n, detune=-0.003)
    e = np.minimum(1.0, np.arange(n) / (0.006 * SR)) * env_exp(n, 9.0)
    return wd.lowpass(x * e, 1400.0)


def make(c):
    length = float(c["length"])
    n = int(length * SR)
    bpm = float(c.get("bpm", 96.0))
    beat = 60.0 / bpm
    bar = beat * 4
    t0 = float(c.get("downbeat", 0.0))
    final = float(c["final"])
    sil0, sil1 = c.get("silence", [final - 1.0, final])
    acts = sorted(c.get("acts", []), key=lambda a: a[0])

    def act_at(t):
        name = "cold"
        for at, nm in acts:
            if t >= at:
                name = nm
        return name

    drums = np.zeros((2, n))
    tonal = np.zeros((2, n))
    fx = np.zeros((2, n))
    taiko = wd.drum(52.0, 1.4, 5.0, 0.9, 2.0, 1.2)
    big = wd.drum(42.0, 1.8, 2.6, 1.3, 3.5, 1.5)
    tom = wd.drum(96.0, 0.9, 9.0, 0.5, 0.9)
    tom2 = wd.drum(128.0, 0.8, 11.0, 0.45, 0.7)
    frame = wd.drum(210.0, 0.4, 22.0, 0.8, 0.4, 0.5)
    clack = wd.lowpass(rng.standard_normal(int(0.06 * SR)), 5000.0) * env_exp(int(0.06 * SR), 90.0)
    hb = heartbeat()
    # The heart in the dark: every other beat through the cold open, quickening.
    t = 0.3
    while t < sil0:
        a = act_at(t)
        if a not in ("cold", "rise"):
            break
        wd.place(drums, hb, t, 0.8 if a == "cold" else 0.55)
        t += beat * (2.0 if a == "cold" else 1.0)
    # The drum line, bar by bar, as hard as the act it is in; nothing in the silence.
    b = 0
    while True:
        tb = t0 + b * bar
        if tb >= sil0 - 0.05:
            break
        b += 1
        a = act_at(tb + 0.01)
        if a == "cold":
            continue
        if a == "rise":
            wd.place(drums, taiko, tb, 0.85)
            if b % 2 == 0:
                wd.place(drums, taiko, tb + beat * 2.5, 0.45, -0.2)
            for e in range(4):
                wd.place(drums, frame, tb + e * beat, 0.16, 0.2 * (1 if e % 2 else -1))
            continue
        wd.place(drums, taiko, tb, 1.0)
        wd.place(drums, taiko, tb + beat * 2, 0.85)
        wd.place(drums, tom, tb + beat * 1.5, 0.55, 0.3)
        wd.place(drums, tom, tb + beat * 3, 0.6, -0.3)
        for e in range(8):
            wd.place(drums, frame, tb + e * beat / 2, 0.2 if e % 2 else 0.32, 0.15 * (1 if e % 2 else -1))
        if a in ("battle", "climax"):
            wd.place(drums, taiko, tb + beat * 0.75, 0.7)
            wd.place(drums, taiko, tb + beat * 3.5, 0.75)
            wd.place(drums, clack, tb + beat, 0.35, 0.4)
            wd.place(drums, clack, tb + beat * 3, 0.35, -0.4)
        if a == "climax":
            for e in range(8):
                wd.place(drums, taiko, tb + e * beat / 2, 0.5, 0.1 * (1 if e % 2 else -1))
            for s16 in range(8):   # a roll of toms into every next bar
                wd.place(drums, tom2 if s16 % 2 else tom, tb + beat * 2 + s16 * beat / 4, 0.3 + 0.07 * s16, 0.5 - 0.15 * s16)
    # Low strings at sixteenths from the battle on (eighths in the rise), on D minor, a bar each
    # of D, D, Bb, A.
    roots = [73.42, 73.42, 58.27, 55.0]
    notes = {}
    b = 0
    while True:
        tb = t0 + b * bar
        if tb >= sil0 - 0.05:
            break
        a = act_at(tb + 0.01)
        if a in ("rise", "battle", "climax"):
            r = roots[b % 4]
            step = beat / 2 if a == "rise" else beat / 4
            k = 0
            while k * step < bar - 1e-6:
                f = r * (2.0 if (k % 4 == 3 and a != "rise") else 1.0)
                if f not in notes:
                    notes[f] = ostinato_note(f, step * 0.9)
                acc = 1.0 if k % 4 == 0 else 0.6
                wd.place(tonal, notes[f], tb + k * step, 0.16 * acc * (1.35 if a == "climax" else 1.0), 0.3 * (1 if k % 2 else -1))
                k += 1
        b += 1
    # The drone and the choir: the drone from the start, the choir from the battle on.
    tt = np.arange(n) / SR
    drone = np.sin(2 * np.pi * 36.71 * tt) * 0.5 + 0.3 * wd.lowpass(wd.saw(73.42, n, vib=0.002), 400.0)
    choir = np.zeros(n)
    for f in (146.83, 174.61, 220.0, 293.66):
        for v in range(4):
            choir += wd.saw(f, n, detune=rng.uniform(-0.006, 0.006), vib=0.004, vib_hz=rng.uniform(4.5, 5.8))
    choir = norm(wd.formant(choir, [(700.0, 110.0, 1.0), (1150.0, 130.0, 0.55), (2600.0, 220.0, 0.25), (300.0, 120.0, 0.4)]))
    lvl_d = np.zeros(n)
    lvl_c = np.zeros(n)
    for i in range(n // 441 + 1):
        tt_i = i * 441 / SR
        a = act_at(tt_i)
        d = {"cold": 0.55, "rise": 0.7, "battle": 0.8, "climax": 0.9}.get(a, 0.0)
        ch = {"battle": 0.42, "climax": 0.6}.get(a, 0.0)
        lvl_d[i * 441:(i + 1) * 441] = d
        lvl_c[i * 441:(i + 1) * 441] = ch
    sm = int(0.6 * SR)
    kern = np.ones(sm) / sm
    lvl_d = np.convolve(lvl_d, kern, mode="same")
    lvl_c = np.convolve(lvl_c, kern, mode="same")
    tonal[0] += drone * lvl_d * 0.5 + choir * lvl_c * 0.42
    tonal[1] += drone * lvl_d * 0.5 + np.roll(choir, 300) * lvl_c * 0.42
    # The horn calls at each act's turn.
    for i, (at, nm) in enumerate(acts):
        if nm in ("rise", "battle", "climax") and at < sil0 - bar:
            m = int(bar * 1.4 * SR)
            h = wd.saw(73.42, m, vib=0.006) + 0.6 * wd.saw(110.0, m, vib=0.006) + 0.3 * wd.saw(146.83, m, vib=0.005)
            e = np.minimum(1.0, np.arange(m) / (0.5 * SR)) * np.minimum(1.0, (m - np.arange(m)) / (0.8 * SR))
            wd.place(tonal, norm(wd.lowpass(h * e, 1100.0 + 300.0 * i)), at, 0.4, 0.25 * (-1 if i % 2 else 1))
    # The events of the cut.
    sb = sub_boom()
    br = braam()
    wh = [whoosh(0.7, True), whoosh(0.6, False)]
    sh = shimmer()
    for i, ht in enumerate(c.get("hits", [])):
        if ht < sil0:
            wd.place(fx, sb, ht, 0.9)
            wd.place(fx, br, ht, 0.45)
            wd.place(fx, reverse_swell(1.2), ht - 1.2, 0.35)
    for i, ct in enumerate(c.get("cuts", [])):
        wd.place(fx, wh[i % 2], ct - 0.3, 0.32, 0.4 * (1 if i % 2 else -1))
    for ct in c.get("cards", []):
        wd.place(fx, sh, ct, 0.18)
    for r0, r1 in c.get("risers", []):
        if r1 > r0:
            wd.place(fx, riser(r1 - r0), r0, 0.45)
    # The music under a slow motion: sunk, muffled and bent down; back up after.
    for s0, s1 in c.get("slows", []):
        i0, i1 = int(s0 * SR), min(n, int(s1 * SR))
        if i1 - i0 < SR // 10:
            continue
        for buf in (drums, tonal):
            for ch in range(2):
                seg = buf[ch, i0:i1].copy()
                low = wd.lowpass(seg, 380.0)
                k = np.ones(i1 - i0)
                r = min(int(0.25 * SR), (i1 - i0) // 3)
                k[:r] = np.linspace(0, 1, r)
                k[-r:] = np.linspace(1, 0, r)
                buf[ch, i0:i1] = seg * (1 - k) + low * k * 0.55
    # The silence before the title: everything gone but a breath, then the great hit.
    i0, i1 = int(sil0 * SR), int(sil1 * SR)
    for buf in (drums, tonal, fx):
        r = int(0.08 * SR)
        buf[:, max(0, i0 - r):i0] *= np.linspace(1, 0, min(r, i0))
        buf[:, i0:] = 0.0
    wd.place(fx, reverse_swell(0.5), final - 0.5, 0.3)
    wd.place(drums, big, final, 2.0)
    wd.place(drums, taiko, final, 1.2, -0.3)
    wd.place(drums, taiko, final, 1.2, 0.3)
    wd.place(fx, sub_boom(5.0), final, 1.0)
    wd.place(fx, braam(4.5), final, 0.7)
    tail = np.zeros(n)
    m = n - int(final * SR)
    if m > 0:
        ch = choir[:m] * env_exp(m, 0.55)
        tail[-m:] = ch
    tonal[0] += tail * 0.55
    tonal[1] += np.roll(tail, 300) * 0.55
    out = np.zeros((2, n))
    for ch in range(2):
        out[ch] = wd.reverb(drums[ch], 2.0, 0.26, ch) * 0.95 + wd.reverb(tonal[ch], 3.2, 0.42, 10 + ch) * 0.7 + wd.reverb(fx[ch], 2.6, 0.3, 20 + ch) * 0.8
    # (The reverbs' tails die in the silence too: a held breath, then the swell into the hit.)
    g0, g1 = int(sil0 * SR), int((final - 0.5) * SR)
    if g1 > g0:
        r = min(int(0.12 * SR), g1 - g0)
        gate = np.ones(n)
        gate[g0:g1] = 0.02
        gate[g0:g0 + r] = np.linspace(1.0, 0.02, r)
        out *= gate
    out = np.tanh(out * 1.15)
    out /= np.max(np.abs(out)) + 1e-9
    f0 = int(0.03 * SR)
    out[:, :f0] *= np.linspace(0, 1, f0)
    f1 = int(1.2 * SR)
    out[:, -f1:] *= np.linspace(1, 0, f1)
    return out * 0.92


def write(path, out):
    pcm = (np.clip(out, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.T.tobytes())


def main():
    with open(sys.argv[1]) as f:
        cues = json.load(f)
    out = make(cues)
    write(sys.argv[2], out)
    print("score: %.1f s, %d hits, the title hit at %.2f s -> %s" % (cues["length"], len(cues.get("hits", [])), cues["final"], sys.argv[2]))


if __name__ == "__main__":
    main()
