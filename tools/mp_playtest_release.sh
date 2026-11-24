#!/bin/sh
# The playtest of tools/mp_playtest.sh in a RELEASE build, which is what a player runs: the project's pack (--export-pack, a few seconds) beside a copy of Godot's release
# template and the native core's library, in build/play. The editor's own binary is a debug build and costs a physics step 15 to 20% more (the diagnostic test's report), so
# a room that runs in slow motion under it runs better here, and F3 and build/play/hitches.txt say what a player's game does. Needs Godot's export templates for 4.7.
#   sh tools/mp_playtest_release.sh            the friends' Arena (the room opens on its lobby)
#   ROOM=campaign sh tools/mp_playtest_release.sh      a campaign room        YARD=1: straight into the yard
# Godot: $GODOT, or `godot` on the PATH. Windows users: multiplayer_playtest_release.bat.
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
T=$(ls -d "${XDG_DATA_HOME:-$HOME/.local/share}"/godot/export_templates/4.7*/linux_release.x86_64 2>/dev/null | tail -n 1)
if [ -z "$T" ]; then
	echo "Godot's export templates for 4.7 are not installed (Editor, Manage Export Templates, Download and Install)." >&2
	exit 1
fi
echo "Making the release build (a few seconds)..."
mkdir -p build/play
rm -f build/play/play.pck build/play/play
"$G" --headless --path . --export-pack "Linux" build/play/play.pck >/dev/null 2>&1
if [ ! -f build/play/play.pck ]; then
	echo "The game's pack was not made (is there a preset named Linux in export_presets.cfg?)." >&2
	exit 1
fi
cp "$T" build/play/play && chmod +x build/play/play
cp native/bin/*.so build/play/ 2>/dev/null
room="--arena"
[ "$ROOM" = campaign ] && room=""
yard=""
[ -n "$YARD" ] && yard="--yard"
exec build/play/play --position 40,60 --resolution 1280x720 -- --keep-window --host $room $yard --playtest --name "${NAME:-You}"
