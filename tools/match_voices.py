#!/usr/bin/env python3
"""Each voice of a new build set to the loudness of the one it replaces (the loudest 0.4 s of each),
a true limiter keeping its peaks under 0.95: the game no quieter or louder for the swap.

  python3 tools/build_voices.py --hq ... --out /tmp/voices_hq
  python3 tools/match_voices.py art/audio/voices /tmp/voices_hq /tmp/voices_hq_m

Then copy the matched files of the creatures wanted over art/audio/voices. Needs numpy, soundfile
and ffmpeg.
"""
import glob, os, subprocess, sys
import numpy as np
import soundfile as sf

def loud(x):
    w = int(0.4 * 44100)
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    if len(x) <= w:
        return float(np.sqrt(c[-1] / max(1, len(x))))
    return float(np.sqrt(((c[w:] - c[:-w]) / w).max()))

def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    cur, new, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    n = 0
    for f in sorted(glob.glob(os.path.join(new, "*.ogg"))):
        name = os.path.basename(f)
        b, _ = sf.read(f)
        if b.ndim > 1:
            b = b.mean(1)
        g = 1.0
        if os.path.exists(os.path.join(cur, name)):
            a, _ = sf.read(os.path.join(cur, name))
            if a.ndim > 1:
                a = a.mean(1)
            g = loud(a) / max(1e-6, loud(b))
        chain = "volume=%.4f,alimiter=limit=0.95:attack=1:release=40:level=disabled" % g
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f, "-af", chain, "-c:a", "libvorbis", "-q:a", "4", os.path.join(out, name)], check=True)
        n += 1
    print(n, "matched")

if __name__ == "__main__":
    main()
