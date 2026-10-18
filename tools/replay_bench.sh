#!/bin/sh
# How long the replay check's fights take a step on this machine (one physics thread): the same
# fight to the last bit before and after a change, so the difference is the code's alone.
#   sh tools/replay_bench.sh        (run it on each version, a few times, and compare)
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
printf '[threading]\nworker_pool/max_threads=1\n' > override.cfg
for sc in "REPLAY_N=16" "REPLAY_MIX=1 REPLAY_N=24"; do
	echo "$sc: $(env $sc "$GODOT" --headless --fixed-fps 120 --path . -- --probe replay_dump 2>&1 | grep TIMING)"
done
rm -f override.cfg
