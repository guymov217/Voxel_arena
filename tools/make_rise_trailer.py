#!/usr/bin/env python3
"""The second trailer: one gladiator's rise, all from just over his right shoulder (tests/
shouldershots.gd). A slave with a stick, then recruits, the big lion, the cyclops, the minotaur,
a troll and at last the hydra: each bout cut from its run-in to the kill, the killing blow in
slow motion, the fight's own sound (the blows, the cries of men and beasts, the crowd) under war
drums made for it (tools/war_drums.py) that build to one great hit on the end card.

    python tools/make_rise_trailer.py          -> docs/store/trailer_rise.mp4

Needs what make_trailer.py needs (Godot 4.7 with a display, ffmpeg with ffprobe, Pillow) and
numpy for the drums. Work files go to <trailer_work>/rise; shots already made are kept."""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_trailer as mt  # noqa: E402

FPS = mt.FPS
RTMP = os.path.join(mt.TMP, "rise")
LEAD, TAIL = 5.0, 2.2          # seconds of the bout before the kill, and after it
SLOW_FROM, SLOW_TO = 0.5, 1.3  # around the kill (s before, s after): played at half speed
SEEDS = ["", "3", "11", "21", "5", "9"]
# The bouts in order, with the two lines over each: the bout's number and what it is.
SHOTS = [
    ("slave", "BOUT I", "A SLAVE WITH A STICK"),
    ("recruit", "BOUT IV", "FIRST BLOOD"),
    ("lion", "BOUT VIII", "THE BIG LION"),
    ("cyclops", "BOUT XVI", "THE CYCLOPS"),
    ("minotaur", "BOUT XXIV", "THE MINOTAUR"),
    ("troll", "BOUT XL", "CHAMPION OF ROME"),
    ("hydra", "BOUT LXIV", "THE HYDRA"),
]
END_S = 5.0


def deaths(lines):
    """(frame, kind, seconds) of each death the probe tagged."""
    out = []
    for l in lines:
        p = l.split()
        if len(p) >= 3 and p[0] == "DEATH":
            out.append((int(p[1]), p[2], float(p[3]) if len(p) > 3 else -1.0))
    return out


def foe_death(lines):
    for f, kind, _t in deaths(lines):
        if kind != "local":
            return f
    return None


def probe_env(k, seed, extra):
    e = {"SHOT": k}
    if seed:
        e["CLIP_SEED"] = seed
    e.update(extra)
    return e


def shot(k):
    """One bout: <rise>/<k>.mp4, the run-in to the kill with its sound, the kill slowed down."""
    out = os.path.join(RTMP, k + ".mp4")
    if os.path.exists(out) and os.path.getsize(out):
        print("  %s: kept" % k)
        return
    # The dry run (nothing drawn, fast): the first seed whose fight ends with the foe dead.
    seed, death = None, None
    for s in SEEDS:
        dry = mt.run([mt.G, "--fixed-fps", str(FPS), "--path", mt.PROJ, "--", "--probe", "shouldershots"],
                     probe_env(k, s, {"CLIP_DRY": "1", "CLIP_SECONDS": "70"}), os.path.join(RTMP, k + ".dry"))
        d = foe_death(dry)
        if d is not None and d > 0:
            seed, death = s, d
            break
        print("  %s: seed %s, the foe did not fall; trying another" % (k, s or "default"))
    if death is None:
        print("  %s: left out (no seed ended with the foe down; see %s)" % (k, os.path.join(RTMP, k + ".dry")))
        return
    start = max(0, death - int(LEAD * FPS))
    frames = os.path.join(RTMP, k)
    if os.path.isdir(frames):
        shutil.rmtree(frames)
    os.makedirs(frames)
    rec = mt.run([mt.G, "--write-movie", os.path.join(frames, "f.png"), "--fixed-fps", str(FPS), "--path", mt.PROJ, "--", "--probe", "shouldershots"],
                 probe_env(k, seed, {"CLIP_FROM": str(start), "CLIP_SECONDS": str(int((death + TAIL * FPS) / FPS) + 3)}),
                 os.path.join(RTMP, k + ".rec"))
    rec0 = mt.tagged(rec, "REC_START") or 0
    d2 = foe_death(rec)
    if d2 is not None and d2 > start:
        death = d2
    stop = death + int(TAIL * FPS)
    last = mt.tagged(rec, "REC_END")
    if last is not None and stop > last:
        stop = last
    ok = encode(frames, rec0 + start, stop - start, death - start, out)
    print("  %s: %.1f s (seed %s)" % (k, mt.duration(out), seed or "default") if ok else "  %s: ffmpeg failed" % k)
    shutil.rmtree(frames, ignore_errors=True)


