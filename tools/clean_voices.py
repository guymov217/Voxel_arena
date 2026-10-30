#!/usr/bin/env python3
"""The rendered voices made clean for the speakers (run after build_voices.py and
elephant_voice.py): a voice that clips is set down under full scale, one with a fizz of hiss over
it or a click in it is rounded off above 7 kHz (where the hiss lives and a call has little), as
tools/sound_audit.py finds them. Files that pass are left as they are.

  python3 tools/clean_voices.py [art/audio/voices] [--dry]"""
import os, subprocess, sys, tempfile
import numpy as np
from scipy.signal import butter, sosfiltfilt

sys.path.insert(0, os.path.dirname(__file__))
import sound_audit

SR = 44100
PEAK = 0.85
LP_HZ = 7000.0
# A snake's call is all hiss: rounded lower, or it is static from the speakers.
LP_OF = {"python": 4500.0, "basilisk": 4500.0}

def gate(x):
    """The hiss between and after the calls taken down (a soft gate: under 28 dB below the call's
    loudest it is turned down smoothly, the call itself is left whole)."""
    w = max(1, int(0.01 * SR))
    env = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same") + 1e-12)
    thr = env.max() * 10 ** (-28 / 20.0)
    g = np.clip((env / thr) ** 2, 0.05, 1.0)
    # Opens in 5 ms, closes over 60 ms: no chatter, no click.
    out = np.empty_like(g)
    a_up = 1.0 - np.exp(-1.0 / (0.005 * SR))
    a_dn = 1.0 - np.exp(-1.0 / (0.06 * SR))
    v = g[0]
    for i in range(len(g)):
        v += (g[i] - v) * (a_up if g[i] > v else a_dn)
        out[i] = v
    return (x * out).astype(np.float32)

def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()

def encode(x, path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav = f.name
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.unlink(wav)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry" in sys.argv
    d = args[0] if args else os.path.join(os.path.dirname(__file__), "..", "art", "audio", "voices")
    fixed = 0
    for name in sorted(os.listdir(d)):
        if not name.endswith(".ogg"):
            continue
        path = os.path.join(d, name)
        r = sound_audit.audit(path)
        bad = [f for f in r["flags"] if f in ("CLIP", "HISS", "CLICK")]
        # A noise floor under quiet stretches (a call that is loud all through has none).
        if "FLOOR" in r["flags"] and r["floor"] < -20.0:
            bad.append("FLOOR")
        if not bad:
            continue
        x = decode(path)
        if "FLOOR" in bad:
            x = gate(x)
            sos = butter(4, LP_HZ, btype="low", fs=SR, output="sos")
            x = sosfiltfilt(sos, x).astype(np.float32)
        if "HISS" in bad or "CLICK" in bad:
            sos = butter(4, LP_OF.get(name.split("_")[0], LP_HZ), btype="low", fs=SR, output="sos")
            x = sosfiltfilt(sos, x).astype(np.float32)
        # Set down under full scale, then again until the codec's overshoot is under it too.
        target = PEAK
        for _ in range(4):
            pk = float(np.abs(x).max())
            if pk > target:
                x *= target / pk
            if dry:
                break
            encode(x, path)
            got = float(np.abs(decode(path)).max())
            if got <= 0.92:
                break
            target *= 0.92 / got
        print("%-28s %s" % (name, " ".join(bad)))
        fixed += 1
    print("%d voices cleaned" % fixed)

if __name__ == "__main__":
    main()
