#!/usr/bin/env python3
"""The trailer's editor (tools/make_rise_trailer.py drives it): cuts recorded game footage into a
finished picture and sound, frame by frame, the way a cutting room does.

The game is recorded at 120 frames a second (a frame for every physics step), so the editor has
four times the frames it needs for a 30 fps film and uses them:
- motion blur: each film frame is the blend of the game frames its shutter was open for (a 180
  degree shutter: two of every four at full speed), as a film camera blurs a swung blade;
- speed ramps: the speed eases down into a slow motion and back up out of it, and the slow motion
  is smooth (every game frame shown, a quarter speed with no frame shown twice);
- the sound follows the picture exactly: slowed with it, its pitch falling as on film, muffled
  under the slow motion.

The picture goes out to ffmpeg as raw frames; ffmpeg grades it, lays the titles over it and
encodes it. Needs numpy, and ffmpeg/ffprobe on the PATH.

    python tools/trailer_edit.py --selftest <work dir>   (a quick check with made-up footage)"""
import json
import math
import os
import subprocess
import sys

import numpy as np

AR = 48000                       # the sound's rate throughout


def probe(path):
    """fps, width, height, duration of a recording."""
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                   "stream=width,height,r_frame_rate:format=duration", "-of", "json", path])
    j = json.loads(out)
    st = j["streams"][0]
    num, den = st["r_frame_rate"].split("/")
    return float(num) / float(den), int(st["width"]), int(st["height"]), float(j["format"]["duration"])


class Source:
    """A recording: its frames read in order from any frame on, its sound whole."""

    def __init__(self, path):
        self.path = path
        self.fps, self.w, self.h, self.dur = probe(path)
        self.frames = int(round(self.dur * self.fps))
        self._audio = None

    def reader(self, first, w, h):
        """Frames from `first` on, scaled to w x h, as uint8 arrays."""
        args = ["ffmpeg", "-v", "error", "-ss", "%.6f" % (max(0, first) / self.fps), "-i", self.path,
                "-an", "-vf", "scale=%d:%d:flags=lanczos" % (w, h), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=w * h * 3 * 4)
        size = w * h * 3
        try:
            while True:
                b = p.stdout.read(size)
                if len(b) < size:
                    break
                yield np.frombuffer(b, np.uint8).reshape(h, w, 3)
        finally:
            p.stdout.close()
            p.kill()
            p.wait()

    def audio(self):
        """The recording's sound, stereo float at AR (silence if it has none)."""
        if self._audio is None:
            try:
                raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", self.path, "-vn", "-ac", "2", "-ar", str(AR),
                                               "-f", "f32le", "-"])
                a = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
            except subprocess.CalledProcessError:
                a = np.zeros((0, 2), np.float32)
            n = int(self.dur * AR)
            if len(a) < n:
                a = np.concatenate([a, np.zeros((n - len(a), 2), np.float32)])
            self._audio = a
        return self._audio


class Speed:
    """The speed of the picture along a shot, by the shot's own clock (seconds into the source):
    keys [(t, speed)], eased between them (smoothstep), held before the first and after the last."""

    def __init__(self, keys):
        self.keys = sorted(keys) if keys else [(0.0, 1.0)]

    def at(self, t):
        k = self.keys
        if t <= k[0][0]:
            return k[0][1]
        for (t0, s0), (t1, s1) in zip(k, k[1:]):
            if t <= t1:
                u = (t - t0) / max(1e-9, t1 - t0)
                u = u * u * (3 - 2 * u)
                return s0 + (s1 - s0) * u
        return k[-1][1]

    @staticmethod
    def ramp(kill, slow=0.25, before=0.55, after=0.9, ease=0.3):
        """Full speed, easing down into `slow` `before` s ahead of `kill`, back up `after` s past it."""
        return Speed([(kill - before - ease, 1.0), (kill - before, slow), (kill + after, slow), (kill + after + ease, 1.0)])


def frame_plan(src_fps, out_fps, t_in, t_out, speed):
    """Where each film frame comes from: [(p, q)] in source frames, from t_in to t_out (source
    seconds), as fast as `speed` says."""
    plan = []
    p = t_in * src_fps
    end = t_out * src_fps
    while p < end - 1e-6:
        s = speed.at(p / src_fps)
        step = max(0.02, s) * src_fps / out_fps
        plan.append((p, p + step))
        p += step
    return plan


