#!/usr/bin/env python3
"""The music of WRECKSMITH played by real instruments: every piece of scripts/autoload/music.gd
(the same tunes, chords, rhythms and moods) performed note by note from recorded samples and
mixed into a seamless loop, written to art/audio/music/<piece>.ogg. The game plays these files;
the synthesised version stays as its fallback.

The band, every voice a recording (all CC0, see art/CREDITS.md):
  - frame drum, darbuka (the dum and the tek), tambourine (the riq's jingles), war toms and
    bass drum, suspended cymbal, hand claps, a smith's anvil, gong and tubular bells
    (Versilian Community Sample Library);
  - folk harp and plucked psaltery (the lyre), alto recorder (VCSL); oboe (the aulos, a double
    reed); horn, trombone, tuba and trumpet (the cornu and the tuba of the arena); violins,
    violas, cellos and contrabass, bowed, tremolo, spiccato and pizzicato; timpani
    (Versilian Studios Chamber Orchestra 2, Community Edition).

    python3 tools/make_music.py [--samples DIR] [--out DIR] [--only fight,boss] [--demo DIR]

SAMPLES is the folder holding VCSL/ and VSCO-2-CE/ (github.com/sgossner). Needs numpy, scipy
and ffmpeg."""
import argparse
import glob
import os
import random
import re
import subprocess
import tempfile

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- the pieces (music.gd)
SCALE = [0, 1, 4, 5, 7, 8, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
MIXOLYDIAN = [0, 2, 4, 5, 7, 9, 10]
AEOLIAN = [0, 2, 3, 5, 7, 8, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]
HARMONIC_MINOR = [0, 2, 3, 5, 7, 8, 11]
D3, E3, G3, C3, F3, CS3 = 50, 52, 55, 48, 53, 49

# Every piece as in music.gd (root as a MIDI note), and how it is voiced here: `pipe` an oboe
# (the aulos) or a recorder, `drone` low strings (held, or a tremolo for the beasts), `choir` a brass
# chorale (the cornu and the tuba), `lyre` the plucked psaltery or the harp.
STATES = {
    "menu": dict(bpm=76, drone=0.7, lyre=0.55, density=0.35, bars=8, root=D3, scale=SCALE),
    "menu2": dict(bpm=66, scale=DORIAN, root=E3, drone=0.4, pipe=0.55, pipe_kind="recorder", arp=0.3, pad=0.5, density=0.3, chords=[0, 0, 3, 3, 6, 6, 0, 0], bars=8),
    "yard": dict(bpm=92, drum=0.25, riq=0.35, drone=0.5, lyre=0.6, density=0.45, bars=8, root=D3, scale=SCALE),
    "yard2": dict(bpm=104, scale=MIXOLYDIAN, root=G3, drum=0.3, riq=0.45, clap=0.45, drone=0.25, pipe=0.45, pipe_kind="recorder", arp=0.28, bass=0.35, density=0.5, swing=0.16, chords=[0, 6, 3, 0, 0, 6, 3, 4], bars=8),
    "yard3": dict(bpm=86, scale=AEOLIAN, root=C3, drum=0.2, anvil=0.5, anvil_pat=[1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0], drone=0.55, lyre=0.55, bass=0.3, density=0.4, chords=[0, 5, 6, 0, 0, 5, 3, 4], bars=8),
    "forge": dict(bpm=90, scale=DORIAN, root=D3, anvil=0.35, anvil_pat=[1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0], drone=0.4, lyre=0.35, arp=0.25, pad=0.3, bass=0.25, density=0.3, chords=[0, 3, 0, 3, 6, 3, 0, 0], bars=8),
    "fight": dict(bpm=118, drum=0.85, riq=0.5, drone=0.4, lyre=0.4, horn=0.2, bass=0.7, strings=0.4, stab=0.3, fills=1.0, density=0.45, bars=16, root=D3, scale=SCALE),
    "fight2": dict(bpm=126, scale=PHRYGIAN, root=E3, drum=0.55, toms=0.7, toms_pat=[2, 0, 0, 1, 0, 0, 2, 0, 2, 0, 0, 1, 0, 0, 1, 1], riq=0.35, drone=0.35, pipe=0.3, horn=0.4, bass=0.75, strings=0.5, stab=0.35, fills=1.0, density=0.4, chords=[0, 0, 1, 1, 0, 0, 6, 6], bars=16),
    "fight3": dict(bpm=120, scale=HARMONIC_MINOR, root=D3, drum=0.45, toms=0.7, toms_pat=[1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 2], riq=0.4, drone=0.3, lyre=0.25, horn=0.5, horn_lead=True, bass=0.7, strings=0.45, fills=1.0, density=0.45, chords=[0, 0, 5, 5, 3, 3, 4, 4], bars=16),
    "beast": dict(bpm=132, scale=PHRYGIAN, root=F3, drum=0.55, toms=0.75, toms_pat=[2, 0, 1, 0, 0, 1, 2, 0, 2, 0, 1, 1, 0, 1, 2, 1], riq=0.45, drone=0.45, drone_kind="tremolo", pipe=0.35, bass=0.55, strings=0.35, fills=0.8, density=0.35, chords=[0, 0, 0, 1], bars=16),
    "boss": dict(bpm=136, drum=1.0, riq=0.7, drone=0.5, lyre=0.25, horn=0.65, bass=0.9, strings=0.6, stab=0.7, fills=1.0, density=0.55, bars=16, root=D3, scale=SCALE),
    "boss2": dict(bpm=140, scale=SCALE, root=CS3, drum=0.85, toms=0.65, toms_pat=[2, 0, 0, 0, 2, 0, 1, 0, 2, 0, 0, 0, 2, 0, 1, 1], riq=0.55, drone=0.4, choir=0.5, horn=0.55, bass=0.75, strings=0.5, stab=0.55, fills=0.9, density=0.5, chords=[0, 0, 1, 1, 0, 0, 3, 1], bars=16),
    "victory": dict(bpm=104, drum=0.6, riq=0.6, drone=0.4, lyre=0.6, horn=0.8, horn_kind="trumpet", density=0.7, bars=2, once=True, root=D3, scale=SCALE),
    "defeat": dict(bpm=58, scale=AEOLIAN, root=D3, toll=0.7, drone=0.4, strings=0.5, horn=0.6, line=[[0, 4, 5], [6, 3, 4], [10, 2, 6], [16, 1, 5], [22, 0, 10]], density=0.0, chords=[3, 0], bars=2, once=True),
}
DUM = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0]
TEK = [0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
DUM2 = [1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1, 0]
BASS = [0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 7, 1, 0]
BASS_ON = [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0]
ARP = [0, 2, 4, 7, 4, 2, 4, 2]
# How loud each piece sits (RMS of the mix), as the synthesised ones: the menu quiet, a boss loud.
LOUD = {"menu": 0.045, "menu2": 0.05, "yard": 0.052, "yard2": 0.058, "yard3": 0.053, "forge": 0.04,
        "fight": 0.13, "fight2": 0.145, "fight3": 0.14, "beast": 0.15, "boss": 0.155, "boss2": 0.165,
        "victory": 0.09, "defeat": 0.064}


def djb2(s):
    """Godot's String.hash(): the tunes come out note for note as the synthesised ones."""
    h = 5381
    for ch in s:
        h = ((h << 5) + h + ord(ch)) & 0xFFFFFFFF
    return h


def phrase(seed, density, land=0):
    s = (seed * 9301 + 49297) % 233280
    notes = []
    deg = 4
    for i in range(16):
        s = (s * 9301 + 49297) % 233280
        r = s / 233280.0
        if i == 14:
            notes.append({"step": i, "deg": land if r < 0.5 else (land + 4 if land + 4 <= 9 else land - 3), "len": 2})
            break
        if r < ((density + 0.3) if i % 4 == 0 else density * 0.7):
            s = (s * 9301 + 49297) % 233280
            r2 = s / 233280.0
            deg += ((-3 if r2 < 0.07 else 3) if r2 < 0.15 else (-1 if r2 < 0.57 else 1))
            deg = max(-2, min(9, deg))
            notes.append({"step": i, "deg": deg, "len": 2 if r2 > 0.7 else 1})
    return notes


def midi(sc, root, deg, octave=0):
    m = len(sc)
    return root + sc[deg % m] + 12 * (octave + deg // m)


# ---------------------------------------------------------------- the samples
LIB = "/home/user/samples"
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
_cache = {}
_lead = {}


def decode(path):
    if path in _cache:
        return _cache[path]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)
    # The silence before the note taken off (a hair of it kept).
    a = np.abs(x).max(axis=1)
    pk = a.max() if len(a) else 0.0
    if pk > 0:
        idx = np.nonzero(a > pk * 0.006)[0]
        if len(idx):
            x = x[max(0, idx[0] - int(0.002 * SR)):]
    _cache[path] = x
    # How long the sample takes to speak (half its peak, within its first half second): a played
    # note is begun that much ahead of the beat so the hit lands on it (the brass stabs, a pizz,
    # a bass drum took 20 to 140 ms to come up and every one of them dragged behind the drums).
    a = np.abs(x).max(axis=1)
    w = max(1, int(0.002 * SR))
    env = np.convolve(a[:int(0.5 * SR)], np.ones(w) / w, mode="same")
    k = np.nonzero(env >= 0.5 * env.max())[0] if len(env) and env.max() > 0 else []
    _lead[path] = min(0.15, max(0.0, k[0] / SR - 0.003)) if len(k) else 0.0
    return x


def note_of(name):
    m = re.search(r"_([A-G]#?)(-?\d)(?=[_.])", name)
    return 12 * (int(m.group(2)) + 1) + NOTE[m.group(1)] if m else None


def vel_of(name):
    m = re.search(r"_v[l]?(\d)", name)
    if m:
        return int(m.group(1))
    m = re.search(r"_(ppp|pp|p|mp|mf|ff|fff|f)[_.]", name)
    return {"ppp": 1, "pp": 1, "p": 2, "mp": 2, "mf": 3, "f": 4, "ff": 5, "fff": 6}[m.group(1)] if m else 2


class Inst:
    """A recorded instrument: its samples by the note they sound (or round robins of a drum),
    the range it plays, how it is placed in the stereo field and how loud it sits."""

    def __init__(self, globs, pitched=True, lo=0, hi=127, pan=0.0, gain=1.0, release=0.12, attack=0.0):
        files = []
        for g in globs:
            files += glob.glob(os.path.join(LIB, g))
        files = sorted(set(files))
        if not files:
            raise SystemExit("no samples for %s" % globs)
        self.samples = [(note_of(os.path.basename(f)) if pitched else None, vel_of(os.path.basename(f)), f) for f in files]
        if pitched:
            self.samples = [s for s in self.samples if s[0] is not None]
        self.pitched, self.lo, self.hi, self.pan, self.gain, self.release, self.attack = pitched, lo, hi, pan, gain, release, attack
        self.rr = {}
        # one peak for the whole instrument: its own soft and loud layers keep their difference
        self.norm = 1.0 / max(1e-6, max(np.abs(decode(f)).max() for _, _, f in self.samples))

    def pick(self, note, vel, rng):
        vmax = max(v for _, v, _ in self.samples)
        want = 1 + round(vel * (vmax - 1))
        if self.pitched:
            best = min(abs(s[0] - note) for s in self.samples)
            cands = [s for s in self.samples if abs(s[0] - note) == best]
        else:
            cands = self.samples
        vbest = min(abs(s[1] - want) for s in cands)
        cands = [s for s in cands if abs(s[1] - want) == vbest]
        return cands[rng.randrange(len(cands))]

    def render(self, note, vel, dur, rng):
        root, _, f = self.pick(note, vel, rng)
        x = decode(f) * self.norm
        self.lead = _lead.get(f, 0.0)
        if self.pitched and root != note:
            r = 2.0 ** ((note - root) / 12.0)
            self.lead /= r
            pos = np.arange(0, len(x) - 1, r)
            x = np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in (0, 1)], axis=1)
        if dur is not None:
            n = min(len(x), int((dur + self.release) * SR))
            x = x[:n].copy()
            rel = min(n, int(self.release * SR))
            if rel > 0 and n >= int(dur * SR):
                x[-rel:] *= np.linspace(1, 0, rel)[:, None] ** 1.5
        else:
            x = x.copy()
        if self.attack > 0:
            na = min(len(x), int(self.attack * SR))
            x[:na] *= np.linspace(0, 1, na)[:, None]
        g = self.gain * (0.35 + 0.65 * vel)
        L = np.cos((self.pan + 1) * np.pi / 4)
        R = np.sin((self.pan + 1) * np.pi / 4)
        return x * g * np.array([L, R]) * 1.41


