#!/usr/bin/env python3
"""WRECKSMITH - THE CROWD WANTS BLOOD, the trailer, made from the game itself on your PC.

The cut of the trailer that worked, its lines and its order kept, made again as a film:

  cold open   THE CROWD WANTS BLOOD, on black, over a heartbeat
  the arena   a crane from the sky down over the full stands to the champion walking in:
              ENTER THE ARENA; the crowd on its feet under the Emperor's box
  first blood a duel, its kill in slow motion
  the beasts  the lion's kill: NOT EVERY FOE IS A MAN; the dragon's fire across the sand
  the forge   a weapon going up on the anvil: FORGE YOUR WEAPON / VOXEL BY VOXEL
  the joke    a wheel of cheese bowled along the sand takes a man off his feet: ...AND CHEESE
  the modes   a free-for-all from high: CHOOSE YOUR CHAOS; friends, their names over their
              heads, against the minotaur: BRING YOUR FRIENDS / ONLINE MULTIPLAYER
  the battle  the cyclops; a montage of the hardest blows, one a beat: EVERY BLOW LANDS /
              EVERY BONE BREAKS; the troll; the hydra, its kill in the slowest motion of all,
              cut to black on the blow
  the title   a breath of silence, then on one great hit the logo over the champion alone in
              the middle, his axe raised to the crowd: COMING SOON TO STEAM, WISHLIST NOW

Every fight is seen through a film camera (not the helmet of the rise trailer): wide on the
sand while they fight, cut in close on the same side for the kill, which eases into slow motion
and out of it with a white flash on the blow. The game is recorded at 120 frames a second, so
the full speed has a film camera's motion blur and the slow motion is smooth. Every cut falls on
the beat of its own score (90 bpm, tools/rise_score.py: a heartbeat and a drone in the dark, the
drums coming in with the arena, strings, a choir of men and a horn at each act, a sub boom and a
braam on every kill, whooshes under the cuts, risers into the battle and the finale, a silence and
the title hit), the fight's own sound under it (the blows, the cries, the crowd; slowed and
muffled in the slow motion). Graded warm and hard, with a film's grain, darkened corners and
cinema bars (2.39:1); the sound brought to -14 LUFS.

    python tools/make_blood_trailer.py          -> docs/store/trailer_blood.mp4 (1920x1080, 30 fps)
    TRAILER_FPS=60                              -> the same at 60 frames a second
    python tools/make_blood_trailer.py --fake   -> the whole cut from made-up footage (a check)

Needs Godot 4.7 with a display, ffmpeg (with ffprobe), Pillow and numpy. Work files go to
<trailer_work>/blood; shots already made are kept (delete one's .avi to make it again)."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_trailer as mt  # noqa: E402
import make_rise_trailer as rt  # noqa: E402
import trailer_edit as ed  # noqa: E402

FPS, W, H = rt.FPS, rt.W, rt.H
BEAT = rt.BEAT
REC_FPS = rt.REC_FPS
WORK = os.path.join(mt.TMP, "blood")
LOGO = os.path.join(os.path.dirname(HERE), "docs", "store", "capsules", "logo.png")
# The bouts, filmed by tests/shouldershots.gd with its film camera (CLIP_CAM=film): the shot, the
# beats before the kill lands and after it, the speed of its slow motion.
BOUTS = {
    "duel": (6, 4, 0.3),
    "lion": (6, 4, 0.25),
    "cyclops": (5, 3, 0.25),
    "minotaur": (5, 3, 0.25),
    "troll": (6, 3, 0.25),
    "hydra": (7, 1, 0.15),
}
# The staged shots (tests/stageshots.gd), each recorded once.
STAGES = ["reveal", "crowd", "dragon", "cheese", "chaos", "squad", "finale"]


# ---------- the shots ----------

def record_stage(k):
    """One staged shot: <blood>/<k>.avi and <k>.json (where it starts, its moment, its end)."""
    avi = os.path.join(WORK, k + ".avi")
    meta = os.path.join(WORK, k + ".json")
    if os.path.exists(avi) and os.path.getsize(avi) and os.path.exists(meta):
        print("  %s: kept" % k)
        return
    rec = mt.run([mt.G, "--write-movie", avi, "--fixed-fps", str(REC_FPS), "--path", mt.PROJ, "--", "--probe", "stageshots"],
                 {"STAGE": k}, os.path.join(WORK, k + ".rec"))
    f0, f1 = mt.tagged(rec, "REC_START"), mt.tagged(rec, "REC_END")
    if f0 is None or f1 is None or not os.path.exists(avi):
        print("  %s: the recording failed (see %s)" % (k, os.path.join(WORK, k + ".rec")))
        if os.path.exists(avi):
            os.remove(avi)
        return
    key = mt.tagged(rec, "KEY")
    hits = sorted({(int(p[1]), int(p[2])) for p in (l.split() for l in rec) if len(p) >= 3 and p[0] == "HIT"})
    with open(meta, "w") as f:
        json.dump({"rec0": f0, "end": f1, "key": key, "hits": [list(h) for h in hits]}, f)
    print("  %s: recorded%s" % (k, "" if key is None else " (its moment %.1f s in)" % (key / REC_FPS)))


# ---------- the cards ----------

def _cinzel(size, weight=700):
    import make_capsules as mc
    return mc.cinzel(size, weight)


def _tracked(dr, x, y, txt, fnt, fill, track):
    for ch in txt:
        dr.text((x, y), ch, font=fnt, fill=fill)
        x += fnt.getlength(ch) + track


def _tracked_width(fnt, txt, track):
    return sum(fnt.getlength(ch) for ch in txt) + track * (len(txt) - 1)


def card_line(path, title, sub=None, size=64, y=None):
    """The trailer's own card: the line in gold Roman capitals spaced wide, a thin gold rule on
    each side of it, a smaller line under it; a soft shadow under the letters and a faint dark
    band behind, so it reads over the bright sand."""
    from PIL import Image, ImageDraw, ImageFilter
    import make_capsules as mc
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fnt = _cinzel(size, 700)
    track = int(size * 0.32)
    tw = _tracked_width(fnt, title, track)
    y = int(H * 0.74) if y is None else int(y)
    x = (W - tw) / 2
    sub_f = _cinzel(int(size * 0.5), 700) if sub else None
    sub_track = int(size * 0.24)
    # The band behind, soft-edged, only as wide as the line wants.
    band = Image.new("L", (W, H), 0)
    bh = int(size * (2.0 if sub else 1.5))
    ImageDraw.Draw(band).rectangle([int(x - size * 2.6), y - int(size * 0.35), int(x + tw + size * 2.6), y + bh], fill=110)
    band = band.filter(ImageFilter.GaussianBlur(size * 0.9))
    shade = Image.new("RGBA", (W, H), (8, 5, 3, 255))
    shade.putalpha(band)
    img = Image.alpha_composite(img, shade)
    # The shadow of the letters.
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    _tracked(sd, x + 2, y + 4, title, fnt, (0, 0, 0, 220), track)
    if sub:
        sw = _tracked_width(sub_f, sub, sub_track)
        _tracked(sd, (W - sw) / 2 + 2, y + int(size * 1.28) + 3, sub, sub_f, (0, 0, 0, 200), sub_track)
    sh = sh.filter(ImageFilter.GaussianBlur(5))
    img = Image.alpha_composite(img, sh)
    dr = ImageDraw.Draw(img)
    _tracked(dr, x, y, title, fnt, mc.GOLD_HI + (255,), track)
    # The rules either side, at the letters' middle.
    ry = y + int(size * 0.52)
    gap, rl = int(size * 0.7), int(size * 1.6)
    dr.rectangle([int(x - gap - rl), ry, int(x - gap), ry + 2], fill=mc.GOLD + (230,))
    dr.rectangle([int(x + tw + gap), ry, int(x + tw + gap + rl), ry + 2], fill=mc.GOLD + (230,))
    if sub:
        sw = _tracked_width(sub_f, sub, sub_track)
        _tracked(dr, (W - sw) / 2, y + int(size * 1.28), sub, sub_f, (240, 214, 160, 255), sub_track)
    img.save(path)


def card_end(dir_):
    """The end card over the last shot, each its own layer (they come in one after another): a
    dark sky for the logo, the logo (docs/store/capsules/logo.png, the store's own), the rule and
    COMING SOON TO STEAM, then WISHLIST NOW."""
    from PIL import Image, ImageDraw, ImageFilter
    import make_capsules as mc
    sky = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sky).rectangle([0, 0, W, int(H * 0.56)], fill=165)
    sky = sky.filter(ImageFilter.GaussianBlur(H * 0.09))
    dark = Image.new("RGBA", (W, H), (8, 5, 3, 255))
    dark.putalpha(sky)
    p0 = os.path.join(dir_, "end_dark.png")
    dark.save(p0)
    logo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if os.path.exists(LOGO):
        lg = Image.open(LOGO).convert("RGBA")
        k = min(W * 0.6 / lg.width, H * 0.24 / lg.height)
        lg = lg.resize((int(lg.width * k), int(lg.height * k)), Image.LANCZOS)
    else:
        lg = mc.fit(mc.voxel_title(720), int(W * 0.6), int(H * 0.24))
    ly = int(H * 0.33) - lg.height // 2
    logo.alpha_composite(lg, ((W - lg.width) // 2, ly))
    p1 = os.path.join(dir_, "end_logo.png")
    logo.save(p1)
    line = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(line)
    ry = ly + lg.height + 22
    dr.rectangle([W // 2 - 300, ry, W // 2 + 300, ry + 3], fill=mc.GOLD + (255,))
    f1 = _cinzel(58, 700)
    t1 = "COMING SOON TO STEAM"
    w1 = _tracked_width(f1, t1, 12)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _tracked(ImageDraw.Draw(sh), (W - w1) / 2 + 2, ry + 30 + 4, t1, f1, (0, 0, 0, 220), 12)
    line = Image.alpha_composite(line, sh.filter(ImageFilter.GaussianBlur(4)))
    _tracked(ImageDraw.Draw(line), (W - w1) / 2, ry + 30, t1, f1, mc.GOLD_HI + (255,), 12)
    p2 = os.path.join(dir_, "end_line.png")
    line.save(p2)
    call = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    f2 = _cinzel(40, 600)
    t2 = "WISHLIST NOW"
    w2 = _tracked_width(f2, t2, 14)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _tracked(ImageDraw.Draw(sh), (W - w2) / 2 + 2, ry + 112 + 3, t2, f2, (0, 0, 0, 220), 14)
    call = Image.alpha_composite(call, sh.filter(ImageFilter.GaussianBlur(4)))
    _tracked(ImageDraw.Draw(call), (W - w2) / 2, ry + 112, t2, f2, (232, 204, 150, 255), 14)
    p3 = os.path.join(dir_, "end_call.png")
    call.save(p3)
    return p0, p1, p2, p3


# ---------- the edit ----------

def stage(e, srcs, metas, k, beats, start=0.0, key_beat=None, fade_in=0.0, fade_out=0.0, flash=False):
    """A staged shot for `beats` beats from `start` s into it, or with its moment on `key_beat`;
    its start (film s), and the moment's (or None)."""
    src, meta = srcs[k], metas[k]
    t_in = (meta["rec0"] + 2) / src.fps + start
    key_t = None
    if key_beat is not None and meta.get("key") is not None:
        kt = (meta["rec0"] + meta["key"]) / src.fps
        t_in = max((meta["rec0"] + 2) / src.fps, kt - key_beat * BEAT)
        key_t = kt - t_in
    seg = ed.Segment(src, t_in, t_in + beats * BEAT + 0.5, ed.Speed([]), fade_in=fade_in, fade_out=fade_out,
                     flash=[key_t] if (flash and key_t is not None) else [], name=k)
    t0 = e.add(seg, beats)
    if key_t is not None:
        e.cues["hits"].append(round(t0 + key_t, 3))
    return t0, (None if key_t is None else t0 + key_t)


def bout(e, srcs, metas, k):
    """A bout through the film camera, its kill eased into slow motion with a flash on the blow;
    its start and the kill's film time."""
    lead, after, slow = BOUTS[k]
    src, meta = srcs[k], metas[k]
    kt = rt.source_time(src, meta, meta["kill"])
    if k == "hydra":
        sp = ed.Speed.ramp(kt, slow, before=0.5, after=1.2, ease=0.35)
    else:
        sp = ed.Speed.ramp(kt, slow, before=0.55, after=0.6, ease=0.3)
    lo = rt.source_time(src, meta, meta["from"]) + 0.05
    t_in = max(lo, ed.lead_for(src.fps, FPS, kt, sp, lead * BEAT))
    t_out = rt.source_time(src, meta, meta["kill"] + int(rt.REC_TAIL * REC_FPS)) - 0.05
    seg = ed.Segment(src, t_in, t_out, sp, name=k)
    t0 = e.add(seg, lead + after)
    hit_t = t0 + seg.film_time_of(kt, FPS)
    e.cues["hits"].append(round(hit_t, 3))
    seg.flash = [hit_t - t0]
    return t0, hit_t


def over(e, cd, name, title, sub, t0, t1, size=64, y=None):
    p = os.path.join(cd, name + ".png")
    card_line(p, title, sub, size, y)
    e.card(p, t0, t1, 0.4, 0.35, 10)


def build(srcs, metas, work):
    """The whole cut, beat by beat."""
    cd = os.path.join(work, "cards")
    os.makedirs(cd, exist_ok=True)
    e = rt.Edit()
    # THE CROWD WANTS BLOOD, on black, over the heartbeat.
    t0 = e.add(ed.Segment(None, dur=0), 4)
    over(e, cd, "c_blood", "THE CROWD WANTS BLOOD", None, t0 + 0.3, t0 + 4 * BEAT - 0.4, 60, H * 0.46)
    # ENTER THE ARENA: the crane down from the sky, the drums coming in with it.
    if "reveal" in srcs:
        e.act("rise")
        t0, _k = stage(e, srcs, metas, "reveal", 9, fade_in=0.6)
        over(e, cd, "c_arena", "ENTER THE ARENA", None, t0 + 4 * BEAT, t0 + 9 * BEAT - 0.25)
    if "crowd" in srcs:
        stage(e, srcs, metas, "crowd", 3, start=0.4)
    e.act("rise")
    if "duel" in srcs:
        bout(e, srcs, metas, "duel")
    e.act("battle")
    if "lion" in srcs:
        t0, hit = bout(e, srcs, metas, "lion")
        over(e, cd, "c_foe", "NOT EVERY FOE IS A MAN", None, t0 + 0.35, max(t0 + 1.6, min(t0 + 3.4, hit - 0.8)))
    if "dragon" in srcs:
        stage(e, srcs, metas, "dragon", 5, key_beat=1.5)
    if "forge" in srcs:
        src, meta = srcs["forge"], metas["forge"]
        t_in = (meta["rec0"] + 6) / src.fps
        t0 = e.add(ed.Segment(src, t_in, t_in + 8.0, ed.Speed([]), fade_in=0.15, fade_out=0.2, shutter=1.0, name="forge"), 6)
        over(e, cd, "c_forge", "FORGE YOUR WEAPON", "VOXEL BY VOXEL", t0 + 0.4, t0 + 6 * BEAT - 0.3)
    if "cheese" in srcs:
        t0, hit = stage(e, srcs, metas, "cheese", 5, key_beat=3, flash=False)
        at = hit if hit is not None else t0 + 3 * BEAT
        over(e, cd, "c_cheese", "...AND CHEESE", None, at + 0.1, t0 + 5 * BEAT - 0.2)
    if "chaos" in srcs:
        t0, _k = stage(e, srcs, metas, "chaos", 6, start=0.2)
        over(e, cd, "c_chaos", "CHOOSE YOUR CHAOS", None, t0 + 0.4, t0 + 6 * BEAT - 0.3)
    if "squad" in srcs:
        t0, _k = stage(e, srcs, metas, "squad", 6, start=0.2)
        over(e, cd, "c_friends", "BRING YOUR FRIENDS", "ONLINE MULTIPLAYER", t0 + 0.4, t0 + 6 * BEAT - 0.3)
    if "cyclops" in srcs:
        bout(e, srcs, metas, "cyclops")
    montage(e, srcs, metas, cd)
    if "troll" in srcs:
        bout(e, srcs, metas, "troll")
    if "hydra" in srcs:
        lead = BOUTS["hydra"][0]
        e.cues["risers"].append([round(e.t + max(0.0, (lead - 4) * BEAT), 3), round(e.t + lead * BEAT, 3)])
        bout(e, srcs, metas, "hydra")
    # A breath of silence, then the title on one great hit, over the champion alone.
    e.cues["silence"] = [round(e.t, 3), round(e.t + 2 * BEAT, 3)]
    e.add(ed.Segment(None, dur=0), 2)
    e.cues["final"] = round(e.t, 3)
    dark, logo, line, call = card_end(cd)
    if "finale" in srcs:
        src, meta = srcs["finale"], metas["finale"]
        t_in = (meta["rec0"] + 2) / src.fps
        t0 = e.add(ed.Segment(src, t_in, t_in + 12 * BEAT + 0.5, ed.Speed([]), fade_out=1.0, name="finale"), 12)
    else:
        t0 = e.add(ed.Segment(None, dur=0), 12)
    end = e.t
    e.card(dark, t0, end - 1.0, 0.1, 0.9, 0, cue=False)
    e.card(logo, t0, end - 1.0, 0.12, 0.9, 0, cue=False)
    e.card(line, t0 + 2 * BEAT, end - 1.0, 0.6, 0.9, 6)
    e.card(call, t0 + 4 * BEAT, end - 1.0, 0.6, 0.9, 6)
    e.cues["length"] = round(e.t, 3)
    return e


def montage(e, srcs, metas, cd):
    """A cut on every beat: the hardest blows of the bouts (not their kills), at full speed, a
    flash on every other one, EVERY BLOW LANDS / EVERY BONE BREAKS over them."""
    pool = []
    for k in BOUTS:
        if k not in srcs:
            continue
        meta = metas[k]
        for f, J in meta.get("hits", []):
            if meta["from"] + 30 <= f <= meta["kill"] - int(1.2 * REC_FPS):
                pool.append((J, k, f))
    pool.sort(reverse=True)
    picked, per = [], {}
    for J, k, f in pool:
        if per.get(k, 0) >= 2 or any(k == k2 and abs(f - f2) < REC_FPS for _j, k2, f2 in picked):
            continue
        picked.append((J, k, f))
        per[k] = per.get(k, 0) + 1
        if len(picked) >= 8:
            break
    order = {k: i for i, k in enumerate(BOUTS)}
    picked.sort(key=lambda x: (order.get(x[1], 0), x[2]))
    if len(picked) % 2:
        picked = picked[:-1]
    if len(picked) < 2:
        return
    e.act("climax")
    e.cues["risers"].append([round(max(0.0, e.t - 4 * BEAT), 3), round(e.t, 3)])
    t_start = e.t
    for i, (J, k, f) in enumerate(picked):
        src = srcs[k]
        th = rt.source_time(src, metas[k], f)
        t0 = e.add(ed.Segment(src, th - 0.25, th + 1.0, ed.Speed([]), flash=[0.25] if i % 2 == 0 else [], name="montage"), 1)
        if i % 2 == 0:
            e.cues["hits"].append(round(t0 + 0.25, 3))
    half = len(picked) // 2 * BEAT
    over(e, cd, "c_m1", "EVERY BLOW LANDS", None, t_start + 0.1, t_start + half - 0.2, 72, H * 0.45)
    over(e, cd, "c_m2", "EVERY BONE BREAKS", None, t_start + half + 0.1, e.t - 0.15, 72, H * 0.45)


# ---------- made-up footage, to check the whole cut without the game ----------

def fake_sources(work):
    srcs, metas = {}, {}
    keys = list(BOUTS) + STAGES + ["forge"]
    for i, k in enumerate(keys):
        path = os.path.join(work, k + ".avi")
        fps = 30 if k == "forge" else REC_FPS
        secs = 10 if k in STAGES else 9
        if not os.path.exists(path):
            subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=%d:duration=%d" % (fps, secs),
                                   "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=48000:duration=%d" % (220 + 30 * i, secs),
                                   "-c:v", "mjpeg", "-q:v", "4", "-c:a", "pcm_s16le", "-shortest", path])
        srcs[k] = ed.Source(path)
        if k == "forge":
            metas[k] = {"rec0": 0, "end": 270}
        elif k in STAGES:
            metas[k] = {"rec0": 0, "end": int(9.5 * REC_FPS), "key": int(2.5 * REC_FPS), "hits": []}
        else:
            metas[k] = {"rec0": 0, "kill": int(6.0 * REC_FPS), "from": int(1.6 * REC_FPS), "hits": [[int(3.0 * REC_FPS), 40 + i], [int(4.0 * REC_FPS), 30 + i]]}
    return srcs, metas


