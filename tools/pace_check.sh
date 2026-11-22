#!/bin/sh
# Does the way the engine shares the physics steps out among frames change the game (#298)? The same fight (bots and the campaign's armoured men, seed 7) for exactly
# STEPS physics steps, then a fingerprint of every body, played four ways: a step to a frame (--fixed-fps 120); in real time on one core with four steps a frame (the
# engine's own cap: PACE=0), with two (CAP=2) and with the governor (Net.overload_on: two while the host cannot keep up). Equal fingerprints: the fight came out the same
# whichever way the frames shared the steps.
#   sh tools/pace_check.sh                     8 bots, 6 armoured men, 720 steps (15 on the sand)
#   STEPS=1200 MEN=8 FOES=8 EVERY=60 sh tools/pace_check.sh      a longer, bloodier one, with a fingerprint every 60 steps (PHASH lines): the same for the first
#                                              960 steps; after that the runs of every mode part, two runs of one mode too (README: "The same fight, however the frames share the steps")
# One physics thread (override.cfg while it runs), and one core for the real-time runs when there is `taskset` (CPU=n picks it). Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
mark="; pace_check.sh: one worker thread while it runs (removed after)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
	trap 'rm -f override.cfg' EXIT
	trap 'rm -f override.cfg; exit 130' INT TERM
fi
pin=""
if command -v taskset >/dev/null 2>&1; then
	pin="taskset -c ${CPU:-0}"
fi
export STEPS=${STEPS:-720} MEN=${MEN:-8} FOES=${FOES:-6}
echo "$MEN bots and $FOES armoured men, $STEPS steps:"
play() {   # play LABEL ENV... : one run, its fingerprint line
	label=$1; shift
	printf '%-28s' "$label"
	env "$@" $PINNED "$G" --headless $FIXED --path . -- --probe pacehash298 2>&1 | grep -E "^PACEHASH|^PHASH|SCRIPT ERROR|PARSE ERROR" | sed -e 's/^PACEHASH steps=[0-9]* fighters=\([0-9]*\) alive=\([0-9]*\) frames=\([0-9]*\) (\([0-9.]*\) steps a frame) wall \([0-9.]*\) s cap \([0-9]*\): /\1 on the sand, \2 alive, \3 frames (\4 a frame, \5 s), fingerprint /'
}
PINNED="" FIXED="--fixed-fps 120" play "a step to a frame" DRAW=0
PINNED="$pin" FIXED="" play "real time, four a frame" RT=1 PACE=0
PINNED="$pin" FIXED="" play "real time, two a frame" RT=1 PACE=0 CAP=2
PINNED="$pin" FIXED="" play "real time, the governor" RT=1
[ $ours -eq 1 ] && rm -f override.cfg
