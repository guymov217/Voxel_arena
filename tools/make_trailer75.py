#!/usr/bin/env python3
"""WRECKSMITH - the 75-second trailer, made from the game itself, shot by shot to its production
script (tools/TRAILER.md): 31 shots at the script's own times (the armourer's bench left out),
its eight lines of text, the logo and WISHLIST NOW ON STEAM.

Every shot is staged in the game and recorded by its movie maker (tests/trailer75.gd): the men
are put where they stand and driven as a player's mouse and keys drive them; every blow, cut,
fall and grab is the game's own. Several shots are one scene filmed again by another camera
(the scene goes the same way every time). The editor (tools/trailer_edit.py) cuts each shot on
its moment (the blow it is cut on, read from the scene's tags), eases into and out of slow motion
where the script asks for it, blends the 120 game frames a second into the film's (a film
camera's motion blur), grades the picture a little, lays the lines of text over it, and mixes the
game's own sound under the game's own music (art/audio/music), brought to -14 LUFS.

    python tools/make_trailer75.py             -> docs/store/trailer75.mp4 (1920x1080, 30 fps)
                                                  docs/store/trailer75_clean.mp4 (no text)
                                                  docs/store/trailer75_cut.json (the cut list)
    TRAILER_FPS=60                             -> the same at 60 frames a second
    python tools/make_trailer75.py --preview   -> a rough cut at 640x360 from 30 fps recordings
                                                  (no graphics card: a computer without one
                                                  renders in software, slowly)
    python tools/make_trailer75.py --fake      -> the whole cut from made-up footage (a check of
                                                  the timing, the text and the sound)
    --shots 1,2,24b                            -> record only those (again)

Needs Godot 4.7 with a display, ffmpeg (with ffprobe), numpy and Pillow. Work files go to
<trailer_work>/t75 (or t75_preview); shots already recorded are kept until the game changes."""
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import trailer_edit as ed  # noqa: E402

PREVIEW = "--preview" in sys.argv
FAKE = "--fake" in sys.argv
OUT = os.path.join(ROOT, "docs", "store")
TMP = os.environ.get("TRAILER_TMP") or os.path.join(os.path.dirname(ROOT), "trailer_work")
WORK = os.path.join(TMP, ("t75_fake" if FAKE else "t75") + ("_preview" if PREVIEW else ""))
PROJ = os.path.join(TMP, "project")
FPS = int(os.environ.get("TRAILER_FPS", "30"))
W, H = (640, 360) if PREVIEW else (1920, 1080)
REC_FPS = 30 if PREVIEW else 120
FONT = os.path.join(HERE, "fonts", "InterDisplay-Black.otf")
LOGO = os.path.join(OUT, "capsules", "logo.png")
MUSIC = os.path.join(ROOT, "art", "audio", "music")
LENGTH = 75.0

# ---------- the script ----------

