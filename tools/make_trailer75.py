#!/usr/bin/env python3
"""Record and edit the 75-second WRECKSMITH director's cut from the game.

See tools/TRAILER.md for the storyboard and quality gates. No failed take is
exported as black or a freeze frame. --preview is a 640x360 rough cut; --fake
checks the editing pipeline with test patterns, never gameplay. --audit runs
the choreography without rendering; --plan prints the editorial shot list.
"""
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
FONT = os.path.join(ROOT, "art", "fonts", "AlegreyaSans-Bold.ttf")
LOGO = os.path.join(OUT, "capsules", "logo.png")
MUSIC = os.path.join(ROOT, "art", "audio", "music")

# The director's cut is one editable source of truth, shared with validation and tests.
from trailer_plan import (SHOTS, CUTS, TEXT, END_LINES, END_CALL, MUSIC_PLAN,
                          NEEDS, GROUPS, TAKES, DROPS, BOOMS, RISES, VISIBLE,
                          END_START, LENGTH)
END_CALL = os.environ.get("TRAILER_CTA", END_CALL).strip()

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
    p = subprocess.run(args, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
                       timeout=int(os.environ.get("TRAILER_TIMEOUT", "1800")))
    lines = [ln.strip() for ln in (p.stdout or "").splitlines()]
    if os.path.exists(tags):
        with open(tags) as f:
            lines += [ln.strip() for ln in f if ln.strip()]
    if log:
        with open(log, "w") as f:
            f.write("\n".join(lines))
    # Godot 4.6's dummy renderer reports shutdown-only RID leaks in this project,
    # including on the unchanged branch. Preserve those in the log; they cannot
    # validate/invalidate choreography. Any script error or earlier engine error is fatal.
    completed = False
    errors = []
    for ln in lines:
        if ln.startswith("REC_END "):
            completed = True
        shutdown_leak = ("at exit" in ln or "RID allocations" in ln) and completed
        if "SCRIPT ERROR:" in ln or (ln.startswith("ERROR:") and not shutdown_leak):
            errors.append(ln)
    if p.returncode or errors:
        code = "0x%08X" % (p.returncode & 0xFFFFFFFF)
        hint = " (native access violation; the last logged asset is not necessarily the cause)" if code == "0xC0000005" else ""
        raise RuntimeError("Godot failed (%s, %s)%s: %s\n%s" % (p.returncode, code, hint, log or "import", "\n".join(errors[:8] or lines[-12:])))
    return lines


def stamp(engine=""):
    """What the shots are filmed from: the game's scripts, data, shaders and scenes, the probe and
    these tools, by their contents (line ends aside)."""
    h = hashlib.sha1()
    h.update((engine + str(REC_FPS) + os.environ.get("FORCE_LOOK", "human") + os.environ.get("FORCE_QUALITY", "high")
              + os.environ.get("TRAILER_RENDERER", "forward_plus") + os.environ.get("TRAILER_SSAA", "1.5")
              + os.environ.get("TRAILER_AA", "msaa4")).encode())
    exts = (".gd", ".json", ".gdshader", ".tscn", ".tres", ".py", ".cfg", ".so", ".dll", ".glb", ".ogg", ".png")
    for top in ("scripts", "data", "shaders", "scenes", "art", "native/bin", "tests/trailer75.gd", "tests/capsuleart.gd", "tools/make_trailer75.py", "tools/trailer_plan.py", "tools/trailer_edit.py", "project.godot"):
        base = os.path.join(ROOT, top)
        files = [base] if os.path.isfile(base) else [os.path.join(d, f) for d, _, fs in os.walk(base) for f in fs if f.endswith(exts)]
        for f in sorted(files):
            h.update(os.path.relpath(f, ROOT).replace("\\", "/").encode())
            with open(f, "rb") as fh:
                content = fh.read()
                h.update(content.replace(b"\r\n", b"\n") if f.endswith((".gd", ".json", ".gdshader", ".tscn", ".tres", ".py", ".cfg")) else content)
    return h.hexdigest()


