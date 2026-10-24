#!/usr/bin/env python3
"""War drums for the second trailer (tools/make_rise_trailer.py): a Norse-sounding battle track
made from nothing, so it is the game's own and free to use. Big low drums (taiko-like hits with
a pitch drop), toms and a frame drum, a horn calling over a low drone and a choir of men holding
an "aah" on D minor, all in a stone-hall reverb. It builds bar by bar to one great hit at HIT
seconds (the end card), and rings out to LENGTH.

    python tools/war_drums.py <out.wav> <length s> [<hit s>]

Needs numpy (pip install numpy)."""
import sys
import wave

import numpy as np

SR = 44100
BPM = 96.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
rng = np.random.default_rng(1066)


def env_exp(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def lowpass(x, cutoff):
    """A gentle low-pass in the frequency domain (the whole signal at once)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    X *= 1.0 / (1.0 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def drum(f0, drop, decay, noise, dur=1.6, body=1.0):
    """A struck skin: a sine falling from f0*(1+drop) to f0, plus a short thump of noise."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1.0 + drop * np.exp(-t * 28.0))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) * env_exp(n, decay) * body
    tone += 0.35 * np.sin(2 * ph * 1.01) * env_exp(n, decay * 1.8)
    nz = lowpass(rng.standard_normal(n), 900.0) * env_exp(n, 38.0) * noise
    return np.tanh((tone + nz) * 1.6)


def saw(freq, n, detune=0.0, vib=0.0, vib_hz=5.0):
    t = np.arange(n) / SR
    f = freq * (1.0 + detune) * (1.0 + vib * np.sin(2 * np.pi * vib_hz * t + rng.uniform(0, 6.28)))
    ph = np.cumsum(f) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def formant(x, peaks):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.zeros_like(f)
    for fc, bw, a in peaks:
        g += a * np.exp(-0.5 * ((f - fc) / bw) ** 2)
    return np.fft.irfft(X * g, len(x))


def reverb(x, secs=2.4, wet=0.32, seed=0):
    n = int(secs * SR)
    r = np.random.default_rng(seed)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / secs))
    ir = lowpass(ir, 3500.0)
    ir /= np.sqrt(np.sum(ir ** 2))
    m = len(x) + n
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[: len(x)]
    return x * (1.0 - wet) + y * wet