# Each shot: [number, start, end, what it shows, the recording, where it is cut]. Where it is
# cut: ("key", s): the shot's moment (its KEY tag: the blow it cuts on) s film seconds into the
# shot (negative: that long before it starts); ("mark", what, s): the same for a MARK; ("t", s):
# from s seconds into the scene. slow: [(seconds from the moment, speed), ...] the speed of the
# picture eased between those (1 before the first and after the last); cuts: a shot made of
# several short pieces [(recording, scene seconds, length)].
SHOTS = [
    [1, 0.0, 1.5, "ECU low side, still: the axe comes down on the man's arm; cut on the blow", "1", ("key", 1.45), None],
    [2, 1.5, 3.0, "CU three-quarters low: the cut arm, the axe on into his thigh and stuck there; a short slow motion", "2", ("key", 0.05), [(0.0, 0.45), (0.45, 0.45), (0.75, 1.0)]],
    [3, 3.0, 5.0, "WS a little high, going with them: the champion presses on, the man gives ground", "3", ("key", -0.9), None],
    [4, 5.0, 7.0, "WS high over the arena, pushing in: the two of them engaged in the middle", "4", ("key", 0.6), None],
    [5, 7.0, 10.0, "FS low, going along: the champion comes on, the man turns to face him", "5", ("t", 0.2), None],
    [6, 10.0, 13.0, "Medium-wide, side on: they trade blows, sword on shield", "6", ("key", 0.5), None],
    [7, 13.0, 15.0, "MS low before the champion: the warhammer down on the man; a ramp on the blow", "7", ("key", 1.15), [(0.02, 0.35), (0.4, 0.35), (0.65, 1.0)]],
    [8, 15.0, 17.0, "CU side: the mace into his shin", "8", ("key", 1.0), None],
    [9, 17.0, 19.0, "CU a little high, side on: the second chop into the same wound takes his arm off; slow at the cut", "9", ("key", 0.85), [(-0.02, 0.35), (0.45, 0.35), (0.7, 1.0)]],
    [10, 19.0, 21.0, "FS side on, going with him: the warhammer into his legs, and he goes down", "10", ("key", 0.6), None],
    [11, 21.0, 23.0, "MS three-quarters, a little high: the champion takes hold of him and throws him", "11", ("key", 0.55), None],
    [12, 23.0, 25.0, "Medium-close, side on: the kick in his chest", "12", ("key", 0.9), None],
    [13, 25.0, 27.0, "CU three-quarters from behind him: the axe stuck in him, wrenched out", "13", ("mark", "free", 1.55), None],
    [14, 27.0, 29.0, "Medium-wide three-quarters, pushing in: the forge", "14f", ("t", 0.0), None],
    [15, 29.0, 32.0, "CU a little high: the axe built block by block (three cuts)", None, None, None],
    [16, 32.0, 34.0, "CU side on: the axe done, the forge's camera round it", "16", ("key", 0.15), None],
    [17, 34.0, 39.0, "The same axe in the arena: close on its head, then into a man", "17", ("key", 2.2), None],
    [20, 39.0, 45.0, "FS low three-quarters: a brute's hammer on his armour, twice", "20", ("key", 1.3), None],
    [21, 45.0, 49.0, "EWS very low, rising: the cyclops comes at the champion", "21", ("t", 0.0), None],
    [22, 49.0, 52.0, "FS low, side on: the cyclops's blow, the champion thrown", "22", ("key", 1.3), None],
    [23, 52.0, 55.0, "Medium-wide from behind the champion: up again, his cuts into the giant's legs", "23", ("mark", "cut giant", 0.8), None],
    [24, 55.0, 58.0, "Low three-quarters, two quick cuts: the big lion's charge bowls the champion over; the minotaur's axe on him", None, None, None],
    [25, 58.0, 60.0, "WS a little high: the champion crossing the yard", "25", ("t", 0.6), None],
    [26, 60.0, 62.0, "MS over the shoulder: at the smith's, his stall opened", "26", ("key", 1.4), None],
    [27, 62.0, 64.0, "MS three-quarters: the physician fits a hook to the stump", "27", ("key", 1.0), None],
    [28, 64.0, 66.0, "FS a little low: training on the sparring partner", "28", ("t", 0.35), None],
    [29, 66.0, 68.0, "WS low three-quarters: the melee, the champion in it", "29", ("t", 0.4), None],
    [30, 68.0, 70.0, "CU side on: the axe down into his head, the blow he dies of; a ramp into slow motion", "30", ("key", 0.75), [(-0.05, 0.25), (0.5, 0.25), (0.8, 1.0)]],
    # (The kill cam slows right down round the blow: it comes 5.1 s into its replay.)
    [31, 70.0, 72.0, "The game's own kill cam of it", "31", ("mark", "killcam", -3.8), None],
    [32, 72.0, 73.0, "A little high, three-quarters: the champion over the man", "32", ("key", -1.5), None],
    [33, 73.0, 75.0, "Black, the logo, the lines, WISHLIST NOW ON STEAM", None, None, None],
]
# The pieces of 15 (the haft, the head, the edge going on) and of 24 (the big lion's charge
# bowling the champion over, the minotaur's axe on him): [recording, how it is cut, film seconds].
CUTS = {
    15: [["15", ("t", 1.0), 1.0], ["15", ("t", 3.2), 1.0], ["15", ("t", 5.1), 1.0]],
    24: [["24b", ("key", 0.55), 1.5], ["24c", ("key", 0.5), 1.5]],
}
# The lines (PART 3 of the script), at its times.
TEXT = [
    (5.0, 8.0, "PHYSICS-DRIVEN COMBAT"),
    (13.0, 17.0, "EVERY HIT MATTERS"),
    (17.0, 23.0, "BRUTAL. PHYSICAL. UNPREDICTABLE."),
    (27.0, 34.0, "BUILD YOUR OWN WEAPONS"),
    (38.0, 45.0, "CUSTOMIZE YOUR GLADIATOR"),
    (45.0, 58.0, "FACE THE UNTHINKABLE"),
    (58.0, 66.0, "FIGHT. HEAL. PREPARE."),
]
END_LINES = ["BUILD YOUR WEAPON.", "ENTER THE ARENA.", "SURVIVE THE FIGHT."]
END_CALL = "WISHLIST NOW ON STEAM"
# The music (PART 4): the game's own pieces, one to each stretch of the curve, the strongest (or
# the quietest) stretch of each.
MUSIC_PLAN = [
    (0.0, 5.0, "boss2", "hard"),      # impact and tension
    (5.0, 13.0, "fight", "mid"),      # the rhythm
    (13.0, 27.0, "fight3", "hard"),   # the combat building
    (27.0, 45.0, "forge", "mid"),     # a change of rhythm: making and fitting out
    (45.0, 58.0, "boss", "hard"),     # the giants
    (58.0, 66.0, "yard", "soft"),     # the yard, quieter
    (66.0, 73.0, "boss2", "hard"),    # the finale
    (73.0, 75.0, "victory", "start"),  # the logo's sting
]
# What each recording must have caught for its shot (KEY: its moment; the rest, MARKs): a take
# without them is filmed again with the next take's dice (SHOT_SEED). The shots of one scene seen by
# different cameras (GROUPS) are all filmed with the same take, so a cut between them is one moment.
NEEDS = {
    "1": ["KEY"], "2": ["KEY"], "3": ["KEY"],
    "4": ["KEY"], "5": ["KEY"], "6": ["KEY"],
    "7": ["KEY", "down foe"], "8": ["KEY"], "9": ["severed foe"], "10": ["KEY", "down foe"],
    "11": ["grab", "down foe"], "12": ["KEY"], "13": ["lodged", "free"],
    "14f": ["KEY"], "15": ["KEY"], "16": ["KEY"], "17": ["KEY"],
    "20": ["KEY"],
    "21": ["KEY"], "22": ["KEY"], "23": ["cut giant"], "24b": ["KEY"], "24c": ["KEY"],
    "26": ["KEY"], "27": ["KEY"], "28": ["KEY"], "29": ["KEY"],
    "30": ["KEY"], "31": ["killcam"], "32": ["KEY"],
}
GROUPS = [["1", "2", "3"], ["4", "5", "6"], ["14f", "15", "16"], ["21", "22"], ["30", "31", "32"]]
TAKES = [11, 12, 13, 14, 15]

