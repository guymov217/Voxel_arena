#!/bin/sh
# The same fight, step for step, on one physics thread (Jolt is deterministic then), and a
# fingerprint of every body each second. Two versions of the game that print the same lines play
# it exactly the same way.
#   sh tools/replay_check.sh > before.txt   ... change the code ...   sh tools/replay_check.sh | diff before.txt -
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
printf '[threading]\nworker_pool/max_threads=1\n' > override.cfg
for n in 16 6; do
	REPLAY_N=$n "$GODOT" --headless --fixed-fps 120 --path . -- --probe replay_dump 2>&1 | grep REPLAY | sed "s/^/n=$n /"
done
rm -f override.cfg
