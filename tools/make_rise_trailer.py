#!/usr/bin/env python3
"""WRECKSMITH - RISE, the trailer, made from the game itself on your PC.

One gladiator's rise from a slave with a stick to the champion of Rome, cut to its own score:

  cold open   a flash-forward: the troll's kill in deep slow motion, then black
  titles      EVERY CHAMPION OF ROME / BEGAN AS A SLAVE, over a heartbeat
  act I       the slave's bout, the first blood
  the forge   a weapon going up on the anvil voxel by voxel: FORGE YOUR OWN STEEL
  act II      the big lion, the cyclops, the minotaur
  montage     a cut on every beat, the hardest blows of all of them: EVERY BLOW LANDS /
              EVERY BONE BREAKS
  act III     the troll, champion of Rome; the hydra, its kill in the slowest motion of all,
              cut to black on the blow
  silence     a breath of black
  the title   one great hit: WRECKSMITH, EARN YOUR FREEDOM, WISHLIST NOW ON STEAM

Every bout is seen through the camera on his helmet (the user's GoPro) and, for the kill of the
big ones, a film camera low on the sand with a long lens and a shallow focus. Each kill eases into
slow motion and out of it; the game is recorded at 120 frames a second, so the slow motion is
smooth and the full speed has a film camera's motion blur. Every cut falls on the beat of the
score (90 bpm), and every kill on a beat: the score (tools/rise_score.py) is written to the cut,
with a sub boom and a braam on each kill, whooshes under the cuts, risers into the montage and the
finale, a silence and the title hit. The picture is graded warm and hard, with a film's grain,
darkened corners and cinema bars (2.39:1); the sound is the fight's own (slowed and muffled under
the slow motion) under the score, which gives way to the blows, and the whole is brought to -14
LUFS (what Steam and YouTube play at).

    python tools/make_rise_trailer.py          -> docs/store/trailer_rise.mp4 (1920x1080, 30 fps)
    TRAILER_FPS=60                             -> the same at 60 frames a second
    python tools/make_rise_trailer.py --fake   -> the whole cut from made-up footage (a check)

Needs Godot 4.7 with a display, ffmpeg (with ffprobe), Pillow and numpy. Work files go to
<trailer_work>/rise; shots already made are kept (delete one's .avi to make it again)."""
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_trailer as mt  # noqa: E402
import trailer_edit as ed  # noqa: E402

REC_FPS = 120                      # the game recorded at a frame for every physics step
FPS = int(os.environ.get("TRAILER_FPS", "30"))
W, H = 1920, 1080
BPM = 90.0
BEAT = 60.0 / BPM                  # 2/3 s: 20 frames at 30 fps, 40 at 60
BAR_PX = 138                       # the cinema bars (2.39:1 in 16:9)
RTMP = os.path.join(mt.TMP, "rise")
SEEDS = ["", "3", "11", "21", "5", "9", "14", "27"]
REC_LEAD, REC_TAIL = 4.2, 2.6      # seconds of the fight kept before the kill and after it
# The bouts in order: the shot, the card (its number small, what it is large), the beats before
# the kill lands and after it, and the speed of its slow motion.
BOUTS = [
    ("slave", "BOUT I", "A SLAVE WITH A STICK", 7, 5, 0.3),
    ("recruit", "BOUT IV", "FIRST BLOOD", 7, 5, 0.3),
    ("lion", "BOUT VIII", "THE BIG LION", 7, 5, 0.25),
    ("cyclops", "BOUT XVI", "THE CYCLOPS", 7, 5, 0.25),
    ("minotaur", "BOUT XXIV", "THE MINOTAUR", 7, 5, 0.25),
    ("troll", "BOUT XL", "CHAMPION OF ROME", 7, 5, 0.25),
    ("hydra", "BOUT LXIV", "THE HYDRA", 8, 1, 0.15),
]
COLD = ["troll", "minotaur", "cyclops", "lion"]   # the flash-forward: the first of these made
ACT2 = "lion"                                       # where the battle starts
MONTAGE_BEFORE = "troll"                            # the montage goes in before this bout


