#!/bin/sh
# Try multiplayer by yourself: one window of the game as the host of a room, and friends who are not there. They are games of
# this project opened without a window, which join your room as a friend's game would and play: they walk the yard, go into
# the stalls, quarrel with whoever is near, fight as bots do, pick their rewards and vote. Over the game, top right:
#   F6 (+)  a friend comes in      F7 (-)  the newest says goodbye and goes
#   F8 (x)  the newest one's line goes at once (a game that crashes)      F9 (~)  the next friends come over a poor line
#   sh tools/mp_playtest.sh              # the friends' Arena (the room opens on its lobby: ENTER THE YARD when you like)
#   ROOM=campaign sh tools/mp_playtest.sh    # a campaign room
#   YARD=1 sh tools/mp_playtest.sh       # straight into the yard, and the friends come in after you
# Godot: $GODOT, or `godot` on the PATH. Windows users: multiplayer_playtest.bat.
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
room="--arena"
[ "$ROOM" = campaign ] && room=""
yard=""
[ -n "$YARD" ] && yard="--yard"
exec "$G" --path . --position 40,60 --resolution 1280x720 -- --keep-window --host $room $yard --playtest --name "${NAME:-You}"
