#!/bin/sh
# The store screenshots from the game itself: 1920x1080 PNGs in docs/store/screenshots (see tools/make_screenshots.bat).
#   tools/make_screenshots.sh              all of them          tools/make_screenshots.sh 03_clash   one scene
# Needs Godot 4.7 ($GODOT, else `godot`) and a display; on a machine with no screen: xvfb-run -a -s "-screen 0 1920x1080x24" tools/make_screenshots.sh
# (a GPU renders a shot in seconds; the software renderer of a machine with none takes many minutes for each fight).
G=${GODOT:-godot}
cd "$(dirname "$0")/.." || exit 1
mkdir -p docs/store/screenshots
SHOT_DIR=$PWD/docs/store/screenshots SHOT_ONLY=$1 exec "$G" --path . --resolution 1920x1080 -- --probe steamshots
