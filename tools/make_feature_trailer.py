#!/usr/bin/env python3
"""WRECKSMITH - the trailer: the game's features one by one, made from the game itself on your PC.

Every scene shows one thing the game does, with its line over it, and nothing in it is left to
chance (tests/featureshots.gd): the men stand where they are put, every blow is scripted the way
a player's mouse drives it and lands where the plan says, and the camera moves as the scene
was planned. (The crowd trailer before it filmed bots fighting it out: two men hugging, blows
into the air, a lion scene where nothing happened. User: start it again from nothing.)

  the arena    the champion walks out of the dark of the gate into the light and the roar; the
               stands on their feet, the Emperor in his box raising his hand: THE EMPEROR IS
               WATCHING
  the control  four swings at a man with a shield as the player plays them (the game's own
               camera and HUD), the mouse's path drawn in the corner: EVERY SWING IS YOURS
  the damage   an axe through a raised arm in the slowest motion: STEEL CUTS WHERE IT LANDS; a
               hammer knocking the plates off a cuirass blow by blow: ARMOUR DENTS, CRACKS AND
               FALLS; a mace on both shins, the man fighting on from the sand: BONES BREAK. MEN
               FIGHT ON.
  the foes     a lion takes a man down: BEASTS; three men charge a troll and one sweep throws
               them all: GIANTS; the dragon's fire across the sand: MONSTERS OF LEGEND
  the tools    fire, poison and thunder pots among a band of men: FIRE. POISON. THUNDER.; the
               forge: FORGE YOUR OWN WEAPONS / VOXEL BY VOXEL; a blade for a forearm: LOSE A
               HAND. GAIN A BLADE.
  the others   four friends, their names over their heads, their blows into the minotaur at once:
               BRING YOUR FRIENDS / ONLINE CO-OP
  as played    the hammer, the mace, the blade arm and the friends again, through the player's
               own camera with the HUD over it, a beat and a half each: ALL OF IT IN THE GAME
  the climax   the hydra's last head coming down onto the champion's blade, in the slowest motion
               of all, cut to black on the blow
  the title    a breath of silence, then the logo over the champion alone in the middle, his
               axe raised to the crowd: COMING SOON TO STEAM, WISHLIST NOW

Each scene is recorded once at 120 frames a second (so the slow motion is smooth and the full
speed has a film camera's motion blur), in the game's own look at its best; five of them a
second time as played (POV_SCENES). Cut to its own
score (90 bpm, tools/rise_score.py), the game's own sound under it; graded warm and hard, with
cinema bars; the sound brought to -14 LUFS.

    python tools/make_feature_trailer.py          -> docs/store/trailer_features.mp4 (1920x1080, 30 fps)
    TRAILER_FPS=60                                -> the same at 60 frames a second
    python tools/make_feature_trailer.py --fake   -> the whole cut from made-up footage (a check)

Needs Godot 4.7 with a display, ffmpeg (with ffprobe), Pillow and numpy. Work files go to
<trailer_work>/feature; scenes already made are kept (delete one's .avi to make it again)."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_trailer as mt  # noqa: E402
import make_rise_trailer as rt  # noqa: E402
import make_blood_trailer as bt  # noqa: E402
import trailer_edit as ed  # noqa: E402

FPS, W, H = rt.FPS, rt.W, rt.H
BEAT = rt.BEAT
REC_FPS = rt.REC_FPS
WORK = os.path.join(mt.TMP, "feature")
# The scenes of tests/featureshots.gd, in the order they are recorded.
SCENES = ["gate", "crowd", "swing", "cut", "armour", "bones", "lion", "troll", "dragon", "pots",
          "blade", "friends", "hydra", "finale"]
# The scenes recorded a second time as they are played: through the game's own camera behind the
# champion, its HUD over it (POV=1; <scene>_pov). User: parts that are really gameplay, from the
# player's eyes.
POV_SCENES = ["swing", "armour", "bones", "blade", "friends"]


def record_scene(k, pov=False):
    """One scene: <feature>/<k>.avi and <k>.json (where it starts, its moment, its end, its
    blows), recorded once; with `pov`, as played (<k>_pov: the game's camera and HUD)."""
    name = k + "_pov" if pov else k
    avi = os.path.join(WORK, name + ".avi")
    meta = os.path.join(WORK, name + ".json")
    if os.path.exists(avi) and os.path.getsize(avi) and os.path.exists(meta):
        print("  %s: kept" % name)
        return
    env = {"SCENE": k, "POV": "1"} if pov else {"SCENE": k}
    rec = mt.run([mt.G, "--write-movie", avi, "--fixed-fps", str(REC_FPS), "--path", mt.PROJ, "--", "--probe", "featureshots"],
                 env, os.path.join(WORK, name + ".rec"))
    f0, f1 = mt.tagged(rec, "REC_START"), mt.tagged(rec, "REC_END")
    if f0 is None or f1 is None or not os.path.exists(avi):
        print("  %s: the recording failed (see %s)" % (name, os.path.join(WORK, name + ".rec")))
        if os.path.exists(avi):
            os.remove(avi)
        return
    key = mt.tagged(rec, "KEY")
    hits = sorted({(int(p[1]), int(p[2])) for p in (l.split() for l in rec) if len(p) >= 3 and p[0] == "HIT"})
    with open(meta, "w") as f:
        json.dump({"rec0": f0, "end": f1, "key": key, "hits": [list(h) for h in hits]}, f)
    print("  %s: recorded%s" % (name, "" if key is None else " (its moment %.1f s in)" % (key / REC_FPS)))


# ---------- the edit ----------

def scene(e, srcs, metas, k, beats, start=0.0, key_beat=None, slow=None, flash=False, fade_in=0.0, fade_out=0.0, after=1.0):
    """Scene `k` for `beats` beats: from `start` s into it, or with its moment on beat
    `key_beat` (eased into `slow` motion there when given, for `after` s of the scene past it; a
    white flash on it when `flash`). Its start in the film, and its moment's (or None)."""
    src, meta = srcs[k], metas[k]
    first = (meta["rec0"] + 2) / src.fps
    t_in = first + start
    sp = ed.Speed([])
    kt = None
    if key_beat is not None and meta.get("key") is not None:
        kt = (meta["rec0"] + meta["key"]) / src.fps
        if slow:
            sp = ed.Speed.ramp(kt, slow, before=0.15, after=after, ease=0.2)
            t_in = max(first, ed.lead_for(src.fps, FPS, kt, sp, key_beat * BEAT))
        else:
            t_in = max(first, kt - key_beat * BEAT)
    t_out = (meta["rec0"] + meta["end"]) / src.fps - 0.02
    seg = ed.Segment(src, t_in, t_out, sp, fade_in=fade_in, fade_out=fade_out, name=k)
    t0 = e.add(seg, beats)
    hit = None
    if kt is not None:
        hit = t0 + seg.film_time_of(kt, FPS)
        e.cues["hits"].append(round(hit, 3))
        if flash:
            seg.flash = [hit - t0]
    return t0, hit


def line(e, cd, name, title, sub, t0, t1, size=64, y=None):
    """The scene's line over it: gold Roman capitals spaced wide (bt.card_line)."""
    p = os.path.join(cd, name + ".png")
    bt.card_line(p, title, sub, size, y)
    e.card(p, t0, t1, 0.35, 0.35, 10)


def build(srcs, metas, work):
    """The whole cut, beat by beat."""
    cd = os.path.join(work, "cards")
    os.makedirs(cd, exist_ok=True)
    e = rt.Edit()
    have = lambda k: k in srcs  # noqa: E731
    # Out of the dark: the gate, over the heartbeat; then the stands and the Emperor.
    if have("gate"):
        scene(e, srcs, metas, "gate", 7, fade_in=1.2)
    else:
        e.add(ed.Segment(None, dur=0), 3)
    e.act("rise")
    if have("crowd"):
        t0, _h = scene(e, srcs, metas, "crowd", 5)
        line(e, cd, "l_emperor", "THE EMPEROR IS WATCHING", None, t0 + 1.0, t0 + 5 * BEAT - 0.25)
    # The control: four swings as the player plays them (the game's camera and HUD), the mouse's
    # path in the corner.
    sw = "swing_pov" if have("swing_pov") else "swing"
    if have(sw):
        t0, _h = scene(e, srcs, metas, sw, 9, start=0.25)
        line(e, cd, "l_swing", "EVERY SWING IS YOURS", "THE BLADE GOES WHERE YOUR HAND GOES", t0 + 0.3, t0 + 9 * BEAT - 0.3, 60, H * 0.12)
    e.act("battle")
    # The damage: the cut in the slowest motion, the armour, the bones.
    if have("cut"):
        t0, hit = scene(e, srcs, metas, "cut", 6, key_beat=2, slow=0.15, flash=True)
        at = hit if hit is not None else t0 + 2 * BEAT
        line(e, cd, "l_cut", "STEEL CUTS WHERE IT LANDS", None, at + 0.2, t0 + 6 * BEAT - 0.25)
    if have("armour"):
        # (Four blows, the last in slow motion: the plates flying off it.)
        t0, _h = scene(e, srcs, metas, "armour", 8, key_beat=6, slow=0.4, after=0.6)
        line(e, cd, "l_armour", "ARMOUR DENTS, CRACKS AND FALLS", None, t0 + 0.4, t0 + 8 * BEAT - 0.3)
    if have("bones"):
        # (Both shins, the second slowed a moment; then at full speed, down and fighting on from
        # the sand: slowed a whole second, the scene ended on him falling.)
        t0, hit = scene(e, srcs, metas, "bones", 8, key_beat=3, slow=0.3, after=0.35)
        at = hit if hit is not None else t0 + 3 * BEAT
        line(e, cd, "l_bones", "BONES BREAK. MEN FIGHT ON.", None, at + 0.3, t0 + 8 * BEAT - 0.25)
    # The foes.
    if have("lion"):
        t0, hit = scene(e, srcs, metas, "lion", 6, key_beat=3, slow=0.35)
        line(e, cd, "l_beasts", "BEASTS", "LIONS, BEARS, BULLS, CROCODILES", t0 + 0.3, t0 + 6 * BEAT - 0.25)
    if have("troll"):
        t0, hit = scene(e, srcs, metas, "troll", 7, key_beat=3, slow=0.35)
        line(e, cd, "l_giants", "GIANTS", None, (hit or t0 + 3 * BEAT) + 0.3, t0 + 7 * BEAT - 0.25, 72)
    if have("dragon"):
        t0, _h = scene(e, srcs, metas, "dragon", 6, key_beat=1.5)
        line(e, cd, "l_monsters", "MONSTERS OF LEGEND", None, t0 + 0.4, t0 + 6 * BEAT - 0.25)
    # The tools: the pots, the forge, the physician's blade.
    if have("pots"):
        # (From the first pot: on the thunder two beats in, the fire and the vitriol were before
        # the scene began.)
        t0, _h = scene(e, srcs, metas, "pots", 8, key_beat=5)
        line(e, cd, "l_pots", "FIRE. POISON. THUNDER.", None, t0 + 0.4, t0 + 8 * BEAT - 0.25)
    if "forge" in srcs:
        src, meta = srcs["forge"], metas["forge"]
        t_in = (meta["rec0"] + 3) / src.fps
        t0 = e.add(ed.Segment(src, t_in, t_in + 8.0, ed.Speed([]), fade_in=0.15, shutter=1.0, name="forge"), 6)
        line(e, cd, "l_forge", "FORGE YOUR OWN WEAPONS", "VOXEL BY VOXEL", t0 + 0.4, t0 + 6 * BEAT - 0.3)
    if have("blade"):
        # (Its three cuts: the moment is the last, the first is two and a half seconds before.)
        t0, _h = scene(e, srcs, metas, "blade", 7, key_beat=4, slow=0.3)
        line(e, cd, "l_blade", "LOSE A HAND. GAIN A BLADE.", None, t0 + 0.3, t0 + 7 * BEAT - 0.25)
    # The others: friends.
    if have("friends"):
        t0, _h = scene(e, srcs, metas, "friends", 7, key_beat=3, slow=0.35)
        line(e, cd, "l_friends", "BRING YOUR FRIENDS", "ONLINE CO-OP", t0 + 0.3, t0 + 7 * BEAT - 0.3, 64, H * 0.17)
    # As it is played: the hammer, the mace, the blade arm and the four friends again, through
    # the player's own camera with the HUD over it, a beat and a half each, each blow on a beat.
    took = [k for k in ("armour_pov", "bones_pov", "blade_pov", "friends_pov") if have(k)]
    if took:
        m0 = e.t
        for k in took:
            scene(e, srcs, metas, k, 1.5, key_beat=0.75)
        line(e, cd, "l_played", "ALL OF IT IN THE GAME", "AS YOU PLAY IT", m0 + 0.2, e.t - 0.2, 56, H * 0.12)
    # The climax: the hydra's head onto his blade, in the slowest motion of all, cut to black on it.
    e.act("climax")
    if have("hydra"):
        e.cues["risers"].append([round(e.t, 3), round(e.t + 4 * BEAT, 3)])
        scene(e, srcs, metas, "hydra", 8, key_beat=6, slow=0.12, flash=True)
    # A breath of silence, then the title on one great hit, over the champion alone.
    e.cues["silence"] = [round(e.t, 3), round(e.t + 2 * BEAT, 3)]
    e.add(ed.Segment(None, dur=0), 2)
    e.cues["final"] = round(e.t, 3)
    dark, logo, line_, call = bt.card_end(cd)
    if have("finale"):
        t0, _h = scene(e, srcs, metas, "finale", 12, fade_out=1.0)
    else:
        t0 = e.add(ed.Segment(None, dur=0), 12)
    end = e.t
    e.card(dark, t0, end - 1.0, 0.1, 0.9, 0, cue=False)
    e.card(logo, t0, end - 1.0, 0.12, 0.9, 0, cue=False)
    e.card(line_, t0 + 2 * BEAT, end - 1.0, 0.6, 0.9, 6)
    e.card(call, t0 + 4 * BEAT, end - 1.0, 0.6, 0.9, 6)
    e.cues["length"] = round(e.t, 3)
    return e


# ---------- made-up footage, to check the whole cut without the game ----------

def fake_sources(work):
    srcs, metas = {}, {}
    for i, k in enumerate(SCENES + [p + "_pov" for p in POV_SCENES] + ["forge"]):
        path = os.path.join(work, k + ".avi")
        fps = 30 if k == "forge" else REC_FPS
        if not os.path.exists(path):
            subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=%d:duration=9" % fps,
                                   "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=48000:duration=9" % (220 + 30 * i),
                                   "-c:v", "mjpeg", "-q:v", "4", "-c:a", "pcm_s16le", "-shortest", path])
        srcs[k] = ed.Source(path)
        if k == "forge":
            metas[k] = {"rec0": 0, "end": 270}
        else:
            metas[k] = {"rec0": 0, "end": int(8.5 * REC_FPS), "key": int(3.0 * REC_FPS), "hits": []}
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
    # The rise trailer's recorder (its forge), pointed at this trailer's own work folder.
    rt.RTMP = WORK
    os.makedirs(WORK, exist_ok=True)
    if fake:
        work = os.path.join(WORK, "fake")
        os.makedirs(work, exist_ok=True)
        srcs, metas = fake_sources(work)
        e = build(srcs, metas, work)
        rt.film(e, work, os.path.join(work, "trailer_fake.mp4"))
        return
    mt.G = mt.godot()
    print("Godot: %s\nwork dir: %s" % (mt.G, WORK))
    mt.fresh(WORK)
    print("== the project copy")
    rt.project()
    print("== the scenes (each recorded once at 120 frames a second)")
    for k in SCENES:
        record_scene(k)
    print("== the scenes as played (the game's camera and HUD)")
    for k in POV_SCENES:
        record_scene(k, pov=True)
    print("== the forge")
    os.environ["FORGE_CINE"] = "1"
    rt.record_forge()
    srcs, metas = {}, {}
    for k in SCENES + [p + "_pov" for p in POV_SCENES] + ["forge"]:
        avi = os.path.join(WORK, k + ".avi")
        meta = os.path.join(WORK, k + ".json")
        if os.path.exists(avi) and os.path.exists(meta):
            with open(meta) as f:
                metas[k] = json.load(f)
            srcs[k] = ed.Source(avi)
    if not srcs:
        sys.exit("no scene was recorded: see the .rec files in %s" % WORK)
    print("== the cut")
    e = build(srcs, metas, WORK)
    rt.film(e, WORK, os.path.join(mt.OUT, "trailer_features.mp4"))


if __name__ == "__main__":
    main()
