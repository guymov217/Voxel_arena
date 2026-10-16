#!/bin/sh
# Parses every script (an import run) and prints script errors with their lines.
# Godot: $GODOT, else `godot` on the PATH, else the Linux build in /opt. On Windows (Git Bash):
#   GODOT="/d/godot/Godot_v4.7.2-stable_win64_console.exe" bash run_tests.sh
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
if ! command -v "$G" >/dev/null 2>&1 && [ ! -x "$G" ]; then
	echo "Godot not found: set GODOT to the Godot 4.7 executable (the *_console.exe on Windows), or put godot on the PATH" >&2
	exit 2
fi
cd "$(dirname "$0")" && timeout 180 "$G" --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|at: GDScript" | head -${1:-30}