# ---------- the shots ----------

def _meta_path(k):
    return os.path.join(RTMP, k + ".json")


def _foe_death(lines):
    for l in lines:
        p = l.split()
        if len(p) >= 3 and p[0] == "DEATH" and p[2] != "local":
            return int(p[1])
    return None


KILL_SLACK = REC_FPS // 4          # how far the drawn kill may fall from the one it was framed on
DRAW_TRIES = 3


def _dry(k, seed):
    """The bout run without drawing: the frame its foe falls on, or None."""
    env = {"SHOT": k, "CLIP_DRY": "1", "CLIP_SECONDS": "75"}
    if seed:
        env["CLIP_SEED"] = seed
    dry = mt.run([mt.G, "--fixed-fps", str(REC_FPS), "--path", mt.PROJ, "--", "--probe", "shouldershots"], env, os.path.join(RTMP, k + ".dry"))
    d = _foe_death(dry)
    return d if d is not None and d > 0 else None


def _drawn(k, seed, death, avi):
    """The bout drawn into <k>.avi from REC_LEAD before `death` to REC_TAIL after it: its output
    lines and the frame the drawing starts on."""
    start = max(0, death - int(REC_LEAD * REC_FPS))
    env = {"SHOT": k, "CLIP_FROM": str(start), "CLIP_KILL": str(death), "CLIP_SECONDS": "%.1f" % ((death + REC_TAIL * REC_FPS) / REC_FPS + 1.5)}
    if seed:
        env["CLIP_SEED"] = seed
    rec = mt.run([mt.G, "--write-movie", avi, "--fixed-fps", str(REC_FPS), "--path", mt.PROJ, "--", "--probe", "shouldershots"], env, os.path.join(RTMP, k + ".rec"))
    return rec, start


def record(k):
    """One bout: <rise>/<k>.avi (every frame of the game from the start, black until the kept
    part) and <k>.json (where it starts, the kill, the hard blows).

    The bout is run twice: once undrawn, to find the frame its foe falls on, then drawn from a
    little before it. The two go the same way (the game's dice are seeded and nothing in the
    fight reads the wall clock), but should the drawn one go another way, the kill would fall in
    the black or outside the film camera's part: it is drawn again round the kill it did make."""
    avi = os.path.join(RTMP, k + ".avi")
    if os.path.exists(avi) and os.path.getsize(avi) and os.path.exists(_meta_path(k)):
        print("  %s: kept" % k)
        return
    for seed in SEEDS:
        death = _dry(k, seed)
        if death is None:
            print("  %s: seed %s, the foe did not fall; trying another" % (k, seed or "default"))
            continue
        for _ in range(DRAW_TRIES):
            rec, start = _drawn(k, seed, death, avi)
            rec0 = mt.tagged(rec, "REC_START")
            if rec0 is None or not os.path.exists(avi):
                print("  %s: the recording failed (see %s)" % (k, os.path.join(RTMP, k + ".rec")))
                return
            d2 = _foe_death(rec)
            if d2 is not None and abs(d2 - death) <= KILL_SLACK:
                hits = sorted({(int(p[1]), int(p[2])) for p in (l.split() for l in rec) if len(p) >= 3 and p[0] == "HIT"})
                with open(_meta_path(k), "w") as f:
                    json.dump({"rec0": rec0, "kill": d2, "from": start, "hits": [list(h) for h in hits], "seed": seed or ""}, f)
                print("  %s: recorded (seed %s, the kill %.1f s in)" % (k, seed or "default", d2 / REC_FPS))
                return
            if d2 is None:
                break
            print("  %s: drawn, the kill fell %.1f s in, not %.1f s; drawing it again round that" % (k, d2 / REC_FPS, death / REC_FPS))
            death = d2
        print("  %s: seed %s would not hold its kill; trying another" % (k, seed or "default"))
    if os.path.exists(avi):
        os.remove(avi)
    print("  %s: left out (no seed gave a kill to film; see %s and .rec)" % (k, os.path.join(RTMP, k + ".dry")))


