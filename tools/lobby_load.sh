#!/bin/sh
# What the host's physics steps cost in the Ludus yard with N men in it (#298: the more men, the slower a room), and a fingerprint
# of every man at the end: two builds that print the same LOBBYHASH played it the same way, to the last bit.
#   sh tools/lobby_load.sh                  8 men walking about, 6 seconds
#   sh tools/lobby_load.sh 4 idle 10        4 men standing, 10 seconds        (idle | walk | brawl)
#   ARM_LOD=0 IDLE=0 sh tools/lobby_load.sh 8 walk     the two ways of sparing the host off (Fighter.arm_lod_on, Match.human_idle_on)
#   NONPC=1 SNAP=0 sh tools/lobby_load.sh 8 walk       for the fingerprint: the yard's keepers sent away (their idle ways differ from run to run)
#   ARMOR=0 MAIN=spear OFF= sh tools/lobby_load.sh     bare men with a spear (ARMOR=1: helmet, lorica, manica, greaves; MAIN, OFF: the hands)
# One physics thread and one step to a frame (--fixed-fps 120), so the steps' wall time is what they cost and a run comes out the same
# every time. Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
mark="; lobby_load.sh: one worker thread while it runs (removed after)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
	trap 'rm -f override.cfg' EXIT
	trap 'rm -f override.cfg; exit 130' INT TERM
fi
N=${1:-8} BEHAVIOR=${2:-walk} SECS=${3:-6} "$G" --headless --fixed-fps 120 --path . -- --probe lobby298 2>&1 | grep -E "^men:|^LOBBY|^STAND|^   SPLIT|^   ENT|SCRIPT ERROR|PARSE ERROR"
[ $ours -eq 1 ] && rm -f override.cfg