def encode(frames, first, n, death_rel, out):
    """Frames <frames>/f%08d.png from `first`, `n` of them, and the movie's sound beside them,
    into `out`: up to the blow, the blow at half speed (its sound slowed and deepened with it),
    and the fall after it."""
    dur = n / FPS
    k0 = max(0.0, death_rel / FPS - SLOW_FROM)
    k1 = min(dur, death_rel / FPS + SLOW_TO)
    wav = os.path.join(frames, "f.wav")
    vin = ["-framerate", str(FPS), "-start_number", str(first), "-i", os.path.join(frames, "f%08d.png")]
    ain = ["-ss", "%.3f" % (first / FPS), "-t", "%.3f" % dur, "-i", wav] if os.path.exists(wav) else ["-f", "lavfi", "-t", "%.3f" % dur, "-i", "anullsrc=r=44100:cl=stereo"]
    f = ("[0:v]trim=end_frame=%d,setpts=PTS-STARTPTS,split=3[va][vb][vc];" % n +
         "[va]trim=0:%.3f,setpts=PTS-STARTPTS[v1];[vb]trim=%.3f:%.3f,setpts=2*(PTS-STARTPTS)[v2];[vc]trim=%.3f,setpts=PTS-STARTPTS[v3];" % (k0, k0, k1, k1) +
         "[1:a]aresample=44100,aformat=channel_layouts=stereo,asplit=3[aa][ab][ac];" +
         "[aa]atrim=0:%.3f,asetpts=PTS-STARTPTS[a1];[ab]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,asetrate=44100*0.8,aresample=44100,atempo=0.625[a2];[ac]atrim=%.3f,asetpts=PTS-STARTPTS[a3];" % (k0, k0, k1, k1) +
         "[v1][a1][v2][a2][v3][a3]concat=n=3:v=1:a=1[v][a]")
    return subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + vin + ain +
                          ["-filter_complex", f, "-map", "[v]", "-map", "[a]", "-r", str(FPS),
                           "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", out]).returncode == 0


