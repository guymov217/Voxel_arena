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
timeout 1500 "$G" --headless --path . -- --test || fail=1
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
