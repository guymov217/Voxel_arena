#!/usr/bin/env python3
"""How far a guest's picture of another man is from where that man is by the time a blow of the guest's lands: the host's probe
(tests/net_lat_host.gd, NET_TGT) logs the host's own man walking to and fro, the guest's (tests/net_lat_guest.gd, NET_TGT_ONLY) logs what
his screen shows of him, both with the system clock. Says how far behind the host the picture is (the shift that fits it best), and how
far it is from where the man is one way of the line on (the guest's input reaching the host: half his ping), in cm, while the man walks.

    python3 tools/lat_tgt.py host.log guest.log [shift_ms] [--max-mean-cm N] [--max-shift-ms N]
        (shift_ms: how far on the blow lands, default half the guest's ping; the limits make it exit 1 when the picture is worse)
"""
import bisect
import math
import re
import sys

import argparse
ap = argparse.ArgumentParser()
ap.add_argument("host")
ap.add_argument("guest")
ap.add_argument("shift_ms", nargs="?", type=float, default=None)
ap.add_argument("--max-mean-cm", type=float, default=None, help="fail when the picture is off by more than this on average while he walks")
ap.add_argument("--max-shift-ms", type=float, default=None, help="fail when the picture is further behind the host's than this")
args = ap.parse_args()
host = open(args.host).read()
guest = open(args.guest).read()
H = [(float(a), float(b), float(c)) for a, b, c in re.findall(r"^TGT_H ([0-9.]+) (-?[0-9.]+) (-?[0-9.]+)", host, re.M)]
G = [(float(a), float(b), float(c)) for a, b, c in re.findall(r"^TGT_G ([0-9.]+) (-?[0-9.]+) (-?[0-9.]+)", guest, re.M)]
pm = re.search(r"^TGT_PING (-?[0-9.]+)", guest, re.M)
ping = float(pm.group(1)) if pm else 0.0
ahead = args.shift_ms / 1000.0 if args.shift_ms is not None else max(0.0, ping) / 2000.0
if len(H) < 100 or len(G) < 100:
    print("too few samples (host %d, guest %d)" % (len(H), len(G)))
    sys.exit(1)
HT = [h[0] for h in H]


def hpos(t):
    """The host's man at the time t (linear between his steps), None outside what was logged."""
    i = bisect.bisect_left(HT, t)
    if i <= 0 or i >= len(H):
        return None
    a, b = H[i - 1], H[i]
    k = (t - a[0]) / max(1e-9, b[0] - a[0])
    return (a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k)


def hvel(t):
    a, b = hpos(t - 0.03), hpos(t + 0.03)
    if a is None or b is None:
        return None
    return ((b[0] - a[0]) / 0.06, (b[1] - a[1]) / 0.06)


# The shift that fits best: his picture at t is where the host's man was at t - s.
best = None
for s_ms in range(-120, 301):
    s = s_ms / 1000.0
    tot = 0.0
    n = 0
    for t, x, z in G:
        q = hpos(t - s)
        if q is None:
            continue
        tot += math.hypot(x - q[0], z - q[1])
        n += 1
    if n > 50 and (best is None or tot / n < best[1]):
        best = (s_ms, tot / n)
print("his picture of the host's man is %+d ms behind the host's (best fit; mean off by %.1f cm), ping %.0f ms" % (best[0], best[1] * 100.0, ping))

# Where his blow meets the man: the host's man `ahead` seconds on, while he walks (more than half a metre a second).
errs = []
along = []
for t, x, z in G:
    q = hpos(t + ahead)
    v = hvel(t + ahead)
    if q is None or v is None:
        continue
    sp = math.hypot(v[0], v[1])
    if sp < 0.5:
        continue
    errs.append(math.hypot(x - q[0], z - q[1]))
    # along his way: negative is behind where he will be, positive is past it
    along.append(((x - q[0]) * v[0] + (z - q[1]) * v[1]) / sp)
errs.sort()
along.sort()
if errs:
    print("a blow landing %.0f ms on, the man walking: the picture is off by mean %.1f cm, 90%% within %.1f cm, worst %.1f cm (%d samples)"
          % (ahead * 1000.0, sum(errs) / len(errs) * 100.0, errs[int(len(errs) * 0.9)] * 100.0, errs[-1] * 100.0, len(errs)))
    print("   along his way: behind by up to %.1f cm, past by up to %.1f cm (median %+.1f cm)"
          % (max(0.0, -along[int(len(along) * 0.02)]) * 100.0, max(0.0, along[int(len(along) * 0.98)]) * 100.0, along[len(along) // 2] * 100.0))

# When he stops: how far the picture runs on past where he stops (the host's final place), along the way he was going, in the half second after.
over = []
i = 0
times = [h[0] for h in H]
while i < len(H) - 1:
    t = H[i][0]
    v = hvel(t)
    if v is not None and math.hypot(v[0], v[1]) < 0.12:
        before = hvel(t - 0.35)
        if before is not None and math.hypot(before[0], before[1]) > 1.0:
            sp = math.hypot(before[0], before[1])
            d = (before[0] / sp, before[1] / sp)
            fin = hpos(t + 0.25)
            if fin is not None:
                ex = [((x - fin[0]) * d[0] + (z - fin[1]) * d[1]) for gt, x, z in G if t - 0.1 <= gt <= t + 0.6]
                if ex:
                    over.append(max(ex))
            i = bisect.bisect_left(HT, t + 0.8)
            continue
    i += 1
if over:
    print("   he stops (%d times): the picture runs past where he stops by mean %.1f cm, at most %.1f cm"
          % (len(over), sum(over) / len(over) * 100.0, max(over) * 100.0))

bad = []
if args.max_shift_ms is not None and best[0] > args.max_shift_ms:
    bad.append("the picture is %+d ms behind the host's (over %.0f)" % (best[0], args.max_shift_ms))
if args.max_mean_cm is not None and (not errs or sum(errs) / len(errs) * 100.0 > args.max_mean_cm):
    bad.append("the picture is off by %.1f cm on average while he walks (over %.1f)" % ((sum(errs) / len(errs) * 100.0) if errs else -1.0, args.max_mean_cm))
if bad:
    print("FAIL: " + "; ".join(bad))
    sys.exit(1)