def record_forge():
    avi = os.path.join(RTMP, "forge.avi")
    if os.path.exists(avi) and os.path.getsize(avi) and os.path.exists(_meta_path("forge")):
        print("  forge: kept")
        return
    rec = mt.run([mt.G, "--write-movie", avi, "--fixed-fps", "30", "--path", mt.PROJ, "--", "--probe", "forgeclip"],
                 {"FORGE_SECONDS": "4", "FORGE_DESIGN": "executionerAxe"}, os.path.join(RTMP, "forge.rec"))
    f0, f1 = mt.tagged(rec, "REC_START"), mt.tagged(rec, "REC_END")
    if f0 is None or f1 is None or not os.path.exists(avi):
        print("  forge: the recording failed (see %s)" % os.path.join(RTMP, "forge.rec"))
        return
    with open(_meta_path("forge"), "w") as f:
        json.dump({"rec0": f0, "end": f1}, f)
    print("  forge: recorded")


def project():
    """The project copy (make_trailer.fresh_project), its movie writer set to a near-lossless
    picture (MJPEG at 95) and the sound at 48 kHz."""
    mt.fresh_project()
    with open(os.path.join(mt.PROJ, "override.cfg"), "a") as f:
        f.write("[editor]\nmovie_writer/mjpeg_quality=0.95\nmovie_writer/mix_rate=48000\n")


# ---------- the cards ----------

def _font(size):
    from PIL import ImageFont
    import make_capsules as mc
    return ImageFont.truetype(mc.FONT, size)


def _text(dr, xy, txt, fnt, fill, track=0, stroke=6, anchor_center=False):
    """Text with letter spacing (`track` px between letters) and a dark stroke round it."""
    x, y = xy
    if anchor_center:
        wdt = sum(fnt.getlength(ch) for ch in txt) + track * (len(txt) - 1)
        x -= wdt / 2
    for ch in txt:
        dr.text((x, y), ch, font=fnt, fill=fill, stroke_width=stroke, stroke_fill=(16, 10, 6, 255))
        x += fnt.getlength(ch) + track


def card_bout(path, top, line):
    """A bout's card, low on the left over a soft dark band: its number small in gold over a blood
    rule, what it is large."""
    from PIL import Image, ImageDraw, ImageFilter
    import make_capsules as mc
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band).rectangle([0, int(H * 0.66), int(W * 0.62), H - BAR_PX], fill=150)
    band = band.filter(ImageFilter.GaussianBlur(60))
    shade = Image.new("RGBA", (W, H), (8, 5, 3, 255))
    shade.putalpha(band)
    img = Image.alpha_composite(img, shade)
    dr = ImageDraw.Draw(img)
    x = int(W * 0.065)
    y = int(H * 0.70)
    _text(dr, (x, y), top, _font(40), mc.GOLD + (255,), track=10, stroke=3)
    dr.rectangle([x, y + 58, x + 180, y + 62], fill=mc.BLOOD + (255,))
    _text(dr, (x, y + 76), line, _font(92), mc.GOLD_HI + (255,), track=4, stroke=6)
    img.save(path)


def card_center(path, line, size=96, y=None):
    """A line across the middle (over black or over the fight), with a faint warm glow."""
    from PIL import Image, ImageDraw, ImageFilter
    import make_capsules as mc
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fnt = _font(size)
    y = int(H * 0.45) - size // 2 if y is None else y
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _text(ImageDraw.Draw(glow), (W / 2, y), line, fnt, (255, 170, 60, 160), track=int(size * 0.12), stroke=10, anchor_center=True)
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    img = Image.alpha_composite(img, glow)
    dr = ImageDraw.Draw(img)
    _text(dr, (W / 2, y), line, fnt, mc.GOLD_HI + (255,), track=int(size * 0.12), stroke=5, anchor_center=True)
    img.save(path)