DROP = (70.05, 71.25)                 # the music drops away under the kill cam, then hits hard on its blow
BOOMS = [1.45, 71.3, 73.0]            # a deep hit under these moments (the hook's blow, the kill cam's, the logo)

# ---------- running Godot ----------

def godot():
    """The Godot to run: GODOT, else Godot 4.7 where it is usually unzipped, else on the PATH."""
    g = os.environ.get("GODOT", "")
    if g and os.path.isfile(g):
        con = g[:-4] + "_console.exe" if g.lower().endswith(".exe") and not g.lower().endswith("_console.exe") else ""
        return con if con and os.path.isfile(con) else g
    import glob
    home = os.path.expanduser("~")
    places = [ROOT, os.path.dirname(ROOT), r"D:\godot", r"C:\godot", os.path.join(home, "Downloads"), os.path.join(home, "Desktop")]
    for kind in ("_console", ""):
        for d in places:
            for pat in ("Godot_v4.7*win64%s.exe" % kind, os.path.join("Godot*", "Godot_v4.7*win64%s.exe" % kind)):
                hits = sorted(glob.glob(os.path.join(d, pat)))
                if hits:
                    return hits[0]
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    if os.path.exists("/opt/godot/Godot_v4.7.2-stable_linux.x86_64"):
        return "/opt/godot/Godot_v4.7.2-stable_linux.x86_64"
    sys.exit("Godot not found: set GODOT to the Godot 4.7 executable (the *_console.exe on Windows), or put godot on the PATH")


def ffmpeg_on_path():
    """FFMPEG may name the ffmpeg.exe, its bin folder or the folder it was unzipped to."""
    f = os.environ.get("FFMPEG", "")
    if not f:
        return
    cands = [os.path.dirname(f) if os.path.isfile(f) else f, os.path.join(f, "bin")]
    if os.path.isdir(f):
        cands += [os.path.join(f, d, "bin") for d in os.listdir(f) if d.lower().startswith("ffmpeg")]
    for c in cands:
        if os.path.isfile(os.path.join(c, "ffmpeg.exe")) or os.path.isfile(os.path.join(c, "ffmpeg")):
            os.environ["PATH"] = c + os.pathsep + os.environ.get("PATH", "")
            return


