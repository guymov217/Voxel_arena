#!/bin/sh
# How many fighters this computer can host smoothly (no network, no players needed).
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
"$GODOT" --headless --fixed-fps 120 --path . -- --probe host_bench 2>&1 | grep -E "host check|fighters|RESULT|guest"
