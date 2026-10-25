#!/bin/sh
# The demo edition (what the free Steam demo ships): campaign bouts 1 to 8, the demo's arena
# modes and training, the forge and the yard. Same game, the "demo" feature on (docs/DEMO.md).
# Godot: $GODOT, else `godot` on the PATH.
G=${GODOT:-godot}
cd "$(dirname "$0")" || exit 1
exec "$G" --path . -- --demo "$@"