def run(args, env=None, log=None):
    """Runs Godot; returns its output lines with the tags the probe also writes to TAG_LOG (the
    window build of Godot on Windows prints nothing to a pipe)."""
    e = dict(os.environ)
    # Filmed in the game's own look at its full quality, whatever this PC's Options say.
    e.setdefault("FORCE_LOOK", "human")
    e.setdefault("FORCE_QUALITY", "high")
    e.update(env or {})
    tags = os.path.join(WORK, "tags.txt")
    if os.path.exists(tags):
        os.remove(tags)
    e["TAG_LOG"] = tags
    p = subprocess.run(args, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    lines = [ln.strip() for ln in (p.stdout or "").splitlines()]
    if os.path.exists(tags):
        with open(tags) as f:
            lines += [ln.strip() for ln in f if ln.strip()]
    if log:
        with open(log, "w") as f:
            f.write("\n".join(lines))
    return lines


def stamp():
    """What the shots are filmed from: the game's scripts, data, shaders and scenes, the probe and
    these tools, by their contents (line ends aside)."""
    h = hashlib.sha1()
    exts = (".gd", ".json", ".gdshader", ".tscn", ".tres", ".py", ".cfg")
    for top in ("scripts", "data", "shaders", "scenes", "tests/trailer75.gd", "tests/capsuleart.gd", "tools/make_trailer75.py", "project.godot"):
        base = os.path.join(ROOT, top)
        files = [base] if os.path.isfile(base) else [os.path.join(d, f) for d, _, fs in os.walk(base) for f in fs if f.endswith(exts)]
        for f in sorted(files):
            h.update(os.path.relpath(f, ROOT).replace("\\", "/").encode())
            with open(f, "rb") as fh:
                h.update(fh.read().replace(b"\r\n", b"\n"))
    return h.hexdigest()


def fresh():
    """Shots kept from a run made from another version of the game are thrown away (every shot is
    filmed from the game as it is now); within one version a stopped run carries on."""
    os.makedirs(WORK, exist_ok=True)
    sp = os.path.join(WORK, "stamp.txt")
    now = stamp()
    was = open(sp).read().strip() if os.path.exists(sp) else ""
    if was != now:
        for f in os.listdir(WORK):
            if f.endswith((".avi", ".json", ".rec")):
                os.remove(os.path.join(WORK, f))
        with open(sp, "w") as fh:
            fh.write(now)


def fresh_project(g):
    """A copy of the project to film in: its window the film's size, one worker thread (the same
    frames every run), and a user folder of its own (the player's saves are never touched)."""
    if os.path.isdir(PROJ):
        shutil.rmtree(PROJ)
    shutil.copytree(ROOT, PROJ, ignore=shutil.ignore_patterns(".git", "store", "trailer_work", ".godot", "*.mp4"))
    with open(os.path.join(PROJ, "override.cfg"), "w") as f:
        f.write("[display]\nwindow/size/viewport_width=%d\nwindow/size/viewport_height=%d\n" % (1600, 900)
                + "[threading]\nworker_pool/max_threads=1\n"
                + "[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"wrecksmith_trailer\"\n")
    run([g, "--headless", "--path", PROJ, "--import"])


def tags_of(lines):
    """The scene's tags: {rec0, end, key (scene seconds), marks {what: seconds}, hits [...]}."""
    out = {"rec0": None, "end": None, "key": None, "marks": {}, "hits": []}
    for ln in lines:
        p = ln.split()
        if not p:
            continue
        if p[0] == "REC_START":
            out["rec0"] = int(p[1])
        elif p[0] == "REC_END":
            out["end"] = int(p[1])
        elif p[0] == "KEY" and len(p) >= 3 and out["key"] is None:
            out["key"] = float(p[2])
        elif p[0] == "MARK" and len(p) >= 4:
            out["marks"].setdefault(" ".join(p[3:]), float(p[2]))
        elif p[0] == "HIT" and len(p) >= 10:
            out["hits"].append({"t": float(p[2]), "J": int(p[3]), "part": p[4], "off": int(p[5]), "kind": p[6], "by_champion": p[7] == "1", "plates": int(p[8]), "who": p[9]})
    return out


def missing(shot, tg):
    """What the take of `shot` should have caught and did not."""
    out = []
    for n in NEEDS.get(shot, []):
        if n == "KEY":
            if tg.get("key") is None:
                out.append(n)
        elif n not in tg.get("marks", {}):
            out.append(n)
    if any(k.startswith("missed") for k in tg.get("marks", {})):
        out.append("a click that missed")
    return out


def record(g, shot, take=11):
    """Shot `shot` of tests/trailer75.gd with the dice of `take`: <work>/<shot>.avi and
    <shot>.json, recorded once. Returns what it should have caught and did not."""
    avi = os.path.join(WORK, shot + ".avi")
    meta = os.path.join(WORK, shot + ".json")
    if os.path.exists(avi) and os.path.getsize(avi) and os.path.exists(meta):
        tg = json.load(open(meta))
        if tg.get("take", 11) == take:
            print("  %s: kept" % shot)
            return missing(shot, tg)
    env = {"SHOT": shot, "SHOT_SEED": str(take)}
    if PREVIEW:
        env.update({"TRAILER_SSAA": "1", "TRAILER_AA": "fxaa"})
    lines = run([g, "--write-movie", avi, "--fixed-fps", str(REC_FPS), "--resolution", "%dx%d" % (W, H), "--path", PROJ, "--", "--probe", "trailer75"],
                env, os.path.join(WORK, shot + ".rec"))
    tg = tags_of(lines)
    tg["take"] = take
    if tg["rec0"] is None or tg["end"] is None or not os.path.exists(avi):
        print("  %s: the recording failed (see %s)" % (shot, os.path.join(WORK, shot + ".rec")))
        if os.path.exists(avi):
            os.remove(avi)
        return ["the recording"]
    with open(meta, "w") as f:
        json.dump(tg, f, indent=1)
    lack = missing(shot, tg)
    print("  %s: recorded, take %d%s%s" % (shot, take, "" if tg["key"] is None else " (its moment %.2f s in)" % tg["key"],
                                           "; it lacks: " + ", ".join(lack) if lack else ""))
    return lack


def record_all(g, wanted):
    """Every recording: a scene's shots with one take, the first take whose first shot caught all
    it should; the others of the scene with the same take. Returns {shot: what it lacks}."""
    lacks = {}
    done = set()
    for r in wanted:
        if r in done:
            continue
        group = next((gr for gr in GROUPS if r in gr), [r])
        group = [x for x in group if x in wanted]
        chosen = TAKES[0]
        for take in TAKES:
            lack = record(g, group[0], take)
            chosen = take
            if not lack:
                break
            print("  %s: filmed again with another take" % group[0])
        lacks[group[0]] = record(g, group[0], chosen) if lack else []
        for x in group[1:]:
            lacks[x] = record(g, x, chosen)
        done.update(group)
    return {k: v for k, v in lacks.items() if v}


def recordings():
    """Every recording the cut uses."""
    out = []
    for s in SHOTS:
        if s[4] and s[4] not in out:
            out.append(s[4])
    for pieces in CUTS.values():
        for p in pieces:
            if p[0] not in out:
                out.append(p[0])
    return out

# ---------- made-up footage (--fake) ----------

def fake(shot):
    """A test pattern with a tone for a shot, its moment two seconds in (a check of the edit)."""
    avi = os.path.join(WORK, shot + ".avi")
    meta = os.path.join(WORK, shot + ".json")
    if os.path.exists(avi) and os.path.exists(meta):
        return
    secs = 14.0 if shot == "31" else 9.0
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=%dx%d:rate=%d:duration=%.2f" % (W, H, REC_FPS, secs),
                           "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=48000:duration=%.2f" % (200 + 13 * len(shot) * 7, secs),
                           "-vf", "drawtext=fontfile='%s':text='SHOT %s':fontsize=%d:fontcolor=white:x=40:y=40" % (FONT.replace("\\", "/").replace(":", "\\:"), shot, H // 8),
                           "-c:v", "mjpeg", "-q:v", "4", "-c:a", "pcm_s16le", "-shortest", avi])
    tg = {"rec0": REC_FPS // 2, "end": int((secs - 0.6) * REC_FPS), "key": 2.0,
          "marks": {"free": 2.6, "killcam": 4.0, "down giant": 2.2}, "hits": []}
    with open(meta, "w") as f:
        json.dump(tg, f)

