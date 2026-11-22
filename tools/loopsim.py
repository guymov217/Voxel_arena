#!/usr/bin/env python3
"""A model of the game's main loop (#298l): frames, physics steps, the engine's cap on the steps of a frame, the host governor (Net.overload_*), vsync, on a core `k` times as
fast as the one the figures were measured on. For comparing ways of sparing the host (and what a computer of this kind or that would get), not for predicting one machine.

Per frame: the steps owed (the engine's accumulator, 120 a second, what the frame before took) are played up to the cap (4; 2 while the governor says the host is over its
budget), each costing a draw from a log-normal fitted to a measured median and 99th percentile of a step; then the frame's own work; the frame ends at the later of the vsync
interval and the work done. What the cap does not let be played is dropped, as the engine drops it: the game runs slow. Game speed = steps played a second / 120.
"The fighters in a process of their own" (decoupled): their steps run on a core of their own (120 a second if they cost under 8.33 ms on the average, else as fast as they
come) and the picture is drawn on another at the vsync interval or its own work, whichever is longer.

Checked against real-time runs on one core (tests/mix298.gd, RT=1, `taskset -c`): 9 fighters 118 steps and 52 frames a second measured, 120 and 53-59 modelled; 17 fighters,
the engine's cap of 4: 51 steps and 13 frames measured, 48-51 and 12-13 modelled; with the governor 51 and 21 measured while it settled, 46-49 and 23-25 modelled.
Within 10-15% of the frame rate and nearer on the steps; the ORDER of the ways is more to be trusted than their figures.

    python3 tools/loopsim.py              the table: 6, 8 and 12 fighters in armour, four kinds of computer, the ways of sparing the host

The costs a step and a frame take (ms, at k = 1; the figures of the README's "What is left to spare" section):
  a step of N armoured fighters all fighting: median 10.2 ms x (0.4 + 1.3 (N-1)) / 9.5 (the 8-man brawl of tests/lobby298.gd), x 0.9 for the release build, 99th percentile 1.62 x median;
  bare: / 1.19 (armour is 19% of a step: tests/lobby298.gd walking, ARMOR=1 against 0);
  a frame: the scripts' drawing 0.41 ms a fighter in armour, 0.24 bare (tests/frame298.gd), the engine's own on the processor 0.44 a fighter in armour, 0.30 bare (assumed from
  the draw calls tests/render298.gd counts; read the real figure off F3's "drawing")."""
import math, random, sys

STEP_DT = 1000.0 / 120.0


def lognorm_params(median, p99):
    sigma = math.log(p99 / median) / 2.326
    return math.log(median), sigma


def simulate(step_median, step_p99, frame_ms, k=1.0, cap_normal=4, cap_over=2, governor=True, vsync_ms=1000.0 / 60.0,
             seconds=20.0, seed=1, c_rt=1.0, decoupled=False, frame_jitter=0.1):
    """-> (frames a second, steps a second, game speed %, frame rate of the worst 1% of frames, mean frame ms). `c_rt`: what a step costs in a row of them against alone (0.9: a
    little less)."""
    rnd = random.Random(seed)
    mu, sg = lognorm_params(step_median * c_rt / k, step_p99 * c_rt / k)
    if decoupled:
        mean_s = math.exp(mu + sg * sg / 2.0)
        sim_rate = min(120.0, 1000.0 / mean_s)
        f_eff = max(vsync_ms, frame_ms / k)
        return 1000.0 / f_eff, sim_rate, 100.0 * sim_rate / 120.0, 1000.0 / f_eff, f_eff
    t = 0.0
    acc = 0.0
    last_dt = vsync_ms
    steps = frames = 0
    smooth = step_median * c_rt / k
    over_looks = 0
    over = False
    frame_times = []
    while t < seconds * 1000.0:
        cap = cap_over if (governor and over) else cap_normal
        owed = acc + last_dt
        due = int(owed // STEP_DT)
        acc = owed - due * STEP_DT
        n = min(cap, due)
        cost = 0.0
        for _ in range(n):
            s = rnd.lognormvariate(mu, sg)
            cost += s
            smooth = 0.9 * smooth + 0.1 * s
        dt = max(vsync_ms, cost + frame_ms / k * (1.0 + (rnd.random() - 0.5) * frame_jitter))
        last_dt = dt
        steps += n
        frames += 1
        frame_times.append(dt)
        t += dt
        if governor:
            if smooth >= 8.6:
                over_looks += 1
                if over_looks >= 2:
                    over = True
            elif smooth <= 7.8:
                over_looks = 0
                over = False
    fs = sorted(frame_times)
    mean = sum(fs) / len(fs)
    return 1000.0 / mean, steps / (t / 1000.0), 100.0 * steps / (t / 1000.0) / 120.0, 1000.0 / fs[int(len(fs) * 0.99)], mean


KS = [("weak laptop (k 0.8)", 0.8), ("average (k 1.15)", 1.15), ("good mid (k 1.5)", 1.5), ("13600KF (k 2.0)", 2.0)]


def step_median(n, armoured=True, release=0.9):
    base = (0.4 + 1.3 * (n - 1)) / (0.4 + 1.3 * 7) * 10.2 * release
    return base * (1.0 if armoured else 1 / 1.19)


def frame_ms(n, armoured=True, cut=0.0):
    return (0.41 if armoured else 0.24) * n + (0.44 if armoured else 0.30) * n - cut * n / 8.0


def run(n, k, step_mult=1.0, frame_cut=0.0, decoupled=False, armoured=True, seeds=5):
    fs, ss = [], []
    for seed in range(1, seeds + 1):
        m = step_median(n, armoured) * step_mult
        fps, _, spd, _, _ = simulate(m, m * 1.62, frame_ms(n, armoured, frame_cut), k=k, c_rt=0.92, decoupled=decoupled, seed=seed)
        fs.append(fps)
        ss.append(spd)
    return sum(fs) / len(fs), sum(ss) / len(ss)


WAYS = [
    ("no armour at all (the price of armour: this row against the next)", dict(armoured=False)),
    ("as it is, in armour", dict()),
    ("armour fixes: the step's keep-out in a pack (-6% step), the frame's clipping native (-0.7 ms)", dict(step_mult=0.94, frame_cut=0.7)),
    ("armour fixes + the ports of the pieces left (-8% step more)", dict(step_mult=0.94 * 0.92, frame_cut=0.7)),
    ("all of control in C++ (-40% step) + the armour frame fix", dict(step_mult=0.6, frame_cut=0.7)),
    ("the fighters in a process of their own", dict(decoupled=True)),
    ("own process + the armour fixes", dict(decoupled=True, step_mult=0.94, frame_cut=0.7)),
    ("own process + all of control in C++", dict(decoupled=True, step_mult=0.6, frame_cut=0.7)),
]


if __name__ == "__main__":
    for n in (6, 8, 12):
        print("\n%d fighters, all fighting; frames a second / game speed (%% of real time)" % n)
        print("%-86s" % "" + "".join("%-22s" % k[0] for k in KS))
        for label, kw in WAYS:
            row = "%-86s" % label
            for _, k in KS:
                fps, spd = run(n, k, **kw)
                row += "%4.0f fps / %3.0f%%       " % (fps, spd)
            print(row)