def band():
    V, C = "VSCO-2-CE", "VCSL"
    M, I = C + "/Membranophones/Struck Membranophones", C + "/Idiophones/Struck Idiophones"
    return {
        "dum": Inst([M + "/Frame Drum/HDrumL_Hit_v*.wav"], False, pan=0.0, gain=1.0, release=0.05),
        "doum": Inst([M + "/Darbuka/Darbuka_1_hit_*.wav"], False, pan=-0.05, gain=0.8),
        "tek": Inst([M + "/Darbuka/Darbuka_4_hit_*.wav"], False, pan=0.18, gain=0.55),
        "riq": Inst([I + "/Tambourine 1/Tamb1_Hit_*.wav"], False, pan=-0.3, gain=0.4),
        "zill": Inst([I + "/Finger Cymbals/*.wav"], False, pan=0.35, gain=0.3),
        "roll": Inst([M + "/Frame Drum/HDrumS_Hit_v*.wav"], False, pan=0.1, gain=0.6),
        "crash": Inst([I + "/Suspended Cymbal 1/susCymb1_hit_" + v + ".wav" for v in ("pp1", "mp1", "f1", "fff1")], False, pan=0.2, gain=0.45),
        "tom_hi": Inst([M + "/Tom 1/Mallet/TomH_HitM_v*.wav"], False, pan=-0.2, gain=0.7),
        "tom_lo": Inst([M + "/Bass Drum 1/BDrumNew_hit_v*.wav"], False, pan=0.0, gain=1.0),
        "timp": Inst([V + "/Percussion/Timpani/Timpani*_Hit_v*.wav"], False, pan=0.1, gain=0.8),
        "anvil": Inst([I + "/Anvil/*.wav"], False, pan=0.35, gain=0.45),
        "clap": Inst([I + "/Claps/Clap_rr*.wav"], False, pan=-0.15, gain=0.45),
        "gong": Inst([I + "/Gong 1/gong_mf.wav", I + "/Gong 1/gong_p.wav"], False, pan=0.0, gain=0.6),
        "bell": Inst([I + "/Tubular Bells 1/*.wav"], True, pan=0.15, gain=0.5, release=1.5),
        "bass": Inst([V + "/Strings/Solo Contrabass/Pizz/*.wav"], True, 24, 60, pan=-0.05, gain=0.9, release=0.08),
        "bass_bow": Inst([V + "/Strings/Cello Section/spic/*.wav"], True, 36, 72, pan=0.12, gain=0.55, release=0.06),
        "harp": Inst([V + "/Strings/Harp/*.wav"], True, 28, 100, pan=-0.4, gain=0.5, release=0.6),
        "lyre": Inst([C + "/Chordophones/Zithers/Psaltery, Bowed and Plucked/Pluck/*.wav"], True, 55, 90, pan=0.25, gain=0.6, release=0.5),
        "lyre_low": Inst([C + "/Chordophones/Composite Chordophones/Folk Harp/*.wav"], True, 30, 80, pan=0.25, gain=0.6, release=0.5),
        "oboe": Inst([V + "/Woodwinds/Oboe/Vib/*.wav"], True, 58, 93, pan=-0.12, gain=0.55, release=0.15, attack=0.02),
        "recorder": Inst([C + "/Aerophones/Edge-blown Aerophones/Baroque Alto Recorder/SusVib/*.wav"], True, 53, 89, pan=-0.12, gain=0.55, release=0.15, attack=0.02),
        "horn": Inst([V + "/Brass/F Horn/sus/*.wav"], True, 34, 77, pan=0.2, gain=0.6, release=0.25, attack=0.03),
        "horn_stac": Inst([V + "/Brass/F Horn/stac/*.wav"], True, 34, 77, pan=0.2, gain=0.6, release=0.08),
        "trumpet": Inst([V + "/Brass/Trumpet/sus/*.wav"], True, 52, 84, pan=0.25, gain=0.55, release=0.2, attack=0.02),
        "trombone": Inst([V + "/Brass/Tenor Trombone/sus/*.wav"], True, 28, 72, pan=-0.2, gain=0.55, release=0.25, attack=0.04),
        "trombone_stac": Inst([V + "/Brass/Tenor Trombone/stac/*.wav"], True, 28, 72, pan=-0.2, gain=0.6, release=0.08),
        "tuba": Inst([V + "/Brass/Tuba/sus/*.wav"], True, 22, 60, pan=0.0, gain=0.55, release=0.3, attack=0.05),
        "cello_trem": Inst([V + "/Strings/Cello Section/trem/*.wav"], True, 36, 72, pan=-0.3, gain=0.45, release=0.3, attack=0.08),
        "viola_trem": Inst([V + "/Strings/Viola Section/trem/*.wav"], True, 48, 84, pan=0.05, gain=0.4, release=0.3, attack=0.08),
        "violin_trem": Inst([V + "/Strings/Violin Section/Trem/*.wav"], True, 55, 100, pan=0.35, gain=0.4, release=0.3, attack=0.08),
        "violins": Inst([V + "/Strings/Violin Section/susVib/*.wav"], True, 55, 100, pan=0.3, gain=0.4, release=0.5, attack=0.35),
        "cellos": Inst([V + "/Strings/Cello Section/susvib/*.wav"], True, 36, 72, pan=-0.3, gain=0.45, release=0.5, attack=0.3),
        "contrabass": Inst([V + "/Strings/Solo Contrabass/SusNV/*.wav"], True, 24, 60, pan=0.0, gain=0.5, release=0.6, attack=0.4),
    }