# ---------- the cut ----------

def anchor_time(meta, how):
    """Scene seconds of the moment `how` is cut on, and how far into the piece it falls."""
    kind = how[0]
    if kind == "t":
        return float(how[1]), 0.0
    if kind == "key":
        k = meta.get("key")
        if k is None:
            raise ValueError("no KEY")
        return float(k), float(how[1])
    k = meta.get("marks", {}).get(how[1])
    if k is None:
        raise ValueError("no MARK %s" % how[1])
    return float(k), float(how[2])


def piece(src, meta, how, secs, slow=None):
    """A run of a recording `secs` film seconds long, cut as `how` says (and slowed as `slow`
    says, round its moment): an ed.Segment, its frames exactly the film's."""
    t0 = meta["rec0"] / src.fps            # the scene's start in the recording
    at, into = anchor_time(meta, how)
    moment = t0 + at
    if slow:
        keys = [(moment + slow[0][0] - 0.12, 1.0)] + [(moment + d, s) for d, s in slow]
        if slow[-1][1] != 1.0:
            keys.append((moment + slow[-1][0] + 0.12, 1.0))
        sp = ed.Speed(keys)
    else:
        sp = ed.Speed([])
    if how[0] == "t":
        t_in = moment
    elif into >= 0.0:
        t_in = ed.lead_for(src.fps, FPS, moment, sp, into, lo=0.0, hi=into * 4.0 + 1.0) if into > 0.0 else moment
    else:
        t_in = moment + (-into) * 1.0
    t_in = max(1.0 / src.fps, t_in)
    seg = ed.Segment(src, t_in, src.dur, sp)
    seg.prepare(FPS)
    n = int(round(secs * FPS))
    short = n - len(seg.plan)
    if short > 0:
        last = seg.plan[-1] if seg.plan else (t_in * src.fps, t_in * src.fps + 1)
        seg.plan += [last] * short
    seg.plan = seg.plan[:n]
    seg.short = max(0, short)
    seg.t_in = t_in
    seg.moment = moment
    return seg


