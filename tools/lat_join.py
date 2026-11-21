#!/usr/bin/env python3
"""What the host sees of a guest's man: joins the PRESS lines the guest probe prints (tests/net_lat_guest.gd) with the MOVED lines
the host probe prints (tests/net_lat_host.gd), both stamped with the system clock, and says how long it was from the key going
down on the guest to his man being 2 cm on in the host's game.

    python3 tools/lat_join.py host.log guest.log [--max-gap MS]

--max-gap: exit 1 when the guest's swing is more than that many ms behind (or ahead of) the host's own (NET_OWN on the host).
"""
import re
import sys

host = open(sys.argv[1]).read()
guest = open(sys.argv[2]).read()
moved = [float(m.group(2)) for m in re.finditer(r"^MOVED (\d+) ([0-9.]+)", host, re.M)]
press = [float(m.group(2)) for m in re.finditer(r"^PRESS (\d+) ([0-9.]+)", guest, re.M)]
d = []
for p in press:
    c = [m for m in moved if p < m < p + 1.5]
    if c:
        d.append((c[0] - p) * 1000.0)
d.sort()
if d:
    print("key down on the guest -> his man 2 cm on in the host's game, %d presses: min %.0f median %.0f mean %.0f worst %.0f ms"
          % (len(d), d[0], d[len(d) // 2], sum(d) / len(d), d[-1]))
else:
    print("no pairs (%d moves, %d presses)" % (len(moved), len(press)))

# The hands: the PRESS of a swing on the guest (HPRESS) to his weapon's being 3 cm on in the host's physics (HMOVED); with NET_OWN on the host,
# the host's own swing (OWN, in his own game) is what it is to be as quick as.
hmoved = [float(m.group(2)) for m in re.finditer(r"^HMOVED (\d+) ([0-9.]+)", host, re.M)]
hpress = [float(m.group(2)) for m in re.finditer(r"^HPRESS (\d+) ([0-9.]+)", guest, re.M)]
hd = []
for p in hpress:
    c = [m for m in hmoved if p < m < p + 2.0]
    if c:
        hd.append((c[0] - p) * 1000.0)
hd.sort()
if hd:
    print("a swing: key down on the guest -> his weapon 3 cm on in the host's physics, %d swings: min %.0f median %.0f mean %.0f worst %.0f ms"
          % (len(hd), hd[0], hd[len(hd) // 2], sum(hd) / len(hd), hd[-1]))
own = [float(m.group(1)) for m in re.finditer(r"^OWN \d+ ([0-9.]+) ms", host, re.M)]
own.sort()
if own:
    print("a swing: the host's own, his key down -> his weapon 3 cm on in the physics, %d swings: min %.0f median %.0f worst %.0f ms"
          % (len(own), own[0], own[len(own) // 2], own[-1]))
    if hd:
        print("   the guest is %+.0f ms behind the host" % (hd[len(hd) // 2] - own[len(own) // 2]))

if len(sys.argv) > 4 and sys.argv[3] == "--max-gap":
    limit = float(sys.argv[4])
    if not (hd and own):
        print("FAIL: no swings to compare (guest %d, host %d)" % (len(hd), len(own)))
        sys.exit(1)
    gap = hd[len(hd) // 2] - own[len(own) // 2]
    if abs(gap) > limit:
        print("FAIL: the guest's swing is %+.0f ms from the host's, over %.0f" % (gap, limit))
        sys.exit(1)
