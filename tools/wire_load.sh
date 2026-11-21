#!/bin/sh
# What the host sends each guest in the Ludus yard with N men in it (#298): the snapshot rows of the Match's own loop, counted as the engine packs
# them, with the rule of a full room (the players' fighters 40 times a second, the rest every other time).
#   sh tools/wire_load.sh                  8 men walking about, 6 seconds
#   sh tools/wire_load.sh 8 idle 6         (idle | walk | brawl)
#   IDLE=0 sh tools/wire_load.sh 8 idle    the men who stand are not let sleep
# One physics thread and one step to a frame (--fixed-fps 120). Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
mark="; wire_load.sh: one worker thread while it runs (removed after)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
	trap 'rm -f override.cfg' EXIT
	trap 'rm -f override.cfg; exit 130' INT TERM
fi
N=${1:-8} BEHAVIOR=${2:-walk} SECS=${3:-6} "$G" --headless --fixed-fps 120 --path . -- --probe wire298 2>&1 | grep -E "^WIRE|SCRIPT ERROR|PARSE ERROR"
[ $ours -eq 1 ] && rm -f override.cfg
