#!/bin/sh
# What a step costs with a given mix on the sand (#298): men, the campaign's foes, beasts and great foes, as the endless arena's party waves and the
# campaign's bouts bring them (the host's own man stands apart, so each run has one on the sand more than it says).
#   sh tools/mix_load.sh "men:8,foe:8" "men:4,foe:4"       one run (one Godot) for each mix
# men:N bots on the players' side, foe:N the campaign's armoured men, beast:KEY or beast:KEY*N (wolf, lion, hydra, ...), great:KEY (cyclops, giant, ...).
# One physics thread and one step to a frame (--fixed-fps 120), so the steps' wall time is what they cost. Godot: $GODOT, or `godot` on the PATH.
#   RT=1 sh tools/mix_load.sh "men:8,foe:8"                real time instead (no --fixed-fps; 60 frames a second at most, the men's drawing on, one core
#                                                          when there is `taskset`: CPU=n picks it): how many of the 120 steps a second the game takes and how
#                                                          many frames a second it draws (WARM=6 seconds to settle, SECS=10 measured). PACE=0 leaves out the two
#                                                          steps a frame of a host over its budget (`Net.overload_on`), CAP=n sets the engine's own cap (4).
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
mark="; mix_load.sh: one worker thread while it runs (removed after)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
	trap 'rm -f override.cfg' EXIT
	trap 'rm -f override.cfg; exit 130' INT TERM
fi
pin=""
if [ "$RT" = "1" ] && command -v taskset >/dev/null 2>&1; then
	pin="taskset -c ${CPU:-0}"
fi
for mix in "$@"; do
	if [ "$RT" = "1" ]; then
		MIX="$mix" WARM=${WARM:-6} SECS=${SECS:-10} $pin "$G" --headless --path . -- --probe mix298 2>&1 | grep -E "^MIXRT|SCRIPT ERROR|PARSE ERROR"
	else
		MIX="$mix" "$G" --headless --fixed-fps 120 --path . -- --probe mix298 2>&1 | grep -E "^MIX|SCRIPT ERROR|PARSE ERROR"
	fi
done
[ $ours -eq 1 ] && rm -f override.cfg
