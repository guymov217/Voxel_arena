#!/bin/sh
# Parses every script (an import run) and prints script errors with their lines.
G=${GODOT:-/opt/godot/Godot_v4.4.1-stable_linux.x86_64}
cd "$(dirname "$0")" && timeout 180 "$G" --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|at: GDScript" | head -${1:-30}