def seconds_until(src_fps, out_fps, t_in, t_at, speed):
    """How long the film runs from source time t_in until it reaches t_at."""
    return len(frame_plan(src_fps, out_fps, t_in, t_at, speed)) / out_fps


def lead_for(src_fps, out_fps, t_at, speed, want, lo=0.5, hi=12.0):
    """The source time to start from so that `t_at` comes `want` film seconds in."""
    for _ in range(40):
        mid = (lo + hi) / 2
        if seconds_until(src_fps, out_fps, t_at - mid, t_at, speed) < want:
            lo = mid
        else:
            hi = mid
    return t_at - (lo + hi) / 2


class Segment:
    """A piece of the film: a run of a shot (`src`), or black (`src` None) for `dur` seconds.
    fade_in/fade_out: from and to black (s); flash: film times (s, from the segment's start) of a
    white frame that dies away; shutter: the part of each film frame the shutter is open (0.5)."""

    def __init__(self, src=None, t_in=0.0, t_out=0.0, speed=None, dur=0.0, fade_in=0.0, fade_out=0.0,
                 flash=(), shutter=0.5, gain=1.0, muffle_slow=True, name=""):
        self.src, self.t_in, self.t_out = src, t_in, t_out
        self.speed = speed or Speed([])
        self.fade_in, self.fade_out = fade_in, fade_out
        self.flash = list(flash)
        self.shutter = shutter
        self.gain = gain
        self.muffle_slow = muffle_slow
        self.name = name
        self.plan = None
        self.black = dur

    def prepare(self, out_fps):
        if self.src is not None:
            self.plan = frame_plan(self.src.fps, out_fps, self.t_in, self.t_out, self.speed)
        else:
            self.plan = [None] * int(round(self.black * out_fps))
        return self

    @property
    def frames(self):
        return len(self.plan)

    def duration(self, out_fps):
        return self.frames / out_fps

    def film_time_of(self, t_src, out_fps):
        """When, in film seconds from the segment's start, source time t_src is shown."""
        f = t_src * self.src.fps
        for i, (p, q) in enumerate(self.plan):
            if q > f:
                return i / out_fps
        return len(self.plan) / out_fps


def _blend(cache, base, a, b):
    """The blend of source frames over [a, b) (frame units), each weighted by its overlap."""
    if b - a < 1.0:
        # Under one frame: between the two nearest, by where the shutter's middle falls.
        m = (a + b) / 2 - 0.5
        i = int(math.floor(m))
        u = m - i
        f0 = cache.get(i - base) if i >= base else cache.get(0)
        f1 = cache.get(i + 1 - base)
        if f1 is None or u < 0.04:
            return f0.astype(np.float32)
        if f0 is None:
            return f1.astype(np.float32)
        return f0.astype(np.float32) * (1 - u) + f1.astype(np.float32) * u
    acc = None
    tot = 0.0
    i = int(math.floor(a))
    while i < b:
        w = min(b, i + 1) - max(a, i)
        f = cache.get(i - base)
        if f is not None and w > 0:
            acc = f.astype(np.float32) * w if acc is None else acc + f.astype(np.float32) * w
            tot += w
        i += 1
    return acc / tot if acc is not None else None


class _Cache:
    """The frames of a shot kept while they may still be wanted (the plan only moves forward)."""

    def __init__(self, reader):
        self.reader = reader
        self.frames = []
        self.offset = 0
        self.done = False

    def get(self, k):
        if k < self.offset:
            return self.frames[0] if self.frames else None
        while not self.done and k - self.offset >= len(self.frames):
            try:
                self.frames.append(next(self.reader))
            except StopIteration:
                self.done = True
        j = k - self.offset
        if j < len(self.frames):
            return self.frames[j]
        return self.frames[-1] if self.frames else None

    def drop_before(self, k):
        n = k - self.offset
        if n > 0:
            del self.frames[:n]
            self.offset = k


