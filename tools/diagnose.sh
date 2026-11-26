#!/bin/sh
# THE diagnostic test (Windows: tools\diagnose.bat): one run measures, on this computer, what decides why the game cannot hold a full room, and writes ONE file,
# diagnose_report.txt, in the game's folder (scripts/diag/diag.gd says what the parts are). About 13 minutes with a window; headless (HEADLESS=1) only the parts that
# need none run (the steps, the release build): a minute and a half quick.
#   sh tools/diagnose.sh                 the whole test (a window shows the list and the time left)
#   sh tools/diagnose.sh --quick         shortened, for a look first
#   sh tools/diagnose.sh --size 1920x1080 --skip room --only fight,steps --keep
#   sh tools/diagnose.sh --all           every part there is, the ones the reports have answered too (50 minutes)
#   HEADLESS=1 sh tools/diagnose.sh --quick
# Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
echo "Checking the project..."
"$G" --headless --path . --import >/dev/null 2>&1   # (the engine must know the scripts, the test's own among them)
rm -f diagnose_report.txt
if [ -n "$HEADLESS" ]; then
	"$G" --headless --path . -- --diag "$@"
else
	"$G" --path . --position 60,60 --resolution 1000x560 -- --diag "$@"
fi
status=$?
[ -f diagnose_report.txt ] && echo "The report: $(pwd)/diagnose_report.txt"
exit $status