def fresh(engine=""):
    """Shots kept from a run made from another version of the game are thrown away (every shot is
    filmed from the game as it is now); within one version a stopped run carries on."""
    os.makedirs(WORK, exist_ok=True)
    sp = os.path.join(WORK, "stamp.txt")
    now = stamp(engine)
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
                + "[editor]\nimport/use_multiple_threads=false\n"
                + "[threading]\nworker_pool/max_threads=1\n"
                + "[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"wrecksmith_trailer\"\n")
    # The importer has its own parallelism switch; worker_pool/max_threads alone
    # does not select serial resource import. Keep this scoped to the capture copy.
    import_log = os.path.join(WORK, "import.log")
    print("Importing capture project serially; full log: %s" % import_log, flush=True)
    run([g, "--headless", "--verbose", "--path", PROJ, "--import"], log=import_log)


def tags_of(lines):
    """The scene's tags: {rec0, end, key (scene seconds), marks {what: seconds}, hits [...]}."""
    out = {"rec0": None, "end": None, "key": None, "marks": {}, "hits": [], "seconds": None}
    for ln in lines:
        p = ln.split()
        if not p:
            continue
        if p[0] == "REC_START":
            out["rec0"] = int(p[1])
        elif p[0] == "REC_END":
            out["end"] = int(p[1])
        elif p[0] == "SCENE_END" and len(p) >= 2:
            out["seconds"] = float(p[1])
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
    renderer = os.environ.get("TRAILER_RENDERER", "forward_plus")
    if renderer not in ("forward_plus", "mobile", "gl_compatibility"):
        raise ValueError("Unknown TRAILER_RENDERER")
    lines = run([g, "--rendering-method", renderer, "--write-movie", avi, "--fixed-fps", str(REC_FPS), "--resolution", "%dx%d" % (W, H), "--path", PROJ, "--", "--probe", "trailer75"],
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
    """Accept a camera group only when ALL angles pass with the SAME seed."""
    lacks = {}
    done = set()
    for r in wanted:
        if r in done:
            continue
        group = next((gr for gr in GROUPS if r in gr), [r])
        # Rerecord the entire group even when --shots names only one angle.
        group = [x for x in group if x in recordings()]
        failures = {}
        for take in TAKES:
            failures = {x: record(g, x, take) for x in group}
            failures = {x: why for x, why in failures.items() if why}
            if not failures:
                try:
                    metas = {x: json.load(open(os.path.join(WORK, x + ".json"))) for x in group}
                    check_continuity(group, metas)
                    for x in group:
                        source = ed.Source(os.path.join(WORK, x + ".avi"))
                        validate_recording(x, source, metas[x])
                except ValueError as e:
                    failures[group[0]] = [str(e)]
            if not failures:
                break
            print("  %s: retrying group: %s" % (", ".join(group), failures), flush=True)
        lacks.update(failures)
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


def validate_plan():
    """Reject gaps, overlaps, duplicate ids, off-grid cuts and unknown source requirements."""
    if FPS not in (30, 60):
        raise ValueError("TRAILER_FPS must be 30 or 60")
    cursor, seen = 0.0, set()
    for num, a, b, _what, rec, how, _slow in SHOTS:
        if num in seen or abs(a - cursor) > 1e-6 or b <= a:
            raise ValueError("invalid timeline at shot %s" % num)
        if any(abs(v * FPS - round(v * FPS)) > 1e-6 for v in (a, b)):
            raise ValueError("shot %s is not on a film frame" % num)
        if num != 33 and num not in CUTS and (not rec or not how):
            raise ValueError("shot %s has no source" % num)
        if num in CUTS and abs(sum(p[2] for p in CUTS[num]) - (b - a)) > 1e-6:
            raise ValueError("shot %s: insert lengths do not add up" % num)
        seen.add(num)
        cursor = b
    if abs(cursor - LENGTH) > 1e-6 or SHOTS[-1][1] != END_START:
        raise ValueError("incorrect end card timing")
    if any(a < 0 or b > END_START or b <= a for a, b, _text in TEXT):
        raise ValueError("invalid text cue")


def check_continuity(group, metas):
    """Different cameras must have matching gameplay event times, not just matching seed labels."""
    first = metas[group[0]]
    for rec in group[1:]:
        other = metas[rec]
        if other.get("take") != first.get("take"):
            raise ValueError("mixed takes in %s" % group)
        for name in NEEDS.get(group[0], []):
            a = first.get("key") if name == "KEY" else first.get("marks", {}).get(name)
            b = other.get("key") if name == "KEY" else other.get("marks", {}).get(name)
            if a is None or b is None or abs(a - b) > 2.0 / 120.0:
                raise ValueError("continuity drift: %s / %s" % (rec, name))


def require_visible(num, seg, meta):
    t0 = meta["rec0"] / seg.src.fps
    lo, hi = seg.plan[0][0] / seg.src.fps, seg.plan[-1][1] / seg.src.fps
    for event in VISIBLE.get(num, []):
        event_time = meta.get("marks", {}).get(event)
        if event_time is None or not lo - 1.0 / FPS <= t0 + event_time <= hi:
            raise ValueError("shot %s: %s is outside the edit" % (num, event))


def validate_recording(rec, source, meta):
    if meta.get("rec0") is None or meta.get("end") is None or meta.get("seconds") is None:
        raise ValueError("%s: incomplete recording metadata" % rec)
    lacks = missing(rec, meta)
    if lacks:
        raise ValueError("%s: %s" % (rec, ", ".join(lacks)))
    for num, a, b, _what, recording, how, slow in SHOTS:
        for prec, phow, duration in CUTS.get(num, [[recording, how, b - a]]):
            if prec == rec:
                seg = piece(source, meta, phow, duration, slow if num not in CUTS else None)
                require_visible(num, seg, meta)


def audit(g, wanted):
    """Headless contact/timing audit, with the same physics rate as full-quality recording.

    This does not certify framing or rendered audio. That still needs a real preview.
    """
    from types import SimpleNamespace
    report, done = {}, set()
    for rec in wanted:
        if rec in done:
            continue
        group = next((gr for gr in GROUPS if rec in gr), [rec])
        metas, errors = {}, {}
        for take in TAKES:
            errors = {}
            for x in group:
                logfile = os.path.join(WORK, x + ".audit.log")
                lines = run([g, "--headless", "--fixed-fps", "120", "--path", PROJ, "--", "--probe", "trailer75"],
                            {"SHOT": x, "SHOT_SEED": str(take)}, logfile)
                meta = tags_of(lines)
                meta["take"] = take
                metas[x] = meta
                try:
                    source = SimpleNamespace(fps=120, dur=meta.get("seconds") or 0.0)
                    validate_recording(x, source, meta)
                except ValueError as e:
                    errors[x] = str(e)
            if not errors:
                try:
                    check_continuity(group, metas)
                except ValueError as e:
                    errors[rec] = str(e)
            print("audit %s / take %s: %s" % (group, take, errors or "PASS"), flush=True)
            if not errors:
                break
        for x in group:
            report[x] = {"metadata": metas[x], "error": errors.get(x)}
        done.update(group)
    with open(os.path.join(WORK, "audit.json"), "w") as f:
        json.dump({"visual_review": False, "shots": report}, f, indent=2)
    if any(r["error"] for r in report.values()):
        raise ValueError("Choreography audit failed; see %s" % os.path.join(WORK, "audit.json"))

# ---------- made-up footage (--fake) ----------

def fake(shot):
    """A test pattern with a tone for a shot, its moment two seconds in (a check of the edit)."""
    avi = os.path.join(WORK, shot + ".avi")
    meta = os.path.join(WORK, shot + ".json")
    if os.path.exists(avi) and os.path.exists(meta):
        return
    secs = 16.0
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=%dx%d:rate=%d:duration=%.2f" % (W, H, REC_FPS, secs),
                           "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=48000:duration=%.2f" % (200 + 13 * len(shot) * 7, secs),
                           "-vf", "drawtext=fontfile='%s':text='SHOT %s':fontsize=%d:fontcolor=white:x=40:y=40" % (FONT.replace("\\", "/").replace(":", "\\:"), shot, H // 8),
                           "-c:v", "mjpeg", "-q:v", "4", "-c:a", "pcm_s16le", "-shortest", avi])
    tg = {"rec0": REC_FPS // 2, "end": int((secs - 0.6) * REC_FPS), "key": 2.5,
          "marks": {n: 2.3 for n in NEEDS.get(shot, []) if n != "KEY"}, "hits": [], "seconds": 15.0}
    tg["marks"].update({"lodged": 2.5, "free": 3.6, "combo first": 1.1, "combo return": 2.2,
                        "combo kick": 3.8, "prosthetic": 2.5, "cut giant": 1.2, "down foe": 2.9})
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
    if t_in < t0 - 1.0 / src.fps:
        raise ValueError("insufficient lead-in: the edit would include scene setup")
    t_in = max(t0, t_in)
    t_out = min(src.dur, t0 + meta["seconds"]) if meta.get("seconds") is not None else src.dur
    seg = ed.Segment(src, t_in, t_out, sp)
    seg.prepare(FPS)
    n = int(round(secs * FPS))
    short = n - len(seg.plan)
    if short > 0:
        raise ValueError("insufficient tail: %d missing frames (freeze frames are forbidden)" % short)
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
            if prec not in srcs or prec not in metas:
                raise ValueError("shot %s: missing recording %s" % (num, prec))
            seg = piece(srcs[prec], metas[prec], phow, n / FPS, slow if len(pieces) == 1 else None)
            require_visible(num, seg, metas[prec])
            sheet.append({"shot": num, "start": round(a + made / FPS, 3), "end": round(a + (made + n) / FPS, 3),
                          "what": what, "source": prec + ".avi", "take": metas[prec].get("take"),
                          "in": round(seg.t_in, 3), "out": round(seg.plan[-1][1] / seg.src.fps, 3),
                          "moment": round(seg.moment, 3), "slow": slow if len(pieces) == 1 else None,
                          "short_frames": 0})
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
    # Long copy must fit even in the 360p review copy, with the same safe margins.
    while size > 12:
        f = _font(size)
        if max(sum(dr.textlength(ch, font=f) for ch in ln) + size * 0.06 * max(0, len(ln) - 1) for ln in lines) <= W * 0.88:
            break
        size -= 1
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
        else:
            # A missing optional artwork must never leave an unbranded end card.
            from PIL import ImageDraw
            dr = ImageDraw.Draw(im)
            f = _font(int(H * 0.105))
            dr.text((W * 0.5, H * 0.32), "WRECKSMITH", font=f, fill="white", anchor="mm")
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
        items.append((END_START, LENGTH if not END_CALL else END_START + 2.0, ends[0], False))
        if END_CALL:
            items.append((END_START + 2.0, LENGTH, ends[1], False))
    else:
        items.append((END_START, LENGTH, ends[2], False))
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


