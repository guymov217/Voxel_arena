#!/usr/bin/env python3
"""What the host sees of a guest's man: joins the PRESS lines the guest probe prints (tests/net_lat_guest.gd) with the MOVED lines
the host probe prints (tests/net_lat_host.gd), both stamped with the system clock, and says how long it was from the key going
down on the guest to his man being 2 cm on in the host's game.

    python3 tools/lat_join.py host.log guest.log
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
