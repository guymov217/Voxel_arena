#!/bin/sh
# All of multiplayer, played out and checked by the game itself: a host and two friends (three games of this project) go
# through every part of it by the game's own screens (tests/e2e_run.gd, e2e_host.gd, e2e_guest.gd) and say what worked.
#   sh tools/mp_e2e.sh                    # without windows, about 5 minutes
#   VISIBLE=1 sh tools/mp_e2e.sh          # in three windows you can watch
#   QUICK=1 sh tools/mp_e2e.sh            # half the time: no tournament, no single modes
#   LAG=120 LOSS=3 sh tools/mp_e2e.sh     # over a pretend poor connection (milliseconds, percent)
# Godot: $GODOT, or `godot` on the PATH. Exit code 0: everything passed. The report: e2e_report.txt.
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
args=""
[ -n "$VISIBLE" ] && args="$args --visible"
[ -n "$QUICK" ] && args="$args --quick"
[ -n "$LAG" ] && args="$args --lag $LAG --loss ${LOSS:-0}"
[ -n "$NET_PORT" ] && args="$args --port $NET_PORT"
exec "$G" --headless --path . -- --probe e2e_run $args