def music_envelope(n):
    """Smooth duck/recovery; silence is deliberate space for foley, not an abrupt edit."""
    g = np.ones(n, np.float32)
    for start, end, level in DROPS:
        a, b = int(start * ed.AR), int(end * ed.AR)
        ramp = min(int(0.1 * ed.AR), a, n - b)
        g[a:b] = level
        if ramp > 0:
            g[a-ramp:a] = np.linspace(1.0, level, ramp)
            g[b:b+ramp] = np.linspace(level, 1.0, ramp)
    # Let the logo's ring-out end cleanly.
    tail = min(n, int(0.45 * ed.AR))
    g[-tail:] *= np.linspace(1.0, 0.0, tail)
    return g


def riser(start, end, n):
    """Original restrained air/metal swell: an editorial transition, not a fake weapon sound."""
    out = np.zeros((n, 2), np.float32)
    a, b = max(0, int(start * ed.AR)), min(n, int(end * ed.AR))
    if b <= a:
        return out
    u = np.linspace(0.0, 1.0, b-a, dtype=np.float32)
    rng = np.random.default_rng(a)
    noise = rng.standard_normal(b-a).astype(np.float32)
    noise = np.convolve(noise, np.ones(8, np.float32) / 8, mode="same")
    phase = np.cumsum(110.0 + 380.0 * u ** 2) * (2 * math.pi / ed.AR)
    envelope = u ** 2 * np.minimum(1.0, (1.0 - u) * 60.0)
    signal = (noise * 0.6 + np.sin(phase) * 0.12) * envelope
    out[a:b, 0] = signal
    out[a:b, 1] = signal * 0.9
    return out