def render_picture(segments, w, h, fps, sink):
    """Every film frame of `segments`, in order, to sink(frame uint8 HxWx3)."""
    black = np.zeros((h, w, 3), np.uint8)
    for seg in segments:
        if seg.src is None:
            for _ in range(seg.frames):
                sink(black)
            continue
        first = int(math.floor(seg.plan[0][0])) if seg.plan else 0
        cache = _Cache(seg.src.reader(first, w, h))
        n = seg.frames
        for i, (p, q) in enumerate(seg.plan):
            a = p
            b = p + max((q - p) * seg.shutter, min(1.0, q - p))
            f = _blend(cache, first, a, b)
            if f is None:
                f = black.astype(np.float32)
            t = i / fps
            k = 1.0
            if seg.fade_in > 0 and t < seg.fade_in:
                k = min(k, t / seg.fade_in)
            tl = (n - 1 - i) / fps
            if seg.fade_out > 0 and tl < seg.fade_out:
                k = min(k, tl / seg.fade_out)
            if k < 1.0:
                f = f * (k * k * (3 - 2 * k))
            for ft in seg.flash:
                d = t - ft
                if 0 <= d < 0.25:
                    a_ = (1.0 - d / 0.25) ** 2 * 0.85
                    f = f * (1 - a_) + 255.0 * a_
            sink(np.clip(f, 0, 255).astype(np.uint8))
            cache.drop_before(int(math.floor(p)) - first - 1)


def _lowpass(x, cutoff):
    X = np.fft.rfft(x, axis=0)
    fr = np.fft.rfftfreq(len(x), 1.0 / AR)
    X *= (1.0 / (1.0 + (fr / cutoff) ** 4))[:, None]
    return np.fft.irfft(X, len(x), axis=0)


def render_sound(segments, fps):
    """The film's own sound (the game's): each segment's run through its time map (slowed with
    the picture, the pitch falling), muffled under slow motion, faded with the picture."""
    parts = []
    for seg in segments:
        n = int(round(seg.frames / fps * AR))
        if seg.src is None or n == 0:
            parts.append(np.zeros((n, 2), np.float32))
            continue
        src = seg.src.audio()
        # Source frame at each film frame's start, then at every sample between.
        ps = np.array([p for p, _ in seg.plan] + [seg.plan[-1][1]], np.float64)
        ft = np.arange(len(ps)) / fps
        ts = np.arange(n) / AR
        pos = np.interp(ts, ft, ps) / seg.src.fps * AR
        pos = np.clip(pos, 0, len(src) - 2)
        i = pos.astype(np.int64)
        u = (pos - i)[:, None]
        out = src[i] * (1 - u) + src[i + 1] * u
        speed = np.interp(ts, ft[:-1], [(q - p) * fps / seg.src.fps for p, q in seg.plan])
        if seg.muffle_slow and np.min(speed) < 0.9:
            low = _lowpass(out, 600.0)
            k = np.clip((0.95 - speed) / 0.5, 0, 1)[:, None]
            out = out * (1 - k) + low * k * 1.25
        env = np.ones(n)
        fi = int(seg.fade_in * AR)
        fo = int(seg.fade_out * AR)
        if fi > 0:
            env[:fi] = np.linspace(0, 1, fi)
        if fo > 0:
            env[-fo:] = np.minimum(env[-fo:], np.linspace(1, 0, fo))
        parts.append((out * env[:, None] * seg.gain).astype(np.float32))
    return np.concatenate(parts) if parts else np.zeros((0, 2), np.float32)


def envelope(x, attack=0.005, release=0.25):
    """A follower of how loud x is (for the music to give way under the fight's blows)."""
    a = np.abs(x).max(axis=1)
    # Block-wise peaks, then a smoothing that rises fast and falls slow.
    blk = 240
    nb = len(a) // blk + 1
    pk = np.zeros(nb)
    for b in range(nb):
        s = a[b * blk:(b + 1) * blk]
        pk[b] = s.max() if len(s) else 0.0
    ra = math.exp(-blk / (attack * AR))
    rr = math.exp(-blk / (release * AR))
    e = np.zeros(nb)
    v = 0.0
    for b in range(nb):
        x_ = pk[b]
        v = x_ + (v - x_) * (ra if x_ > v else rr)
        e[b] = v
    return np.repeat(e, blk)[:len(a)]