def cut(srcs, metas):
    """The film: its segments in order, and the cut list."""
    segs = []
    sheet = []
    for s in SHOTS:
        num, a, b, what, rec, how, slow = s
        secs = b - a
        if num == 33:
            seg = ed.Segment(None, dur=secs)
            seg.prepare(FPS)
            segs.append(seg)
            sheet.append({"shot": num, "start": a, "end": b, "what": what, "source": "black, the logo and the lines"})
            continue
        pieces = CUTS.get(num, [[rec, how, secs]])
        total = int(round(secs * FPS))
        made = 0
        for k, (prec, phow, psecs) in enumerate(pieces):
            n = total - made if k == len(pieces) - 1 else int(round(psecs * FPS))
            if prec not in srcs:
                seg = ed.Segment(None, dur=n / FPS)
                seg.prepare(FPS)
                sheet.append({"shot": num, "start": a + made / FPS, "end": a + (made + n) / FPS, "what": what, "source": "MISSING: recording %s" % prec})
            else:
                try:
                    seg = piece(srcs[prec], metas[prec], phow, n / FPS, slow if len(pieces) == 1 else None)
                    sheet.append({"shot": num, "start": round(a + made / FPS, 3), "end": round(a + (made + n) / FPS, 3), "what": what, "source": prec + ".avi",
                                  "in": round(seg.t_in, 3), "moment": round(seg.moment, 3), "slow": slow if len(pieces) == 1 else None,
                                  "short_frames": seg.short})
                except ValueError as e:
                    seg = ed.Segment(None, dur=n / FPS)
                    seg.prepare(FPS)
                    sheet.append({"shot": num, "start": a + made / FPS, "end": a + (made + n) / FPS, "what": what, "source": "MISSING: %s in %s" % (e, prec)})
            segs.append(seg)
            made += n
    return segs, sheet

# ---------- the text ----------

def _font(size):
    from PIL import ImageFont
    return ImageFont.truetype(FONT, size)