def main():
    fake = "--fake" in sys.argv
    mt.ffmpeg_on_path()
    mt.need("ffmpeg")
    mt.need("ffprobe")
    try:
        import PIL  # noqa: F401
        import numpy  # noqa: F401
    except ImportError:
        sys.exit("Pillow and numpy are needed: pip install pillow numpy")
    # The rise trailer's recorder, pointed at this trailer's own work folder (its bouts are filmed
    # differently: through the film camera, not the helmet).
    rt.RTMP = WORK
    os.makedirs(WORK, exist_ok=True)
    if fake:
        work = os.path.join(WORK, "fake")
        os.makedirs(work, exist_ok=True)
        srcs, metas = fake_sources(work)
        e = build(srcs, metas, work)
        rt.film(e, work, os.path.join(work, "trailer_blood_fake.mp4"))
        return
    mt.G = mt.godot()
    print("Godot: %s\nwork dir: %s" % (mt.G, WORK))
    print("== the project copy")
    rt.project()
    os.environ["CLIP_CAM"] = "film"
    print("== the bouts (each played twice: once to find the kill, once filmed at 120 frames a second)")
    for k in BOUTS:
        rt.record(k)
    print("== the staged shots")
    for k in STAGES:
        record_stage(k)
    print("== the forge")
    rt.record_forge()
    srcs, metas = {}, {}
    for k in list(BOUTS) + STAGES + ["forge"]:
        avi = os.path.join(WORK, k + ".avi")
        meta = os.path.join(WORK, k + ".json")
        if os.path.exists(avi) and os.path.exists(meta):
            with open(meta) as f:
                metas[k] = json.load(f)
            srcs[k] = ed.Source(avi)
    if not any(k in srcs for k in BOUTS):
        sys.exit("no bout was recorded: see the .dry and .rec files in %s" % WORK)
    print("== the cut")
    e = build(srcs, metas, WORK)
    rt.film(e, WORK, os.path.join(mt.OUT, "trailer_blood.mp4"))


if __name__ == "__main__":
    main()