def card_end(dir_):
    """The end: a dark warm glow, the title on it, then the line, then the call, each its own
    layer (they come in one after another)."""
    from PIL import Image, ImageDraw, ImageFilter
    import make_capsules as mc
    base = Image.new("RGBA", (W, H), (10, 7, 5, 255))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.18, H * 0.12, W * 0.82, H * 0.88], fill=95)
    glow = glow.filter(ImageFilter.GaussianBlur(170))
    warm = Image.new("RGBA", (W, H), (125, 54, 18, 255))
    warm.putalpha(glow)
    base = Image.alpha_composite(base, warm)
    p0 = os.path.join(dir_, "end_bg.png")
    base.save(p0)
    logo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    title = mc.fit(mc.voxel_title(720), int(W * 0.72), 300)
    logo.paste(title, ((W - title.width) // 2, int(H * 0.40) - title.height // 2), title)
    ry = int(H * 0.40) + title.height // 2 + 34
    ImageDraw.Draw(logo).rectangle([W // 2 - 280, ry, W // 2 + 280, ry + 6], fill=mc.BLOOD + (255,))
    p1 = os.path.join(dir_, "end_logo.png")
    logo.save(p1)
    tag = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _text(ImageDraw.Draw(tag), (W / 2, ry + 36), "EARN YOUR FREEDOM", _font(66), mc.GOLD_HI + (255,), track=10, stroke=4, anchor_center=True)
    p2 = os.path.join(dir_, "end_tag.png")
    tag.save(p2)
    call = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _text(ImageDraw.Draw(call), (W / 2, ry + 132), "WISHLIST NOW ON STEAM", _font(48), mc.GOLD + (255,), track=8, stroke=3, anchor_center=True)
    p3 = os.path.join(dir_, "end_call.png")
    call.save(p3)
    return p0, p1, p2, p3


# ---------- the edit ----------

class Edit:
    """The cut as it is built: segments, the cards over them, and the cue sheet for the score."""

    def __init__(self):
        self.segs = []
        self.t = 0.0
        self.cards = []         # (png, t0, t1, fade_in, fade_out, drift px)
        self.cues = {"bpm": BPM, "downbeat": 0.0, "acts": [[0.0, "cold"]], "hits": [], "slows": [], "cuts": [], "cards": [], "risers": []}

    def add(self, seg, beats):
        """`seg` for `beats` beats from where the cut has got to; its start (film s)."""
        seg.prepare(FPS)
        n = int(round(beats * BEAT * FPS))
        if seg.src is not None:
            if len(seg.plan) < n:
                last = seg.plan[-1] if seg.plan else (0.0, 1.0)
                seg.plan += [last] * (n - len(seg.plan))
            seg.plan = seg.plan[:n]
        else:
            seg.plan = [None] * n
        t0 = self.t
        if self.segs:
            self.cues["cuts"].append(round(t0, 3))
        self.segs.append(seg)
        self.t += n / FPS
        # The slow motion in it, in film time, for the score to sink under.
        if seg.src is not None:
            sl = None
            for i, (p, q) in enumerate(seg.plan):
                slow = (q - p) * FPS / seg.src.fps < 0.9
                if slow and sl is None:
                    sl = t0 + i / FPS
                if not slow and sl is not None:
                    self.cues["slows"].append([round(sl, 3), round(t0 + i / FPS, 3)])
                    sl = None
            if sl is not None:
                self.cues["slows"].append([round(sl, 3), round(self.t, 3)])
        return t0

    def card(self, png, t0, t1, fade_in=0.3, fade_out=0.4, drift=10, cue=True):
        self.cards.append((png, t0, t1, fade_in, fade_out, drift))
        if cue:
            self.cues["cards"].append(round(t0, 3))

    def act(self, name):
        if self.cues["acts"][-1][1] != name:
            self.cues["acts"].append([round(self.t, 3), name])


def source_time(src, meta, f):
    return (meta["rec0"] + f) / src.fps


def build(srcs, metas, work):
    """The whole cut, beat by beat."""
    cd = os.path.join(work, "cards")
    os.makedirs(cd, exist_ok=True)
    e = Edit()
    have = [b for b in BOUTS if b[0] in srcs]
    # The cold open: a flash-forward, the kill of a big one in the deepest slow motion, cut on
    # the beat after it lands.
    cold = next((k for k in COLD if k in srcs), None)
    if cold:
        src, meta = srcs[cold], metas[cold]
        kt = source_time(src, meta, meta["kill"])
        sp = ed.Speed([(0.0, 0.2)])
        t_in = ed.lead_for(src.fps, FPS, kt, sp, 2 * BEAT)
        t0 = e.add(ed.Segment(src, t_in, kt + 2.0, sp, fade_in=0.15, flash=[2 * BEAT], name="cold"), 4)
        e.cues["hits"].append(round(t0 + 2 * BEAT, 3))
    # Two lines over a heartbeat in the dark.
    p = os.path.join(cd, "t1.png")
    card_center(p, "EVERY CHAMPION OF ROME", 92)
    t0 = e.add(ed.Segment(None, dur=0), 3)
    e.card(p, t0 + 0.15, t0 + 3 * BEAT - 0.35, 0.35, 0.3, 0)
    p = os.path.join(cd, "t2.png")
    card_center(p, "BEGAN AS A SLAVE", 110)
    t0 = e.add(ed.Segment(None, dur=0), 3)
    e.card(p, t0 + 0.1, t0 + 3 * BEAT - 0.3, 0.3, 0.3, 0)
    montage_done = False
    for k, top, line, lead, after, slow in have:
        if k == have[0][0]:
            e.act("rise")
        if k == ACT2:
            e.act("battle")
        if k == MONTAGE_BEFORE and not montage_done:
            montage(e, srcs, metas, cd)
            montage_done = True
        src, meta = srcs[k], metas[k]
        kt = source_time(src, meta, meta["kill"])
        if k == "hydra":
            sp = ed.Speed.ramp(kt, slow, before=0.5, after=1.2, ease=0.35)
            e.act("climax")
            e.cues["risers"].append([round(e.t + max(0.0, (lead - 4) * BEAT), 3), round(e.t + lead * BEAT, 3)])
        else:
            sp = ed.Speed.ramp(kt, slow, before=0.55, after=0.6, ease=0.3)
        lo = source_time(src, meta, meta["from"]) + 0.05
        t_in = max(lo, ed.lead_for(src.fps, FPS, kt, sp, lead * BEAT))
        t_out = source_time(src, meta, meta["kill"] + int(REC_TAIL * REC_FPS)) - 0.05
        seg = ed.Segment(src, t_in, t_out, sp, name=k)
        t0 = e.add(seg, lead + after)
        hit_t = t0 + seg.film_time_of(kt, FPS)
        e.cues["hits"].append(round(hit_t, 3))
        seg.flash = [hit_t - t0]
        p = os.path.join(cd, "bout_%s.png" % k)
        card_bout(p, top, line)
        e.card(p, t0 + 0.35, max(t0 + 1.5, min(t0 + 3.0, hit_t - 1.0)), 0.3, 0.45, 12)
        if k == "recruit" and "forge" in srcs:
            forge(e, srcs, metas, cd)
    if not montage_done:
        montage(e, srcs, metas, cd)
    # The silence, then the title on one great hit.
    e.cues["silence"] = [round(e.t, 3), round(e.t + 2 * BEAT, 3)]
    e.add(ed.Segment(None, dur=0), 2)
    e.cues["final"] = round(e.t, 3)
    bg, logo, tag, call = card_end(cd)
    t0 = e.add(ed.Segment(None, dur=0), 12)
    end = e.t
    e.card(bg, t0, end - 0.9, 0.05, 0.9, 0, cue=False)
    e.card(logo, t0, end - 0.9, 0.12, 0.9, 0, cue=False)
    e.card(tag, t0 + 2 * BEAT, end - 0.9, 0.6, 0.9, 6)
    e.card(call, t0 + 4 * BEAT, end - 0.9, 0.6, 0.9, 6)
    e.cues["length"] = round(e.t, 3)
    return e


def forge(e, srcs, metas, cd):
    """The forge: a weapon going up on the anvil, FORGE YOUR OWN STEEL over it."""
    src, meta = srcs["forge"], metas["forge"]
    t_in = (meta["rec0"] + 6) / src.fps
    t0 = e.add(ed.Segment(src, t_in, t_in + 8.0, ed.Speed([]), fade_in=0.2, fade_out=0.2, shutter=1.0, name="forge"), 6)
    p = os.path.join(cd, "forge.png")
    card_center(p, "FORGE YOUR OWN STEEL", 88, y=int(H * 0.70))
    e.card(p, t0 + 0.5, t0 + 6 * BEAT - 0.3, 0.35, 0.3, 10)


def montage(e, srcs, metas, cd):
    """A cut on every beat: the hardest blows of all the bouts (not their kills), at full speed,
    a flash on every other one, two lines over it."""
    pool = []
    for k, _t, _l, _a, _b, _s in BOUTS:
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
    order = {b[0]: i for i, b in enumerate(BOUTS)}
    picked.sort(key=lambda x: (order.get(x[1], 0), x[2]))
    if len(picked) < 2:
        return
    if len(picked) % 2:
        picked = picked[:-1]
    e.act("climax")
    e.cues["risers"].append([round(max(0.0, e.t - 4 * BEAT), 3), round(e.t, 3)])
    t_start = e.t
    for i, (J, k, f) in enumerate(picked):
        src = srcs[k]
        th = source_time(src, metas[k], f)
        t0 = e.add(ed.Segment(src, th - 0.25, th + 1.0, ed.Speed([]), flash=[0.25] if i % 2 == 0 else [], name="montage"), 1)
        if i % 2 == 0:
            e.cues["hits"].append(round(t0 + 0.25, 3))
    half = len(picked) // 2 * BEAT
    p = os.path.join(cd, "m1.png")
    card_center(p, "EVERY BLOW LANDS", 104)
    e.card(p, t_start + 0.1, t_start + half - 0.2, 0.2, 0.25, 0)
    p = os.path.join(cd, "m2.png")
    card_center(p, "EVERY BONE BREAKS", 104)
    e.card(p, t_start + half + 0.1, e.t - 0.15, 0.2, 0.25, 0)


# ---------- the picture, the sound, the film ----------

GRADE = ("format=gbrp,"
         "curves=r='0/0 0.30/0.27 0.70/0.76 1/1':g='0/0 0.30/0.28 0.70/0.71 1/0.97':b='0/0.035 0.30/0.31 0.70/0.65 1/0.9',"
         "eq=contrast=1.05:saturation=1.07,"
         "vignette=angle=PI/5,"
         "noise=alls=5:allf=t,"
         "rgbashift=rh=1:bh=-1,"
         "drawbox=x=0:y=0:w=iw:h=%d:color=black:t=fill,drawbox=x=0:y=ih-%d:w=iw:h=%d:color=black:t=fill") % (BAR_PX, BAR_PX, BAR_PX)


def picture(e, out):
    """Every frame of the cut to ffmpeg: graded, the cards over it, encoded."""
    total = e.t
    extra, f = [], "[0:v]%s[g0];" % GRADE
    last = "g0"
    for i, (png, t0, t1, fi, fo, drift) in enumerate(e.cards):
        extra.append(["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % total, "-i", png])
        n = i + 1
        f += "[%d:v]format=rgba,fade=t=in:st=%.3f:d=%.3f:alpha=1,fade=t=out:st=%.3f:d=%.3f:alpha=1[c%d];" % (n, t0, fi, t1, fo, n)
        y = "0" if drift == 0 else "'%d*(1-min(1,max(0,(t-%.3f)/0.9)))'" % (drift, t0)
        f += "[%s][c%d]overlay=x=0:y=%s:enable='between(t,%.3f,%.3f)'[g%d];" % (last, n, y, t0, t1 + fo, n)
        last = "g%d" % n
    f += "[%s]format=yuv420p[v]" % last
    enc = ed.encoder(out, W, H, FPS, f, extra)
    done = [0]
    n_all = sum(s.frames for s in e.segs)

    def sink(fr):
        enc.stdin.write(fr.tobytes())
        done[0] += 1
        if done[0] % (FPS * 5) == 0:
            print("    picture %d%%" % (100 * done[0] // max(1, n_all)), flush=True)
    ed.render_picture(e.segs, W, H, FPS, sink)
    enc.stdin.close()
    if enc.wait() != 0:
        sys.exit("the picture's encoding failed")


def sound(e, work, out):
    """The fight's own sound under the score, the score giving way to the blows, at -14 LUFS."""
    import rise_score
    with open(os.path.join(work, "cues.json"), "w") as f:
        json.dump(e.cues, f, indent=1)
    sc = os.path.join(work, "score.wav")
    rise_score.write(sc, rise_score.make(e.cues))
    score = ed.read_wav(sc)
    game = ed.render_sound(e.segs, FPS)
    n = max(len(score), len(game))
    score = np.pad(score, ((0, n - len(score)), (0, 0)))
    game = np.pad(game, ((0, n - len(game)), (0, 0)))
    env = ed.envelope(game)
    duck = 1.0 - 0.45 * np.clip(env / 0.3, 0.0, 1.0)
    mix = np.tanh(game * 1.7) * 0.85 + score * duck[:, None] * 0.8
    raw = os.path.join(work, "mix_raw.wav")
    ed.write_wav(raw, mix / max(1.0, float(np.max(np.abs(mix)))))
    ed.loudnorm(raw, out, -14.0, -1.0)


def film(e, work, out):
    pic = os.path.join(work, "picture.mp4")
    snd = os.path.join(work, "sound.wav")
    print("== the picture (%d frames)" % sum(s.frames for s in e.segs))
    picture(e, pic)
    print("== the sound")
    sound(e, work, snd)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", pic, "-i", snd, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                           "-c:a", "aac", "-b:a", "320k", "-ar", "48000", "-movflags", "+faststart", "-shortest", out])
    with open(os.path.splitext(out)[0] + "_cut.json", "w") as f:
        json.dump({"length": e.t, "segments": [[s.name, s.frames] for s in e.segs], "cues": e.cues}, f, indent=1)
    print("saved %s (%.1f s)" % (out, e.t))


# ---------- made-up footage, to check the whole cut without the game ----------

def fake_sources(work):
    srcs, metas = {}, {}
    for i, b in enumerate(BOUTS + [("forge",)]):
        k = b[0]
        path = os.path.join(work, k + ".avi")
        fps = 30 if k == "forge" else REC_FPS
        if not os.path.exists(path):
            subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=%d:duration=9" % fps,
                                   "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=48000:duration=9" % (220 + 40 * i),
                                   "-c:v", "mjpeg", "-q:v", "4", "-c:a", "pcm_s16le", "-shortest", path])
        srcs[k] = ed.Source(path)
        if k == "forge":
            metas[k] = {"rec0": 0, "end": 270}
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
    except ImportError:
        sys.exit("Pillow is needed: pip install pillow")
    os.makedirs(RTMP, exist_ok=True)
    if fake:
        work = os.path.join(RTMP, "fake")
        os.makedirs(work, exist_ok=True)
        srcs, metas = fake_sources(work)
        e = build(srcs, metas, work)
        film(e, work, os.path.join(work, "trailer_rise_fake.mp4"))
        return
    mt.G = mt.godot()
    print("Godot: %s\nwork dir: %s" % (mt.G, RTMP))
    print("== the project copy")
    project()
    print("== the bouts (each played twice: once to find the kill, once filmed at 120 frames a second)")
    for b in BOUTS:
        record(b[0])
    print("== the forge")
    record_forge()
    srcs, metas = {}, {}
    for k in [b[0] for b in BOUTS] + ["forge"]:
        avi = os.path.join(RTMP, k + ".avi")
        if os.path.exists(avi) and os.path.exists(_meta_path(k)):
            with open(_meta_path(k)) as f:
                metas[k] = json.load(f)
            srcs[k] = ed.Source(avi)
    if not any(b[0] in srcs for b in BOUTS):
        sys.exit("no bout was recorded: see the .dry and .rec files in %s" % RTMP)
    print("== the cut")
    e = build(srcs, metas, RTMP)
    film(e, RTMP, os.path.join(mt.OUT, "trailer_rise.mp4"))


if __name__ == "__main__":
    main()