def contact_accents(segs, metas):
    """Map observed high-energy hits through the speed ramps into the FILM clock."""
    cues, offset = [], 0.0
    for seg in segs:
        if seg.src:
            rec = os.path.splitext(os.path.basename(seg.src.path))[0]
            meta = metas[rec]
            scene0 = meta["rec0"] / seg.src.fps
            lo = seg.plan[0][0] / seg.src.fps
            hi = seg.plan[-1][1] / seg.src.fps
            for hit in meta.get("hits", []):
                at = scene0 + hit["t"]
                if hit["J"] < 35 or not lo <= at <= hi:
                    continue
                film = offset + seg.film_time_of(at, FPS)
                # Sparse accents retain the real metallic/flesh sound of the game.
                if any(a <= film <= b for a, b, _level in DROPS):
                    continue
                if not cues or film - cues[-1] >= 0.65:
                    cues.append(film)
        offset += seg.duration(FPS)
    return cues


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
            raise ValueError("Missing score cue: %s" % path)
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
    bed *= music_envelope(n)[:, None]
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


def mix(segs, path_wav, metas):
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
    contacts = contact_accents(segs, metas)
    for at in contacts:
        hits += boom(at, n) * 0.18
    for a, b in RISES:
        hits += riser(a, b, n) * 0.5
    out = game + bed * 0.6 * duck[:, None] + hits * 0.5
    tail = min(n, int(0.18 * ed.AR))
    out[-tail:] *= np.linspace(1.0, 0.0, tail)[:, None]
    raw = path_wav + ".raw.wav"
    ed.write_wav(raw, out / max(1.0, float(np.abs(out).max())))
    ed.loudnorm(raw, path_wav, tp=-1.5)   # (-1 asked of it came out at -0.9 after the AAC)
    os.remove(raw)
    return {"music": chosen, "contact_accents": contacts, "rises": RISES, "drops": DROPS,
            "target_lufs": -14, "true_peak_ceiling_dbtp": -1.5}

