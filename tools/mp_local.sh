#!/bin/sh
# An online game on one machine: a host window and guest windows over ENet (no Steam needed).
#   sh tools/mp_local.sh              # host + one guest, both played by you
#   sh tools/mp_local.sh 2            # host + two guests
#   BOT=1 sh tools/mp_local.sh        # the guests are played by bots: host, start, and watch
#   LAG=120 LOSS=3 sh tools/mp_local.sh   # pretend a 120 ms (±30) connection losing 3% of packets
#   ROOM=campaign sh tools/mp_local.sh    # a campaign room (the default is the friends' Arena)
# The host window opens on the room's lobby: press ENTER THE YARD (BEGIN BOUT in a campaign room) once the guests are on it.
# For all of it played and checked by the game itself: sh tools/mp_e2e.sh
# Godot: $GODOT, or `godot` on the PATH. Windows users: tools/mp_local.bat.
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
n=${1:-1}
extra=""
[ -n "$LAG" ] && extra="--lag $LAG --loss ${LOSS:-0}"
room="--arena"
[ "$ROOM" = campaign ] && room=""
"$G" --path . --position 40,60 --resolution 1100x650 -- --keep-window --host $room --name Host $extra &
sleep 3
i=1
while [ "$i" -le "$n" ]; do
	bot=""
	[ -n "$BOT" ] && bot="--bot"
	"$G" --path . --position $((60 + i * 420)),$((120 + i * 60)) --resolution 1100x650 -- --keep-window --join 127.0.0.1 --name "Guest $i" $bot $extra &
	i=$((i + 1))
	sleep 1
done
wait
