#!/usr/bin/env python3
"""The launch trailer from the game itself, on any machine with a display (tools/make_trailer.sh
is the same for a Linux box without one): bot fights cut round their best moment (tests/clipshots.gd),
the forge building a weapon (tests/forgeclip.gd), the game's own boss music under it all
(tests/musicbed.gd), title cards over the cuts and the logo at the end. Needs Godot 4.7, ffmpeg
(with ffprobe) and Pillow. With a GPU it takes 20-40 minutes; shots already made are kept, so a
run that stopped carries on where it was.

    python tools/make_trailer.py            -> docs/store/trailer.mp4
    GODOT=D:\\godot\\Godot_v4.7.2-stable_win64_console.exe (or godot on the PATH)
    TRAILER_TMP=<work dir>  (default: a "trailer_work" folder beside the project)"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FPS = 30
OUT = os.path.join(ROOT, "docs", "store")
TMP = os.environ.get("TRAILER_TMP") or os.path.join(os.path.dirname(ROOT), "trailer_work")
PROJ = os.path.join(TMP, "project")
SHOTS = [("gorilla", 4, 1), ("duel", 4, 1), ("elephant", 3, 1), ("cyclops", 3, 1), ("bear", 3, 1), ("chicken", 4, 1)]
ORDER = ["gorilla", "forge", "duel", "elephant", "cyclops", "bear", "chicken"]


def godot():
    g = os.environ.get("GODOT")
    if g:
        return g
    for name in ("godot", "godot4", "Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"):
        p = shutil.which(name)
        if p:
            return p
    if os.path.exists("/opt/godot/Godot_v4.7.2-stable_linux.x86_64"):
        return "/opt/godot/Godot_v4.7.2-stable_linux.x86_64"
    sys.exit("Godot not found: set GODOT to the Godot 4.7 executable (the *_console.exe on Windows), or put godot on the PATH")


def need(tool):
    if not shutil.which(tool):
        sys.exit("%s not found on the PATH: install it (ffmpeg comes with ffprobe)" % tool)


def run(args, env=None, log=None):
    """Runs Godot or ffmpeg, prints nothing of theirs; returns the lines that start with a tag."""
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.run(args, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    lines = [l.strip() for l in p.stdout.splitlines()]
    if log:
        with open(log, "w") as f:
            f.write("\n".join(lines))
    return lines


def tagged(lines, tag):
    for l in lines:
        if l.startswith(tag + " "):
            return int(l.split()[1])
    return None


def fresh_project():
    """A copy of the project with the window forced to 1920x1080 and one worker thread (the same
    frames every run), so the real project is never touched."""
    if os.path.isdir(PROJ):
        shutil.rmtree(PROJ)
    shutil.copytree(ROOT, PROJ, ignore=shutil.ignore_patterns(".git", "store", "trailer_work", ".godot", "*.mp4"))
    with open(os.path.join(PROJ, "override.cfg"), "w") as f:
        f.write("[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n[threading]\nworker_pool/max_threads=1\n")
    # (The project's imports, so the first Godot run does not spend its frames importing.)
    run([G, "--headless", "--path", PROJ, "--import"])


def shot(k, lead, tail):
    """One fight, cut to `lead` seconds before its first death and `tail` after: TMP/<k>.mp4."""
    out = os.path.join(TMP, k + ".mp4")
    if os.path.getsize(out) if os.path.exists(out) else 0:
        print("  %s: kept" % k)
        return
    dry = run([G, "--fixed-fps", str(FPS), "--path", PROJ, "--", "--probe", "clipshots"],
              {"CLIP": k, "CLIP_DRY": "1", "CLIP_SECONDS": "60"}, os.path.join(TMP, k + ".dry"))
    death = tagged(dry, "DEATH")
    if death is None:
        death = tagged(dry, "REC_END")
    if death is None:
        print("  %s: the dry run failed (see %s)" % (k, os.path.join(TMP, k + ".dry")))
        return
    start = max(0, death - lead * FPS)
    stop = death + tail * FPS
    frames = os.path.join(TMP, k)
    if os.path.isdir(frames):
        shutil.rmtree(frames)
    os.makedirs(frames)
    rec = run([G, "--write-movie", os.path.join(frames, "f.png"), "--fixed-fps", str(FPS), "--path", PROJ, "--", "--probe", "clipshots"],
              {"CLIP": k, "CLIP_FROM": str(start), "CLIP_SECONDS": str((stop + FPS) // FPS + 1)}, os.path.join(TMP, k + ".rec"))
    rec0 = tagged(rec, "REC_START") or 0
    d2 = tagged(rec, "DEATH")
    if d2 is not None and d2 > start:
        stop = d2 + tail * FPS
    last = tagged(rec, "REC_END")
    if last is not None and stop > last:
        stop = last
    first = rec0 + start
    ok = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-framerate", str(FPS), "-start_number", str(first),
                         "-i", os.path.join(frames, "f%08d.png"), "-frames:v", str(stop - start),
                         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-an", out]).returncode == 0
    print("  %s: %d s" % (k, (stop - start) // FPS) if ok else "  %s: ffmpeg failed" % k)
    shutil.rmtree(frames, ignore_errors=True)


def forge():
    out = os.path.join(TMP, "forge.mp4")
    if os.path.exists(out) and os.path.getsize(out):
        print("  forge: kept")
        return
    frames = os.path.join(TMP, "forge")
    if os.path.isdir(frames):
        shutil.rmtree(frames)
    os.makedirs(frames)
    rec = run([G, "--write-movie", os.path.join(frames, "f.png"), "--fixed-fps", str(FPS), "--path", PROJ, "--", "--probe", "forgeclip"],
              {"FORGE_SECONDS": "4"}, os.path.join(TMP, "forge.rec"))
    f0, f1 = tagged(rec, "REC_START"), tagged(rec, "REC_END")
    if f0 is None or f1 is None:
        print("  forge: the recording failed (see %s)" % os.path.join(TMP, "forge.rec"))
        return
    ok = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-framerate", str(FPS), "-start_number", str(f0),
                         "-i", os.path.join(frames, "f%08d.png"), "-frames:v", str(f1 - f0),
                         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-an", out]).returncode == 0
    print("  forge: %d s" % ((f1 - f0) // FPS) if ok else "  forge: ffmpeg failed")
    shutil.rmtree(frames, ignore_errors=True)


def music():
    out = os.path.join(TMP, "music.wav")
    if os.path.exists(out) and os.path.getsize(out):
        print("  music: kept")
        return
    d = os.path.join(TMP, "music")
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    run([G, "--write-movie", os.path.join(d, "f.png"), "--fixed-fps", str(FPS), "--resolution", "640x360", "--path", PROJ, "--", "--probe", "musicbed"],
        {"MUSIC_SECONDS": "45"})
    wav = os.path.join(d, "f.wav")
    if os.path.exists(wav):
        shutil.copy(wav, out)
        print("  music: 45 s")
    else:
        print("  music: no wav came out")
    shutil.rmtree(d, ignore_errors=True)


def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).decode().strip())


def cut():
    subprocess.check_call([sys.executable, os.path.join(HERE, "trailer_cards.py"), TMP])
    inputs, filt, n = [], "", 0
    shots = [s for s in ORDER if os.path.exists(os.path.join(TMP, s + ".mp4")) and os.path.getsize(os.path.join(TMP, s + ".mp4"))]
    for s in shots:
        inputs += ["-i", os.path.join(TMP, s + ".mp4")]
        filt += "[%d:v]scale=1920:1080,setsar=1,fps=%d[v%d];" % (n, FPS, n)
        n += 1
    inputs += ["-loop", "1", "-t", "4", "-i", os.path.join(TMP, "cards", "end.png")]
    filt += "[%d:v]scale=1920:1080,setsar=1,fps=%d,format=yuv420p[v%d];" % (n, FPS, n)
    filt += "".join("[v%d]" % i for i in range(n + 1)) + "concat=n=%d:v=1:a=0[cut];" % (n + 1)
    last, k = "cut", 0
    with open(os.path.join(TMP, "cards", "cards.txt")) as f:
        for line in f:
            png, t0, t1 = line.split()
            inputs += ["-i", os.path.join(TMP, "cards", png)]
            idx = n + 1 + k
            filt += "[%s][%d:v]overlay=0:0:enable='between(t,%s,%s)'[o%d];" % (last, idx, t0, t1, k)
            last = "o%d" % k
            k += 1
    inputs += ["-i", os.path.join(TMP, "music.wav")]
    aidx = n + 1 + k
    total = sum(duration(os.path.join(TMP, s + ".mp4")) for s in shots) + 4
    filt += "[%s]format=yuv420p[vout];[%d:a]atrim=0:%s,afade=t=in:d=0.5,afade=t=out:st=%s:d=2[aout]" % (last, aidx, total, total - 2)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "trailer.mp4")
    ok = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + inputs + ["-filter_complex", filt, "-map", "[vout]", "-map", "[aout]",
                         "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", str(total), out]).returncode == 0
    print("saved %s (%.0f s)" % (out, total) if ok else "the final cut failed")


if __name__ == "__main__":
    need("ffmpeg")
    need("ffprobe")
    try:
        import PIL  # noqa: F401
    except ImportError:
        sys.exit("Pillow not found: pip install pillow")
    G = godot()
    os.makedirs(TMP, exist_ok=True)
    print("Godot: %s\nwork dir: %s" % (G, TMP))
    print("== the project copy")
    fresh_project()
    print("== fights")
    for k, lead, tail in SHOTS:
        shot(k, lead, tail)
    print("== the forge")
    forge()
    print("== the music")
    music()
    print("== the cut")
    cut()