# ---------- the whole ----------

def verify_export(path):
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-count_frames", "-show_streams", "-show_format", "-of", "json", path]))
    video = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
    sound = next((s for s in info["streams"] if s["codec_type"] == "audio"), None)
    if not video or not sound:
        raise ValueError("Export has missing picture or audio: %s" % path)
    if (video["width"], video["height"]) != (W, H) or int(video["nb_read_frames"]) != round(LENGTH * FPS):
        raise ValueError("Export dimensions/frame count mismatch: %s" % path)
    if abs(float(info["format"]["duration"]) - LENGTH) > 0.1:
        raise ValueError("Export duration mismatch: %s" % path)
    return {"frames": int(video["nb_read_frames"]), "duration": float(info["format"]["duration"]),
            "video_codec": video["codec_name"], "audio_codec": sound["codec_name"]}

def main():
    validate_plan()
    if "--plan" in sys.argv:
        for num, a, b, what, _rec, _how, _slow in SHOTS:
            print("%02d  %05.1f-%05.1f  %s" % (num, a, b, what))
        return
    ffmpeg_on_path()
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit("%s not found on the PATH: install it (ffmpeg comes with ffprobe)" % tool)
    os.makedirs(WORK, exist_ok=True)
    only = None
    if "--shots" in sys.argv:
        ix = sys.argv.index("--shots") + 1
        if ix >= len(sys.argv):
            raise ValueError("--shots needs comma-separated recording ids")
        only = sys.argv[ix].split(",")
    wanted = recordings()
    if only and any(r not in wanted for r in only):
        raise ValueError("Unknown recording. Choose from: %s" % ",".join(wanted))
    if FAKE:
        for r in wanted:
            fake(r)
    else:
        g = godot()
        engine = subprocess.check_output([g, "--version"], text=True).strip()
        fresh(engine)
        print("Godot: %s" % g)
        fresh_project(g)
        if "--audit" in sys.argv:
            audit(g, only or wanted)
            return
        if only:
            for r in only:
                for ext in (".avi", ".json"):
                    p = os.path.join(WORK, r + ext)
                    if os.path.exists(p):
                        os.remove(p)
        lacks = record_all(g, only or wanted)
        if lacks:
            with open(os.path.join(WORK, "rejected_takes.json"), "w") as f:
                json.dump(lacks, f, indent=2)
            raise ValueError("No trailer exported: failed takes %s. See rejected_takes.json" % lacks)
        if only:
            return
    srcs, metas = {}, {}
    for r in wanted:
        avi, meta = os.path.join(WORK, r + ".avi"), os.path.join(WORK, r + ".json")
        if os.path.exists(avi) and os.path.exists(meta):
            srcs[r] = ed.Source(avi)
            metas[r] = json.load(open(meta))
    segs, sheet = cut(srcs, metas)
    if not FAKE:
        for group in GROUPS:
            check_continuity(group, metas)
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
    if enc.wait():
        raise RuntimeError("Picture encoder failed; no final trailer was published")
    wav = os.path.join(WORK, "sound.wav")
    sound = mix(segs, wav, metas)
    pending = []
    for with_text, name in ((True, base + ".mp4"), (False, base + "_clean.mp4")):
        temp_output = os.path.join(out_dir, "." + name + ".partial.mp4")
        graph, inputs = overlay_graph(cards, ends, with_text)
        args = ["ffmpeg", "-y", "-v", "error", "-i", pic]
        for x in inputs:
            args += x
        args += ["-i", wav, "-filter_complex", graph, "-map", "[v]", "-map", "%d:a" % (len(inputs) + 1),
                 "-c:v", "libx264", "-preset", "slow", "-crf", "16" if not PREVIEW else "22", "-profile:v", "high", "-pix_fmt", "yuv420p",
                 "-r", str(FPS), "-c:a", "aac", "-b:a", "320k", "-ar", str(ed.AR), "-t", "%.3f" % LENGTH, "-movflags", "+faststart",
                 temp_output]
        subprocess.check_call(args)
        verified = verify_export(temp_output)
        pending.append((temp_output, os.path.join(out_dir, name), verified))
    # Keep previous masters until both new encodes have actually passed verification.
    for temp_output, destination, _verified in pending:
        os.replace(temp_output, destination)
        print("  -> %s" % destination)
    with open(os.path.join(out_dir, base + "_cut.json"), "w") as f:
        json.dump({"fps": FPS, "size": [W, H], "shots": sheet, "text": TEXT, "sound": sound,
                   "exports": [v for _t, _d, v in pending],
                   "synthetic_test": FAKE, "visual_review_required": True}, f, indent=1)


if __name__ == "__main__":
    main()
