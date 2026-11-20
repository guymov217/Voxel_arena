#!/bin/sh
# WRECKSMITH - package the game for Steam and for download without Steam (see tools/package.py, docs/PACKAGING.md).
# Godot: $GODOT, else `godot` on the PATH, else the Linux build in /opt. Arguments go on to package.py.
cd "$(dirname "$0")/.." || exit 1
PY=$(command -v python3 || command -v python) || { echo "Python 3 not found"; exit 1; }
exec "$PY" tools/package.py "$@"
