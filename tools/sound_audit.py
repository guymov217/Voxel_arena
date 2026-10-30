#!/usr/bin/env python3
"""Checks every sound of the game for what makes it crackle or hiss: clipping, clicks (a jump
between samples no sound of its own makes), a deep static (noise under a made sound's body), hiss (energy high up the spectrum, noise-flat), a
cut-off start or end, and for the recorded voices the noise floor under them (the room and the
microphone's hiss between and behind the calls).

  python3 tools/sound_audit.py DIR...   (WAVs from `-- --probe sfxdump`, art/audio/voices)

Prints one line per sound and a FLAG column; exit status 1 if anything is flagged."""
import os, subprocess, sys
import numpy as np

SR = 22050
# Made sounds that are noise by nature (air, a crowd, a rattle of shards, a hiss), and a squeak
# (one tone sweeping across the band reads as noise to the measure).
BREATHY = ("whoosh", "cheer", "boo", "murmur", "shatter", "hiss", "draw", "freeze", "growl", "roar", "screech", "scream", "pain", "grunt", "squeak")

def load(path):
    if path.endswith(".wav"):
        import wave
        with wave.open(path) as w:
            n = w.getnframes()
            raw = w.readframes(n)
            x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
            if w.getnchannels() > 1:
                x = x.reshape(-1, w.getnchannels()).mean(axis=1)
            return x, w.getframerate()
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32), SR

def band_energy(x, sr, lo, hi):
    if len(x) < 64:
        return 0.0
    win = np.hanning(len(x))
    p = np.abs(np.fft.rfft(x * win)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    tot = p.sum() + 1e-12
    return float(p[(f >= lo) & (f < hi)].sum() / tot)

def flatness(x, sr, lo, hi):
    """Spectral flatness in a band: 1 for white noise, near 0 for tones."""
    if len(x) < 64:
        return 0.0
    p = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    b = p[(f >= lo) & (f < hi)] + 1e-12
    return float(np.exp(np.mean(np.log(b))) / np.mean(b))

def clicks(x, sr):
    """Clicks: a jump between samples that stands alone, throwing energy across the top of the
    spectrum for an instant (a steep but band-limited wave, a brass tone or a buzz, has none
    there; a crack of noise has it all around, not at one sample). The signal high-passed at
    6 kHz, and the samples where it leaps far over its level in the 3 ms around them."""
    if len(x) < 16:
        return 0, 0.0
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    hp = np.fft.irfft(X * (f >= 6000.0), n=len(x))
    a = np.abs(hp)
    k = max(4, int(0.0015 * sr))
    e = hp ** 2
    pad = np.pad(e, (k, k))
    c = np.cumsum(np.concatenate([[0.0], pad]))
    win = (c[2 * k + 1:] - c[:-2 * k - 1])          # sum over the 3 ms window
    near = np.pad(e, (2, 2))
    own = near[:-4] + near[1:-3] + near[2:-2] + near[3:-1] + near[4:]   # the sample and 2 each side
    rest = np.maximum(win - own, 0.0) / max(1, 2 * k + 1 - 5)
    big = (a > 0.03) & (e > 40.0 * rest + 1e-9)
    idx = np.flatnonzero(big)
    n = int((np.diff(idx) > int(0.002 * sr)).sum() + 1) if len(idx) else 0
    return n, float(a.max())

def floor_db(x, sr):
    """The noise under a recording: the quietest 20 ms windows against the loudest."""
    w = max(1, int(0.02 * sr))
    n = len(x) // w
    if n < 6:
        return 0.0, 0.0
    r = np.sqrt((x[: n * w].reshape(n, w) ** 2).mean(axis=1) + 1e-12)
    lo = np.percentile(r, 10)
    hi = r.max()
    # How noise-like the quietest stretch is (static: flat; a breath or a tail: not).
    q = np.argsort(r)[: max(1, n // 10)]
    seg = np.concatenate([x[i * w:(i + 1) * w] for i in sorted(q)])
    return float(20 * np.log10(lo / hi)), flatness(seg, sr, 1500, min(10000, sr / 2 - 1))

def deep_noise(x, sr):
    """A deep static: low-band noise under a sound after its first 20 ms (a knock, a cut, a
    crunch rings in tones; noise filtered down to the body of a blow is heard as static). The
    noise floor of each 30 ms frame in 40-1500 Hz (its median bin, over every bin) against all of
    it, weighted by energy."""
    w = int(0.03 * sr); h = w // 3; i0 = int(0.02 * sr)
    if len(x) < i0 + w:
        return 0.0
    f = np.fft.rfftfreq(w, 1.0 / sr)
    band = (f >= 40) & (f < 1500)
    nz = tot = 0.0
    for s in range(i0, len(x) - w, h):
        b = np.abs(np.fft.rfft(x[s:s + w] * np.hanning(w)))[band] ** 2
        nz += np.median(b) * len(b)
        tot += b.sum()
    return float(nz / max(tot, 1e-12))

def audit(path):
    x, sr = load(path)
    if len(x) == 0:
        return None
    peak = float(np.abs(x).max())
    clip = int((np.abs(x) >= 0.985).sum())
    nclick, dmax = clicks(x, sr)
    hiss = band_energy(x, sr, 5000, sr / 2)
    flat = flatness(x, sr, 2000, min(9000, sr / 2 - 1))
    edge = max(abs(float(x[0])), abs(float(x[-1]))) / (peak + 1e-9)
    fl, fflat = floor_db(x, sr)
    deep = deep_noise(x, sr)
    flags = []
    if clip > 0:
        flags.append("CLIP")
    if nclick > 0:
        flags.append("CLICK")
    if hiss > 0.12 and flat > 0.25:
        flags.append("HISS")
    # Only the made sounds: a breath in a recorded voice, or a crowd, is meant to be noise.
    if path.endswith(".wav") and deep > 0.15 and not os.path.basename(path).startswith(BREATHY):
        flags.append("STATIC")
    if edge > 0.05:
        flags.append("CUT")
    if path.endswith(".ogg") and fl > -45 and fflat > 0.3 and len(x) > sr * 0.3:
        flags.append("FLOOR")
    return {"name": os.path.basename(path), "peak": peak, "clip": clip, "clicks": nclick, "hiss": hiss, "flat": flat, "edge": edge, "floor": fl, "fflat": fflat, "deep": deep, "flags": flags}

def main():
    paths = []
    for d in sys.argv[1:]:
        if os.path.isdir(d):
            paths += [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith((".wav", ".ogg"))]
        else:
            paths.append(d)
    rows = [r for r in (audit(p) for p in paths) if r]
    bad = 0
    print("%-28s %5s %5s %6s %5s %5s %5s %6s %5s %5s  %s" % ("sound", "peak", "clip", "clicks", "hiss", "flat", "edge", "floor", "fflat", "deep", "FLAG"))
    for r in sorted(rows, key=lambda r: (-len(r["flags"]), r["name"])):
        if r["flags"]:
            bad += 1
        print("%-28s %5.2f %5d %6d %5.2f %5.2f %5.2f %6.1f %5.2f %5.2f  %s" % (r["name"], r["peak"], r["clip"], r["clicks"], r["hiss"], r["flat"], r["edge"], r["floor"], r["fflat"], r["deep"], " ".join(r["flags"])))
    print("%d sounds, %d flagged" % (len(rows), bad))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