def cards(shots):
    """The two lines over each bout (its number small, what it is large) and the end card."""
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
    import make_capsules as mc
    W, H = 1920, 1080
    d = os.path.join(RTMP, "cards")
    os.makedirs(d, exist_ok=True)
    big = ImageFont.truetype(mc.FONT, 104)
    small = ImageFont.truetype(mc.FONT, 46)
    out = []
    t = 0.0
    for k, top, line in shots:
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        band = Image.new("L", (W, H), 0)
        ImageDraw.Draw(band).rectangle([0, int(H * 0.70), W, int(H * 0.93)], fill=160)
        band = band.filter(ImageFilter.GaussianBlur(44))
        shade = Image.new("RGBA", (W, H), (8, 5, 3, 255))
        shade.putalpha(band)
        img = Image.alpha_composite(img, shade)
        dr = ImageDraw.Draw(img)
        x = int(W * 0.07)
        dr.text((x, int(H * 0.72)), top, font=small, fill=mc.GOLD + (255,), stroke_width=3, stroke_fill=(20, 12, 6, 255))
        dr.rectangle([x, int(H * 0.72) + 62, x + 220, int(H * 0.72) + 67], fill=mc.BLOOD + (255,))
        dr.text((x, int(H * 0.72) + 80), line, font=big, fill=mc.GOLD_HI + (255,), stroke_width=6, stroke_fill=(20, 12, 6, 255))
        p = os.path.join(d, k + ".png")
        img.save(p)
        dur = mt.duration(os.path.join(RTMP, k + ".mp4"))
        out.append((p, t + 0.2, t + min(2.6, dur - 0.3)))
        t += dur
    # The end: the title over a dark warm glow, a blood rule, the line and the call.
    img = Image.new("RGBA", (W, H), (10, 7, 5, 255))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.2, H * 0.15, W * 0.8, H * 0.85], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    warm = Image.new("RGBA", (W, H), (120, 52, 18, 255))
    warm.putalpha(glow)
    img = Image.alpha_composite(img, warm)
    title = mc.fit(mc.voxel_title(700), int(W * 0.7), 300)
    img.paste(title, ((W - title.width) // 2, int(H * 0.38) - title.height // 2), title)
    dr = ImageDraw.Draw(img)
    ry = int(H * 0.38) + title.height // 2 + 36
    dr.rectangle([W // 2 - 260, ry, W // 2 + 260, ry + 6], fill=mc.BLOOD)
    for i, (txt, sz, col) in enumerate([("EARN YOUR FREEDOM", 64, mc.GOLD_HI), ("Wishlist on Steam", 52, mc.GOLD)]):
        fnt = ImageFont.truetype(mc.FONT, sz)
        dr.text(((W - fnt.getlength(txt)) / 2, ry + 40 + i * 90), txt, font=fnt, fill=col)
    end = os.path.join(d, "end.png")
    img.save(end)
    return out, end, t


def cut(shots):
    overlays, end, t_end = cards(shots)
    total = t_end + END_S
    music = os.path.join(RTMP, "war_drums.wav")
    subprocess.check_call([sys.executable, os.path.join(HERE, "war_drums.py"), music, "%.2f" % total, "%.2f" % t_end])
    inputs, filt, n = [], "", 0
    for k, _a, _b in shots:
        clip = os.path.join(RTMP, k + ".mp4")
        d = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", clip]).decode().strip())
        inputs += ["-i", clip]
        # Each bout comes up out of black and goes back into it: a cut between fights, not a jump.
        filt += ("[%d:v]scale=1920:1080,setsar=1,fps=%d,format=yuv420p,fade=t=in:st=0:d=0.3,fade=t=out:st=%.2f:d=0.35[v%d];"
                 "[%d:a]aresample=44100,aformat=channel_layouts=stereo,afade=t=in:d=0.15,afade=t=out:st=%.2f:d=0.35[a%d];") % (n, FPS, d - 0.35, n, n, d - 0.35, n)
        n += 1
    inputs += ["-loop", "1", "-t", str(END_S), "-i", end, "-f", "lavfi", "-t", str(END_S), "-i", "anullsrc=r=44100:cl=stereo"]
    filt += "[%d:v]scale=1920:1080,setsar=1,fps=%d,format=yuv420p[v%d];[%d:a]anull[a%d];" % (n, FPS, n, n + 1, n)
    filt += "".join("[v%d][a%d]" % (i, i) for i in range(n + 1)) + "concat=n=%d:v=1:a=1[cut][fx];" % (n + 1)
    idx = n + 2
    last = "cut"
    for i, (png, t0, t1) in enumerate(overlays):
        inputs += ["-i", png]
        filt += "[%s][%d:v]overlay=0:0:enable='between(t,%.2f,%.2f)'[o%d];" % (last, idx, t0, t1, i)
        last = "o%d" % i
        idx += 1
    inputs += ["-i", music]
    # The fight's own sound pressed up loud (the cries and the blows), the drums over it.
    # The film look: a warm, hard grade, the corners darkened, and the wide-screen bars of a
    # cinema (2.39:1); the cards ride over the bars as titles do.
    grade = "eq=contrast=1.12:saturation=0.9:gamma=0.97,colorbalance=rs=0.04:gs=0.0:bs=-0.05:rh=0.03:bh=-0.03,vignette=PI/5,drawbox=x=0:y=0:w=iw:h=138:color=black:t=fill,drawbox=x=0:y=ih-138:w=iw:h=138:color=black:t=fill"
    filt = filt.replace("concat=n=%d:v=1:a=1[cut][fx];" % (n + 1), "concat=n=%d:v=1:a=1[cut0][fx];[cut0]%s[cut];" % (n + 1, grade))
    filt += "[%s]format=yuv420p[vout];" % last
    # The fight's own sound pressed up loud (the cries and the blows), the drums over it; the
    # drums give way under every blow and cry (side-chained), so each one lands, then swell back.
    filt += "[fx]acompressor=threshold=0.08:ratio=5:attack=4:release=150,volume=2.2,asplit=2[fxl][key];"
    filt += "[%d:a]volume=0.95[mus0];[mus0][key]sidechaincompress=threshold=0.06:ratio=5:attack=8:release=320:makeup=1[mus];" % idx
    filt += "[fxl][mus]amix=inputs=2:normalize=0:duration=longest,alimiter=limit=0.95,afade=t=in:d=0.4,afade=t=out:st=%.2f:d=1.5[aout]" % (total - 1.5)
    os.makedirs(mt.OUT, exist_ok=True)
    out = os.path.join(mt.OUT, "trailer_rise.mp4")
    ok = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + inputs + ["-filter_complex", filt, "-map", "[vout]", "-map", "[aout]",
                         "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", "%.2f" % total, out]).returncode == 0
    print("saved %s (%.0f s)" % (out, total) if ok else "the final cut failed")


if __name__ == "__main__":
    mt.ffmpeg_on_path()
    mt.need("ffmpeg")
    mt.need("ffprobe")
    try:
        import PIL  # noqa: F401
        import numpy  # noqa: F401
    except ImportError:
        sys.exit("Pillow and numpy are needed: pip install pillow numpy")
    mt.G = mt.godot()
    os.makedirs(RTMP, exist_ok=True)
    print("Godot: %s\nwork dir: %s" % (mt.G, RTMP))
    print("== the project copy")
    mt.fresh_project()
    print("== the bouts")
    for k, _a, _b in SHOTS:
        shot(k)
    made = [s for s in SHOTS if os.path.exists(os.path.join(RTMP, s[0] + ".mp4")) and os.path.getsize(os.path.join(RTMP, s[0] + ".mp4"))]
    if not made:
        sys.exit("no bout was recorded: see the .dry and .rec files in %s" % RTMP)
    print("== the cut")
    cut(made)