def card(path, lines, size, anchor="lower-left", sub=None):
    """A line of text over the picture as a picture of its own (white, bold, a dark edge for any
    ground), where it keeps clear of the middle of the action."""
    from PIL import Image, ImageDraw, ImageFilter
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    f = _font(size)
    track = size * 0.06
    widths = []
    for ln in lines:
        widths.append(sum(dr.textlength(ch, font=f) for ch in ln) + track * (len(ln) - 1))
    lh = int(size * 1.08)
    block_h = lh * len(lines)
    if anchor == "lower-left":
        x0, y0 = int(W * 0.06), int(H * 0.86) - block_h
    else:
        x0, y0 = None, int(H * 0.5 - block_h * 0.5)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(shadow)
    for i, ln in enumerate(lines):
        x = x0 if x0 is not None else int((W - widths[i]) / 2)
        y = y0 + i * lh
        cx = x
        for ch in ln:
            ds.text((cx + size * 0.04, y + size * 0.05), ch, font=f, fill=(0, 0, 0, 200))
            dr.text((cx, y), ch, font=f, fill=(255, 255, 255, 255))
            cx += dr.textlength(ch, font=f) + track
    if anchor == "lower-left":
        # A short bar of the game's red under the line.
        dr.rectangle([x0, y0 + block_h + int(size * 0.18), x0 + int(size * 2.2), y0 + block_h + int(size * 0.18) + max(2, size // 9)], fill=(178, 34, 28, 255))
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, size // 14)))
    out = Image.alpha_composite(shadow, im)
    out.save(path)


def end_cards(dir_):
    """The end: the logo with the three lines under it, then the logo with WISHLIST NOW ON STEAM;
    and the logo alone (the version without text)."""
    from PIL import Image
    logo = Image.open(LOGO).convert("RGBA") if os.path.exists(LOGO) else None
    paths = []
    for name, lines in (("end_a", END_LINES), ("end_b", [END_CALL]), ("end_logo", [])):
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        if logo is not None:
            lw = int(W * 0.46)
            lg = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
            im.alpha_composite(lg, ((W - lw) // 2, int(H * (0.3 if lines else 0.42)) - lg.height // 2))
        if lines:
            tp = os.path.join(dir_, name + "_t.png")
            card(tp, lines, int(H * (0.05 if len(lines) > 1 else 0.065)), anchor="centre")
            t = Image.open(tp)
            # (Under the logo, not over it.)
            shifted = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            shifted.alpha_composite(t, (0, int(H * 0.2)))
            im = Image.alpha_composite(im, shifted)
        p = os.path.join(dir_, name + ".png")
        im.save(p)
        paths.append(p)
    return paths


def overlay_graph(cards, ends, with_text):
    """The filter: the grade, then each card faded and slid in over its time; the end cards."""
    grade = "[0:v]eq=contrast=1.06:saturation=1.07:gamma=0.98,vignette=angle=PI/6[g]"
    parts = [grade]
    last = "g"
    idx = 1
    items = []
    if with_text:
        for (a, b, _), p in zip(TEXT, cards):
            items.append((a, b, p, True))
        items.append((73.0, 74.0, ends[0], False))
        items.append((74.0, 75.0, ends[1], False))
    else:
        items.append((73.0, 75.0, ends[2], False))
    inputs = []
    for a, b, p, slide in items:
        inputs.append(["-loop", "1", "-t", "%.2f" % LENGTH, "-i", p])
        fi = 0.18
        lbl = "c%d" % idx
        parts.append("[%d:v]format=rgba,fade=t=in:st=%.3f:d=%.2f:alpha=1,fade=t=out:st=%.3f:d=%.2f:alpha=1[%s]" % (idx, a, fi, b - fi, fi, lbl))
        xexpr = "if(lt(t,%.3f),%d*(1-(t-%.3f)/%.2f),0)" % (a + 0.25, -int(W * 0.02), a, 0.25) if slide else "0"
        parts.append("[%s][%s]overlay=x='%s':y=0:enable='between(t,%.3f,%.3f)'[v%d]" % (last, lbl, xexpr, a, b, idx))
        last = "v%d" % idx
        idx += 1
    parts.append("[%s]format=yuv420p[v]" % last)
    return ";".join(parts), inputs

# ---------- the sound ----------

def load_audio(path):
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", path, "-vn", "-ac", "2", "-ar", str(ed.AR), "-f", "f32le", "-"])
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def music_bed():
    """The game's own pieces laid along the curve: for each stretch, the strongest (or the
    quietest) run of its piece that long, cross-faded into the next; the drop under the kill cam."""
    n = int(LENGTH * ed.AR)
    bed = np.zeros((n, 2), np.float32)
    xf = int(0.35 * ed.AR)
    chosen = []
    for a, b, name, kind in MUSIC_PLAN:
        path = os.path.join(MUSIC, name + ".ogg")
        if not os.path.exists(path):
            continue
        x = load_audio(path)
        need = int((b - a) * ed.AR) + xf
        if len(x) < need:
            x = np.concatenate([x] * (need // max(1, len(x)) + 1))
        hop = int(0.25 * ed.AR)
        x2 = (x ** 2).mean(axis=1)
        m = len(x2) // hop
        rms = np.sqrt(x2[:m * hop].reshape(m, hop).mean(axis=1))
        win = need // hop
        if kind == "start" or len(rms) <= win:
            off = 0
        else:
            means = np.convolve(rms, np.ones(win) / win, mode="valid")
            if kind == "hard":
                i = int(np.argmax(means))
            elif kind == "soft":
                i = int(np.argmin(np.abs(means - np.percentile(means, 35))))
            else:
                i = int(np.argmin(np.abs(means - np.percentile(means, 65))))
            off = i * hop
        piece_ = x[off:off + need].copy()
        env = np.ones(len(piece_), np.float32)
        if a > 0:
            env[:xf] = np.sin(np.linspace(0, math.pi / 2, xf)) ** 1.0
        if b < LENGTH:
            env[-xf:] = np.cos(np.linspace(0, math.pi / 2, xf)) ** 1.0
        start = int(a * ed.AR) - (xf // 2 if a > 0 else 0)
        seg = piece_ * env[:, None]
        end = min(n, start + len(seg))
        bed[start:end] += seg[:end - start]
        chosen.append({"from": a, "to": b, "piece": name + ".ogg", "at": round(off / ed.AR, 2)})
    # The drop: the music falls away under the kill cam's first moment, then comes back hard.
    d0, d1 = int(DROP[0] * ed.AR), int(DROP[1] * ed.AR)
    ramp = int(0.08 * ed.AR)
    g = np.ones(n, np.float32)
    g[d0:d1] = 0.12
    g[d0 - ramp:d0] = np.linspace(1.0, 0.12, ramp)
    bed *= g[:, None]
    return bed, chosen


def boom(at, n):
    """A deep hit with a sharp edge to it, at `at` seconds."""
    out = np.zeros((n, 2), np.float32)
    L = int(1.2 * ed.AR)
    t = np.arange(L) / ed.AR
    f = 38.0 + 52.0 * np.exp(-t / 0.09)
    ph = 2 * math.pi * np.cumsum(f) / ed.AR
    body = np.sin(ph) * np.exp(-t / 0.42) * np.minimum(1.0, t / 0.003)
    rng = np.random.default_rng(int(at * 1000))
    click = rng.standard_normal(L) * np.exp(-t / 0.012) * 0.35
    s = (body + click).astype(np.float32)
    i = int(at * ed.AR)
    m = min(L, n - i)
    if m > 0:
        out[i:i + m] += np.stack([s[:m], s[:m]], axis=1)
    return out


def mix(segs, path_wav):
    """The game's own sound of every shot (slowed with the picture), the music under it giving
    way to the loudest of it, the hits; to -14 LUFS."""
    game = ed.render_sound(segs, FPS)
    n = int(LENGTH * ed.AR)
    if len(game) < n:
        game = np.concatenate([game, np.zeros((n - len(game), 2), np.float32)])
    game = game[:n]
    bed, chosen = music_bed()
    env = ed.envelope(game)
    pk = max(1e-6, float(np.percentile(env, 99)))
    duck = 1.0 - 0.45 * np.clip(env / pk, 0.0, 1.0)
    hits = np.zeros((n, 2), np.float32)
    for at in BOOMS:
        hits += boom(at, n)
    out = game * 1.0 + bed * 0.6 * duck[:, None] + hits * 0.5
    raw = path_wav + ".raw.wav"
    ed.write_wav(raw, out / max(1.0, float(np.abs(out).max())))
    ed.loudnorm(raw, path_wav, tp=-1.5)   # (-1 asked of it came out at -0.9 after the AAC)
    os.remove(raw)
    return chosen

# ---------- the whole ----------

def main():
    ffmpeg_on_path()
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit("%s not found on the PATH: install it (ffmpeg comes with ffprobe)" % tool)
    os.makedirs(WORK, exist_ok=True)
    only = None
    if "--shots" in sys.argv:
        only = sys.argv[sys.argv.index("--shots") + 1].split(",")
    wanted = recordings()
    if FAKE:
        for r in wanted:
            fake(r)
    else:
        fresh()
        g = godot()
        print("Godot: %s" % g)
        fresh_project(g)
        if only:
            for r in only:
                for ext in (".avi", ".json"):
                    p = os.path.join(WORK, r + ext)
                    if os.path.exists(p):
                        os.remove(p)
        lacks = record_all(g, only or wanted)
        for r, lack in lacks.items():
            print("  WARNING: %s still lacks %s in every take: look at it before using the trailer" % (r, ", ".join(lack)))
        if only:
            return
    srcs, metas = {}, {}
    for r in wanted:
        avi, meta = os.path.join(WORK, r + ".avi"), os.path.join(WORK, r + ".json")
        if os.path.exists(avi) and os.path.exists(meta):
            srcs[r] = ed.Source(avi)
            metas[r] = json.load(open(meta))
    segs, sheet = cut(srcs, metas)
    frames = sum(s.frames for s in segs)
    print("the cut: %d frames, %.2f s" % (frames, frames / FPS))
    cards = []
    for k, (a, b, text) in enumerate(TEXT):
        p = os.path.join(WORK, "text_%d.png" % k)
        card(p, [text], int(H * 0.058))
        cards.append(p)
    ends = end_cards(WORK)
    out_dir = WORK if (PREVIEW or FAKE) else OUT
    os.makedirs(out_dir, exist_ok=True)
    base = "trailer75" + ("_preview" if PREVIEW else ("_fake" if FAKE else ""))
    # The picture once, then the two films from it (with the text and without).
    pic = os.path.join(WORK, "picture.mp4")
    enc = ed.encoder(pic, W, H, FPS, "[0:v]format=yuv420p[v]", crf=12 if not PREVIEW else 18)
    ed.render_picture(segs, W, H, FPS, lambda f: enc.stdin.write(f.tobytes()))
    enc.stdin.close()
    enc.wait()
    wav = os.path.join(WORK, "sound.wav")
    chosen = mix(segs, wav)
    for with_text, name in ((True, base + ".mp4"), (False, base + "_clean.mp4")):
        graph, inputs = overlay_graph(cards, ends, with_text)
        args = ["ffmpeg", "-y", "-v", "error", "-i", pic]
        for x in inputs:
            args += x
        args += ["-i", wav, "-filter_complex", graph, "-map", "[v]", "-map", "%d:a" % (len(inputs) + 1),
                 "-c:v", "libx264", "-preset", "slow", "-crf", "16" if not PREVIEW else "22", "-profile:v", "high", "-pix_fmt", "yuv420p",
                 "-r", str(FPS), "-c:a", "aac", "-b:a", "320k", "-ar", str(ed.AR), "-t", "%.3f" % LENGTH, "-movflags", "+faststart",
                 os.path.join(out_dir, name)]
        subprocess.check_call(args)
        print("  -> %s" % os.path.join(out_dir, name))
    with open(os.path.join(out_dir, base + "_cut.json"), "w") as f:
        json.dump({"fps": FPS, "size": [W, H], "shots": sheet, "text": TEXT, "music": chosen}, f, indent=1)
    missing = [s for s in sheet if str(s.get("source", "")).startswith("MISSING")]
    if missing:
        print("missing: %s" % ", ".join("%d (%s)" % (s["shot"], s["source"]) for s in missing))


if __name__ == "__main__":
    main()
