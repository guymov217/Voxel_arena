#!/bin/sh
# What the host's steps cost with a full room of friends in the yard (#298): this game opens an Arena room, brings in friends'
# games (headless games of this project, each played by FriendPilot: they wander the yard, go into the stalls, pick a quarrel now
# and then), enters the yard and measures its own steps for a while. All on this one machine, so the friends' games take the host's
# CPU as they would not in a room of computers; the steps' wall time is of the nodes' steps alone (what the engine's own step and the
# waiting for the next are not in it), as the clock would pace them to 8.3 ms whatever they cost.
#   sh tools/friends_load.sh                7 friends, 60 seconds
#   sh tools/friends_load.sh 4 30           4 friends, 30 seconds
#   IDLE=0 ARM_LOD=0 sh tools/friends_load.sh    the two ways of sparing the host off (Match.human_idle_on, Fighter.arm_lod_on)
# Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
FRIENDS=${1:-7} SECS=${2:-60} "$G" --headless --path . -- --probe friends_load298 --port ${NET_PORT:-17960} 2>&1 | grep -E "^FRIENDS|SCRIPT ERROR|PARSE ERROR"
