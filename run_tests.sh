#!/bin/sh
# The Godot port's checks: every script parses, the headless test suites, then a two-process
# multiplayer test (a host and a guest over ENet on localhost). Exit status 0 when all pass.
# Godot: $GODOT, else `godot` on the PATH, else the Linux build in /opt. On Windows (Git Bash):
#   GODOT="/d/godot/Godot_v4.7.2-stable_win64_console.exe" bash run_tests.sh
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
if ! command -v "$G" >/dev/null 2>&1 && [ ! -x "$G" ]; then
	echo "Godot not found: set GODOT to the Godot 4.7 executable (the *_console.exe on Windows), or put godot on the PATH" >&2
	exit 2
fi
cd "$(dirname "$0")" || exit 1
fail=0
errs=$(sh ./check.sh)
if [ -n "$errs" ]; then echo "$errs"; fail=1; else echo "parse: ok"; fi
# --fixed-fps: one physics step to every frame, however fast the machine, so what runs per frame
# and what runs per step keep in step and a run comes out the same every time. And one worker
# thread: the physics' jobs ran in parallel on the pool, and with many bodies about (the fight
# behind the menu) the order they came back in changed from run to run, and with it every fight
# after: the same tests passed one run and failed the next, in no order (override.cfg, only while
# the tests run; one of your own is left as it is, and the tests run with it).
mark="; run_tests.sh: one worker thread while the tests run (removed after them)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
	trap 'rm -f override.cfg' EXIT
	trap 'rm -f override.cfg; exit 130' INT TERM
else
	echo "override.cfg of your own: the tests run with it (and may not come out the same every run)" >&2
fi
timeout 3600 "$G" --headless --fixed-fps 120 --path . -- --test || fail=1
if [ $ours -eq 1 ]; then
	rm -f override.cfg
	trap - EXIT INT TERM
fi
export NET_PORT=${NET_PORT:-17777}
timeout 120 "$G" --headless --path . -- --probe net_host > /tmp/va_net_host.log 2>&1 &
hp=$!
sleep 2
timeout 110 "$G" --headless --path . -- --probe net_guest > /tmp/va_net_guest.log 2>&1
gs=$?
wait $hp
hs=$?
grep -E "^(HOST|GUEST)" /tmp/va_net_host.log /tmp/va_net_guest.log
if [ $gs -ne 0 ] || [ $hs -ne 0 ]; then echo "net: FAIL (host $hs, guest $gs)"; fail=1; else echo "net: ok"; fi
exit $fail
