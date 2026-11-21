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
# The packaging tool's own checks (presets, SteamPipe scripts, archives; no Godot in them). Skipped where there is no Python.
if python3 -c "import sys" >/dev/null 2>&1; then
	if python3 tools/test_package.py > /tmp/va_package_test.log 2>&1; then echo "package tool: ok"; else echo "package tool: FAIL"; tail -20 /tmp/va_package_test.log; fail=1; fi
fi
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
# The same bout over the Steam path: the room is a Steam lobby (Steam itself stands in: tests/steam_loopback.gd, a folder the
# two games share; the bytes go over ENet on localhost). The game's own Steam code is what runs: the lobby and its data,
# the list and its filters, the join, the build check, the hello, the bout. Valve's real calls and relay are only seen with Steam.
export STEAM_FAKE_DIR=$(mktemp -d)
export NET_PORT=$((NET_PORT + 1))
timeout 120 "$G" --headless --path . -- --probe net_steam_host > /tmp/va_netsteam_host.log 2>&1 &
hp=$!
sleep 2
timeout 110 "$G" --headless --path . -- --probe net_steam_guest > /tmp/va_netsteam_guest.log 2>&1
gs=$?
wait $hp
hs=$?
rm -rf "$STEAM_FAKE_DIR"
grep -E "^(HOST|GUEST)" /tmp/va_netsteam_host.log /tmp/va_netsteam_guest.log
if [ $gs -ne 0 ] || [ $hs -ne 0 ]; then echo "net (steam path): FAIL (host $hs, guest $gs)"; fail=1; else echo "net (steam path): ok"; fi
# The endless arena with a friend over ENet: the waves grow with the party, each one's rewards go to him over the wire and his pick
# comes back, the fallen stand up again, and the guest reads the host's state line (tests/net_party_host.gd, net_party_guest.gd).
export NET_PORT=$((NET_PORT + 1))
timeout 150 "$G" --headless --path . -- --probe net_party_host > /tmp/va_netparty_host.log 2>&1 &
hp=$!
sleep 2
timeout 140 "$G" --headless --path . -- --probe net_party_guest > /tmp/va_netparty_guest.log 2>&1
gs=$?
wait $hp
hs=$?
grep -E "^(HOST|GUEST)" /tmp/va_netparty_host.log /tmp/va_netparty_guest.log
if [ $gs -ne 0 ] || [ $hs -ne 0 ]; then echo "net (party): FAIL (host $hs, guest $gs)"; fail=1; else echo "net (party): ok"; fi
# An Arena room through the game's own menus (tests/net_room_host.gd, net_room_guest.gd): the room's kind told to the guest, the
# sandbox (each one's campaign purse untouched), the yard, the team circles and the fight begun on both sides.
export NET_PORT=$((NET_PORT + 1))
timeout 150 "$G" --headless --path . -- --probe net_room_host > /tmp/va_netroom_host.log 2>&1 &
hp=$!
sleep 3
timeout 140 "$G" --headless --path . -- --probe net_room_guest > /tmp/va_netroom_guest.log 2>&1
gs=$?
wait $hp
hs=$?
grep -E "^(HOST|GUEST)" /tmp/va_netroom_host.log /tmp/va_netroom_guest.log
if [ $gs -ne 0 ] || [ $hs -ne 0 ]; then echo "net (room): FAIL (host $hs, guest $gs)"; fail=1; else echo "net (room): ok"; fi
# The delay a guest feels (tests/net_lat_host.gd, net_lat_guest.gd): two games at 60 frames a second, he presses forward and times
# how long until his man moves on his own screen. 115 ms before the network was read at the start of each physics step, 65 ms
# when the players' fighters went out every frame, about 32 ms now that his own man is walked ahead of the host's word
# (MovePredictor) and his hands are read in the physics step. Run again with a pretend 30 ms each way (a ping near 100 ms), where
# the walk ahead is the whole of it: 165 ms without, about 32 with. The medians may not pass 55 and 60.
delay_run() {   # delay_run MAX_MEDIAN REPS [env...]: prints the guest's median, returns 1 if over
	dmax=$1; dreps=$2; shift 2
	export NET_PORT=$((NET_PORT + 1))
	env NET_REPS=$dreps NET_MAX_MEDIAN=$dmax "$@" timeout 140 "$G" --headless --path . -- --probe net_lat_host > /tmp/va_netlat_host.log 2>&1 &
	hp=$!
	sleep 3
	env NET_REPS=$dreps NET_MAX_MEDIAN=$dmax "$@" timeout 130 "$G" --headless --path . -- --probe net_lat_guest > /tmp/va_netlat_guest.log 2>&1
	gs=$?
	wait $hp
	hs=$?
	grep -E "^(HOST|GUEST)" /tmp/va_netlat_host.log /tmp/va_netlat_guest.log | grep -E "SUMMARY|FAIL|his input"
	dmed=$(grep -E 'GUEST SUMMARY' /tmp/va_netlat_guest.log | sed -e 's/.*median \([0-9]*\).*/median \1 ms/')
	[ $gs -eq 0 ] && [ $hs -eq 0 ]
}
if delay_run 55 12; then echo "net (delay): ok ($dmed)"; else echo "net (delay): FAIL (host $hs, guest $gs)"; fail=1; fi
if delay_run 60 8 NET_LAG=30; then echo "net (delay, 30 ms each way): ok ($dmed)"; else echo "net (delay, 30 ms each way): FAIL (host $hs, guest $gs)"; fail=1; fi
# All of multiplayer played out by three games through the game's own screens (tests/e2e_run.gd, e2e_host.gd, e2e_guest.gd): the
# lobby, the yard, the smith, the fights, the endless arena with three, a removal, a campaign room. The short version here
# (E2E=full for every mode of the Arena too: another three minutes).
export NET_PORT=$((NET_PORT + 1))
e2e_args="--quick"
[ "$E2E" = full ] && e2e_args=""
if timeout 1500 "$G" --headless --path . -- --probe e2e_run --port "$NET_PORT" $e2e_args > /tmp/va_e2e.log 2>&1; then
	echo "net (end to end): ok ($(grep -E '^[0-9]+ checks' /tmp/va_e2e.log))"
else
	echo "net (end to end): FAIL"; grep -E "FAIL|RESULT|checks," /tmp/va_e2e.log | tail -25; fail=1
fi
exit $fail
