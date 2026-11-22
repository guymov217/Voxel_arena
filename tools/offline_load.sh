#!/bin/sh
# What a fight of N costs offline (#298): the player's man (an autopilot) and N-1 bots in a free for all, as the game starts a solo fight, headless;
# the same eight as a room's (tools/net_load.sh) so that offline and online can be set side by side: the steps' cost, the steps a second the game
# really takes (of the 120 it is meant to) and the frames a second.
#   sh tools/offline_load.sh                      8 fighters, 12 seconds, as fast as the machine goes
#   sh tools/offline_load.sh 8 12 60              ... at 60 frames a second at most (a window's vsync)
#   CPUS=0 sh tools/offline_load.sh               the game on core 0 only (taskset), as HOST_CPUS=0 does for the room (tools/net_load.sh)
#   LAB=1 sh tools/offline_load.sh                one step to a frame on one physics thread (--fixed-fps 120): what a step costs
# The room's eight to set it against: NET_BOTS=0 HOST_CPUS=0 GUEST_CPUS=1-3 NET_MODE=ffa NET_FPS=60 sh tools/net_load.sh 7 14
# Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
N=${1:-8}; SECS=${2:-12}; FPS=${3:-0}
pin=""
if [ -n "$CPUS" ] && command -v taskset >/dev/null 2>&1; then pin="taskset -c $CPUS"; fi
if [ -n "$LAB" ]; then
	mark="; offline_load.sh: one worker thread while it runs (removed after)"
	ours=0
	if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
		printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
		ours=1
		trap 'rm -f override.cfg' EXIT
		trap 'rm -f override.cfg; exit 130' INT TERM
	fi
	OFF_BOTS=$((N - 1)) OFF_SECS=$SECS OFF_FPS=$FPS $pin "$G" --headless --fixed-fps 120 --path . -- --probe offline_load 2>&1 | grep -E "^OFFLINE|SCRIPT ERROR|PARSE ERROR"
	[ $ours -eq 1 ] && rm -f override.cfg
else
	OFF_BOTS=$((N - 1)) OFF_SECS=$SECS OFF_FPS=$FPS $pin "$G" --headless --path . -- --probe offline_load 2>&1 | grep -E "^OFFLINE|SCRIPT ERROR|PARSE ERROR"
fi