def write_wav(path, x):
    import wave
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(AR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    import wave
    with wave.open(path) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        a = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, ch).astype(np.float32) / 32768.0
    if ch == 1:
        a = np.repeat(a, 2, axis=1)
    if sr != AR:
        n = int(len(a) * AR / sr)
        t = np.arange(n) * sr / AR
        a = np.stack([np.interp(t, np.arange(len(a)), a[:, c]) for c in range(2)], axis=1).astype(np.float32)
    return a


def loudnorm(inp, out, target=-14.0, tp=-1.0):
    """Two passes of ffmpeg's loudnorm: the whole mix to `target` LUFS, peaks under `tp` dBTP."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", inp, "-af",
                        "loudnorm=I=%.1f:TP=%.1f:LRA=11:print_format=json" % (target, tp), "-f", "null", "-"],
                       stderr=subprocess.PIPE, text=True, errors="replace")
    txt = r.stderr
    j = json.loads(txt[txt.rfind("{"):txt.rfind("}") + 1])
    f = ("loudnorm=I=%.1f:TP=%.1f:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true"
         % (target, tp, j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"]))
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", inp, "-af", f + ",aresample=%d" % AR, "-c:a", "pcm_s16le", out])


def encoder(out, w, h, fps, vf, extra_inputs=(), crf=16):
    """An ffmpeg that takes raw frames on stdin, filters them (`vf`, a filter_complex whose input is
    [0:v] and whose output is [v]) and writes `out` (picture only)."""
    args = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h), "-r", str(fps), "-i", "-"]
    for x in extra_inputs:
        args += list(x)
    args += ["-filter_complex", vf, "-map", "[v]", "-c:v", "libx264", "-preset", "slow", "-crf", str(crf),
             "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", str(fps), out]
    return subprocess.Popen(args, stdin=subprocess.PIPE)


# ---------- the self-test: made-up footage through the whole editor ----------

def _fake_shot(path, secs=6.0, fps=120, size="480x270"):
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=%s:rate=%d:duration=%.2f" % (size, fps, secs),
                           "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=%.2f" % secs,
                           "-c:v", "mjpeg", "-q:v", "3", "-c:a", "pcm_s16le", "-shortest", path])


def selftest(work):
    os.makedirs(work, exist_ok=True)
    a = os.path.join(work, "a.avi")
    _fake_shot(a)
    src = Source(a)
    assert abs(src.fps - 120) < 0.5, src.fps
    out_fps = 30
    sp = Speed.ramp(4.0)
    t_in = lead_for(src.fps, out_fps, 4.0, sp, 2.5)
    segs = [Segment(None, dur=0.5), Segment(src, t_in, 5.8, sp, fade_in=0.2, fade_out=0.3, flash=[2.5])]
    for s in segs:
        s.prepare(out_fps)
    kill_at = segs[1].film_time_of(4.0, out_fps)
    assert abs(kill_at - 2.5) < 0.05, kill_at
    w, h = 320, 180
    v = os.path.join(work, "pic.mp4")
    enc = encoder(v, w, h, out_fps, "[0:v]format=yuv420p[v]")
    count = [0]

    def sink(f):
        enc.stdin.write(f.tobytes())
        count[0] += 1
    render_picture(segs, w, h, out_fps, sink)
    enc.stdin.close()
    enc.wait()
    total = sum(s.frames for s in segs)
    assert count[0] == total, (count[0], total)
    snd = render_sound(segs, out_fps)
    assert abs(len(snd) / AR - total / out_fps) < 0.01
    wav = os.path.join(work, "snd.wav")
    write_wav(wav, snd * 0.5)
    print("selftest ok: %d frames, %.2f s, the kill at %.2f s, slow motion %.1f s of source in %.1f s of film"
          % (total, total / out_fps, kill_at, 0.55 + 0.9, seconds_until(src.fps, out_fps, 4.0 - 0.55, 4.0 + 0.9, sp)))


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--selftest":
        selftest(sys.argv[2])
    else:
        print(__doc__)