# ---------------------------------------------------------------- the performance
def perform(name, st, B, rng):
    """Every note of the piece: (time, instrument, MIDI note, velocity 0..1, duration or None)."""
    sc = st.get("scale", SCALE)
    rt = st.get("root", D3)
    step = 60.0 / st["bpm"] / 4.0
    bar_s = step * 16
    bars = st["bars"]
    chords = st.get("chords", [0])
    swing = st.get("swing", 0.0)
    ev = []
    drum, riq = st.get("drum", 0.0), st.get("riq", 0.0)
    once = st.get("once", False)

    def hum(t, amt=0.003):
        return t + rng.uniform(-amt, amt)   # a player, not a machine

    if st.get("drone", 0.0) > 0:
        if st.get("drone_kind") == "tremolo":
            for bar in range(0, bars, 2):
                ev.append((bar * bar_s, "cello_trem", midi(sc, rt, 0, -1), 0.45 * st["drone"] + 0.3, bar_s * 2 + 0.3))
        for bar in range(bars):
            c = chords[bar % len(chords)] if st.get("chords") else 0
            for d, inst, octv in ((0, "contrabass", -1), (4, "cellos", -1), (0, "cellos", 0)):
                ev.append((bar * bar_s, inst, midi(sc, rt, (c if inst != "contrabass" else 0) + d, octv), 0.35 + 0.4 * st["drone"], bar_s + 0.7))
    for bar in range(bars):
        c = chords[bar % len(chords)]
        mel = phrase(bar * 7 + djb2(name) % 97, st["density"], c)
        for s in range(16):
            t0 = (bar * 16 + s) * step + (swing * step if s % 2 == 1 else 0.0)
            if drum > 0:
                driving = st.get("bass", 0.0) > 0 and (bar // 4) % 2 == 1
                if (DUM2 if driving else DUM)[s]:
                    ev.append((hum(t0, 0.003), "dum", None, 0.55 + 0.45 * drum, None))
                    if drum > 0.5 and s % 8 == 0:
                        ev.append((hum(t0, 0.003), "doum", None, 0.5 * drum, None))
                if TEK[s]:
                    ev.append((hum(t0), "tek", None, 0.35 + 0.5 * drum * (1.0 if s % 4 == 0 else 0.8), None))
            if riq > 0 and s % 2 == 1:
                ev.append((hum(t0), "riq", None, 0.3 + 0.6 * riq * (1.0 if s % 4 == 3 else 0.7), None))
            if st.get("bass", 0.0) > 0 and BASS_ON[s]:
                n = midi(sc, rt, BASS[s] + c, -1)
                ev.append((hum(t0, 0.003), "bass", n, 0.5 + 0.5 * st["bass"], step * 1.9))
                if st["bass"] >= 0.6:
                    ev.append((hum(t0, 0.003), "bass_bow", n + 12, 0.4 + 0.4 * st["bass"], step * 0.9))
            if st.get("fills", 0.0) > 0 and bar % 4 == 3 and s >= 12:
                for sub in range(2):
                    ev.append((t0 + sub * step * 0.5, "roll", None, 0.4 + 0.5 * st["fills"] * (s - 11) / 4.0, None))
            if st.get("fills", 0.0) > 0 and bar % 4 == 0 and s == 0:
                ev.append((t0, "crash", None, 0.5 * st["fills"], None))
                ev.append((t0, "timp", None, 0.7 * st["fills"], None))
            if st.get("stab", 0.0) > 0 and s in (8, 15) and bar % 2 == 1:
                d = (0 if s == 8 else 1) + c
                for inst, o in (("horn_stac", 0), ("trombone_stac", -1)):
                    ev.append((t0, inst, midi(sc, rt, d, o), 0.5 + 0.5 * st["stab"], step * 1.5))
                    ev.append((t0, inst, midi(sc, rt, d + 4, o), 0.4 + 0.4 * st["stab"], step * 1.5))
            if st.get("toms", 0.0) > 0:
                k = st["toms_pat"][s]
                if k:
                    acc = 1.0 if s % 4 == 0 else 0.8
                    ev.append((hum(t0, 0.004), "tom_hi" if k == 1 else "tom_lo", None, (0.4 + 0.6 * st["toms"]) * acc, None))
                    if k == 2 and s % 8 == 0:
                        ev.append((hum(t0, 0.004), "timp", None, 0.5 * st["toms"], None))
            if st.get("anvil", 0.0) > 0 and st["anvil_pat"][s]:
                ev.append((hum(t0, 0.004), "anvil", None, (0.4 + 0.6 * st["anvil"]) * (1.0 if s % 8 == 0 else 0.7), None))
            if st.get("clap", 0.0) > 0 and s in (4, 12):
                ev.append((hum(t0, 0.004), "clap", None, 0.4 + 0.6 * st["clap"], None))
            if st.get("arp", 0.0) > 0 and s % 2 == 0:
                ev.append((hum(t0, 0.004), "harp", midi(sc, rt, c + ARP[s // 2], 0), 0.3 + 0.6 * st["arp"], 0.9))
        if st.get("lyre", 0.0) > 0:
            for nt in mel:
                t = (bar * 16 + nt["step"]) * step + (swing * step if nt["step"] % 2 == 1 else 0.0)
                n = midi(sc, rt, nt["deg"], 1)
                ev.append((hum(t), "lyre" if n >= 55 else "lyre_low", n, 0.45 + 0.5 * st["lyre"], 1.1 + 0.4 * nt["len"]))
        if st.get("pipe", 0.0) > 0:
            inst = st.get("pipe_kind", "oboe")
            for k, nt in enumerate(mel):
                nxt = mel[k + 1]["step"] if k + 1 < len(mel) else 18
                dur = max(step, (nxt - nt["step"]) * step * 0.95)
                t = (bar * 16 + nt["step"]) * step + (swing * step if nt["step"] % 2 == 1 else 0.0)
                ev.append((hum(t), inst, midi(sc, rt, nt["deg"], 1), 0.35 + 0.55 * st["pipe"], dur))
        if st.get("horn", 0.0) > 0 and st.get("horn_lead"):
            for k, nt in enumerate(mel):
                nxt = mel[k + 1]["step"] if k + 1 < len(mel) else 18
                dur = max(step, (nxt - nt["step"]) * step * 0.95)
                ev.append((hum((bar * 16 + nt["step"]) * step), "horn", midi(sc, rt, nt["deg"], 0), 0.45 + 0.5 * st["horn"], dur))
        if st.get("strings", 0.0) > 0:
            swell = 0.4 + 0.6 * (bar % 4) / 3.0
            v = (0.25 + 0.6 * st["strings"]) * (0.55 + 0.45 * swell)
            for inst, d, o in (("cello_trem", c, 0), ("cello_trem", c + 4, -1), ("viola_trem", c + 4, 0), ("violin_trem", c, 1), ("violin_trem", c + 4, 1)):
                ev.append((bar * bar_s, inst, midi(sc, rt, d, o), v, bar_s))
        if st.get("pad", 0.0) > 0:
            for d, inst, o in ((c, "cellos", 0), (c + 2, "violins", 1), (c + 4, "violins", 1)):
                ev.append((bar * bar_s, inst, midi(sc, rt, d, o), 0.2 + 0.4 * st["pad"], bar_s + 0.5))
        if st.get("choir", 0.0) > 0:
            # (The arena's own choir: the cornu and the tuba in a slow chorale.)
            v = (0.35 + 0.5 * st["choir"]) * (0.6 + 0.4 * (bar % 4) / 3.0)
            for d, inst, o in ((c, "tuba", -1), (c, "trombone", 0), (c + 2, "trombone", 0), (c + 4, "horn", 0)):
                ev.append((bar * bar_s, inst, midi(sc, rt, d, o), v, bar_s + 0.3))
        if st.get("horn", 0.0) > 0 and not st.get("horn_lead") and not st.get("line") and (bar % 2 == 1 or once):
            inst = st.get("horn_kind", "horn")
            for k in (0, 8):
                d2 = [4, 2, 0, 4][(bar + k // 8) % 4] + c
                ev.append((hum((bar * 16 + k) * step), inst, midi(sc, rt, d2, 0 if inst == "horn" else 1), 0.45 + 0.5 * st["horn"], step * 6))
                if inst == "trumpet":
                    ev.append((hum((bar * 16 + k) * step), "horn", midi(sc, rt, d2, 0), 0.4 + 0.4 * st["horn"], step * 6))
        if st.get("toll", 0.0) > 0:
            ev.append((bar * bar_s, "bell", midi(sc, rt, c, 0), 0.5 + 0.4 * st["toll"], min(4.0, bar_s)))
            ev.append((bar * bar_s, "gong", None, 0.4 * st["toll"], None))
    for nt in st.get("line", []):
        ev.append((nt[0] * step, "horn", midi(sc, rt, nt[1], 0), 0.45 + 0.5 * st.get("horn", 0.5), nt[2] * step))
    return ev


def reverb_ir(size=1.9, seed=3):
    """A stone arena: a decaying stereo tail, darker as it fades."""
    r = np.random.default_rng(seed)
    n = int(size * SR)
    t = np.arange(n) / SR
    out = []
    for ch in range(2):
        x = r.normal(0, 1, n) * np.exp(-t * (6.9 / size))
        x[:int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        b, a = signal.butter(1, 4500 / (SR / 2), "low")
        x = signal.lfilter(b, a, x)
        out.append(x / np.sqrt(np.sum(x * x)))
    return np.stack(out, axis=1)


# How long each drum is let ring, in 16ths: the frame drum, the darbuka and the toms rang half a
# second and more, and at a fight's tempo every hit ran on under the next five.
RING = {"dum": 2.5, "doum": 2.5, "tek": 1.5, "riq": 1.5, "roll": 1.0, "tom_hi": 2.0, "tom_lo": 2.5, "timp": 4.0, "clap": 1.5}


def render(name, B, seed=1):
    st = STATES[name]
    rng = random.Random(seed + djb2(name))
    step = 60.0 / st["bpm"] / 4.0
    n = int(st["bars"] * 16 * step * SR)
    once = st.get("once", False)
    tail = int(4.0 * SR) if once else 0
    buf = np.zeros((n + tail, 2))
    for t0, inst, note, vel, dur in perform(name, st, B, rng):
        if dur is None and inst in RING:
            dur = RING[inst] * step   # (a drum's ring cut to the beat: else at 140 bpm it ran on over six of them)
        x = B[inst].render(note, min(1.0, vel), dur, rng)
        t0 -= B[inst].lead      # (the note begun as far ahead as it takes to speak)
        i0 = int(round(max(0.0, t0) * SR)) if once else int(round(t0 * SR)) % n
        if once:
            m = min(len(x), len(buf) - i0)
            if m > 0:
                buf[i0:i0 + m] += x[:m]
            continue
        # What rings past the loop's end goes round onto its start: a seamless loop.
        pos = 0
        while pos < len(x):
            j = (i0 + pos) % n
            m = min(len(x) - pos, n - j)
            buf[j:j + m] += x[pos:pos + m]
            pos += m
    ir = reverb_ir(2.2 if st["bpm"] < 100 else 1.8)
    wet = np.stack([signal.fftconvolve(buf[:, c], ir[:, c]) for c in (0, 1)], axis=1)
    if once:
        wet = wet[:len(buf)]
    else:
        w = np.zeros_like(buf)
        w += wet[:n]
        k = len(wet) - n
        while k > 0:
            m = min(k, n)
            w[:m] += wet[len(wet) - k:len(wet) - k + m]
            k -= m
        wet = w
    mix = buf + wet * (0.26 if st["bpm"] < 100 else 0.2)
    b, a = signal.butter(2, 32 / (SR / 2), "high")
    if once:
        mix = signal.lfilter(b, a, mix, axis=0)
    else:
        # (Filtered round the loop: three rounds in, the middle one out, so its end meets its
        # start with no step, no click.)
        mix = signal.filtfilt(b, a, np.concatenate([mix, mix, mix]), axis=0)[n:2 * n]
    rms = np.sqrt(np.mean(mix[:n] ** 2))
    mix *= LOUD[name] / max(1e-9, rms)
    mix = np.tanh(mix * 1.1) / np.tanh(1.1)          # a gentle limiter for the odd peak
    mix *= LOUD[name] / max(1e-9, np.sqrt(np.mean(mix[:n] ** 2)))
    if once:
        fade = int(1.5 * SR)
        mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return mix.astype(np.float32)


def write(x, path, quality=5):
    with tempfile.NamedTemporaryFile(suffix=".f32", delete=False) as f:
        f.write(x.astype(np.float32).tobytes())
        raw = f.name
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", raw, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.unlink(raw)


def main():
    global LIB
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", default=os.environ.get("SAMPLES", LIB))
    ap.add_argument("--out", default=os.path.join(ROOT, "art", "audio", "music"))
    ap.add_argument("--only", default="")
    ap.add_argument("--demo", default="", help="also mp3s of two rounds of each loop, to listen to")
    a = ap.parse_args()
    LIB = a.samples
    os.makedirs(a.out, exist_ok=True)
    B = band()
    for name in STATES:
        if a.only and name not in a.only.split(","):
            continue
        x = render(name, B)
        write(x, os.path.join(a.out, name + ".ogg"))
        if a.demo:
            os.makedirs(a.demo, exist_ok=True)
            y = x if STATES[name].get("once") else np.concatenate([x, x])
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "libmp3lame", "-b:a", "192k", os.path.join(a.demo, name + ".mp3")], input=y.tobytes(), check=True)
        print(name, "%.1f s" % (len(x) / SR), "peak %.2f" % float(np.abs(x).max()), flush=True)


if __name__ == "__main__":
    main()