def place(buf, s, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= buf.shape[1]:
        return
    k = min(len(s), buf.shape[1] - i)
    buf[0, i:i + k] += s[:k] * gain * np.sqrt(0.5 * (1.0 - pan))
    buf[1, i:i + k] += s[:k] * gain * np.sqrt(0.5 * (1.0 + pan))


def make(length, hit):
    n = int(length * SR)
    drums = np.zeros((2, n))
    pads = np.zeros((2, n))
    taiko = drum(52.0, 1.4, 5.0, 0.9, 2.0, 1.2)
    big = drum(42.0, 1.8, 2.6, 1.3, 3.5, 1.5)
    tom = drum(96.0, 0.9, 9.0, 0.5, 0.9)
    tom2 = drum(128.0, 0.8, 11.0, 0.45, 0.7)
    frame = drum(210.0, 0.4, 22.0, 0.8, 0.4, 0.5)
    clack = lowpass(rng.standard_normal(int(0.06 * SR)), 5000.0) * env_exp(int(0.06 * SR), 90.0)
    bars = int(hit / BAR)
    t0 = hit - bars * BAR          # the groove runs so the great hit falls on a downbeat
    for b in range(bars):
        tb = t0 + b * BAR
        k = b / max(1, bars - 1)   # 0 at the start, 1 at the climax
        part = 0 if k < 0.15 else (1 if k < 0.45 else (2 if k < 0.8 else 3))
        if part == 0:
            place(drums, taiko, tb, 0.9)
            if b % 2 == 1:
                place(drums, taiko, tb + BEAT * 2.5, 0.5, -0.2)
            continue
        place(drums, taiko, tb, 1.0)
        place(drums, taiko, tb + BEAT * 2, 0.85)
        place(drums, tom, tb + BEAT * 1.5, 0.55, 0.3)
        place(drums, tom, tb + BEAT * 3, 0.6, -0.3)
        for e in range(8):
            place(drums, frame, tb + e * BEAT / 2, (0.18 if e % 2 else 0.3) * (0.6 + 0.4 * k), 0.15 * (1 if e % 2 else -1))
        if part >= 2:
            place(drums, taiko, tb + BEAT * 0.75, 0.7)
            place(drums, taiko, tb + BEAT * 3.5, 0.75)
            place(drums, clack, tb + BEAT, 0.35, 0.4)
            place(drums, clack, tb + BEAT * 3, 0.35, -0.4)
            if b % 2 == 1:
                for s16 in range(4):   # a fill of toms into the next bar
                    place(drums, tom2 if s16 % 2 else tom, tb + BEAT * 3 + s16 * BEAT / 4, 0.5 + 0.1 * s16, 0.5 - 0.3 * s16)
        if part == 3:
            for e in range(8):
                place(drums, taiko, tb + e * BEAT / 2, 0.45 + 0.4 * (e / 7.0) * (b == bars - 1), 0.1 * (1 if e % 2 else -1))
            if b == bars - 1:
                for r in range(16):     # the last bar rolls up into the hit
                    place(drums, tom if r % 2 else tom2, tb + BEAT * 2 + r * BEAT / 8, 0.25 + 0.5 * r / 15.0, 0.6 * (1 if r % 2 else -1))
    place(drums, big, hit, 2.0)
    place(drums, taiko, hit, 1.2, -0.3)
    place(drums, taiko, hit, 1.2, 0.3)
    # The drone and the choir under it all, swelling as the drums build; the horn calls over it.
    tt = np.arange(n) / SR
    swell = np.clip(tt / 6.0, 0, 1) * (0.55 + 0.45 * np.clip((tt - t0) / max(1.0, hit - t0), 0, 1))
    swell *= np.where(tt < hit, 1.0, np.exp(-(tt - hit) * 0.8))
    drone = np.sin(2 * np.pi * 36.71 * tt) * 0.5 + 0.3 * lowpass(saw(73.42, n, vib=0.002), 400.0)
    choir = np.zeros(n)
    for f in (146.83, 174.61, 220.0, 293.66):   # D3 F3 A3 D4
        for v in range(4):
            choir += saw(f, n, detune=rng.uniform(-0.006, 0.006), vib=0.004, vib_hz=rng.uniform(4.5, 5.8))
    choir = formant(choir, [(700.0, 110.0, 1.0), (1150.0, 130.0, 0.55), (2600.0, 220.0, 0.25), (300.0, 120.0, 0.4)])
    choir /= np.max(np.abs(choir)) + 1e-9
    pads[0] += (drone * 0.55 + choir * 0.42) * swell
    pads[1] += (drone * 0.55 + np.roll(choir, 300) * 0.42) * swell
    horn_t = [t0 + BAR, t0 + BAR * 0.5 + (hit - t0) * 0.45, t0 + (hit - t0) * 0.75, hit - BAR]
    for i, ht in enumerate(horn_t):
        d = BAR * (1.6 if i < 3 else 1.0)
        m = int(d * SR)
        h = (saw(73.42, m, vib=0.006) + 0.6 * saw(110.0, m, vib=0.006) + 0.3 * saw(146.83, m, vib=0.005))
        a = np.minimum(1.0, np.arange(m) / (0.5 * SR)) * np.minimum(1.0, (m - np.arange(m)) / (0.8 * SR))
        h = lowpass(h * a, 900.0 + 500.0 * i)
        place(pads, h / (np.max(np.abs(h)) + 1e-9), ht, 0.38 + 0.08 * i, 0.25 * (-1 if i % 2 else 1))
    out = np.zeros((2, n))
    for c in range(2):
        out[c] = reverb(drums[c], 2.0, 0.28, c) * 0.9 + reverb(pads[c], 3.2, 0.45, 10 + c) * 0.7
    out = np.tanh(out * 1.2)
    out /= np.max(np.abs(out)) + 1e-9
    fade = int(0.04 * SR)
    out[:, :fade] *= np.linspace(0, 1, fade)
    return (out * 0.92 * 32767).astype(np.int16)


def main():
    path = sys.argv[1]
    length = float(sys.argv[2])
    hit = float(sys.argv[3]) if len(sys.argv) > 3 else length - 4.0
    pcm = make(length, hit)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.T.tobytes())
    print("war drums: %.1f s, the hit at %.1f s -> %s" % (length, hit, path))


if __name__ == "__main__":
    main()
