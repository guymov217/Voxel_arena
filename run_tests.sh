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
# No host advantage (Match._fair_*, InputDelay; tools/lat_join.py): in a fight of people against each other the host's own hands wait for
# the slowest friend's trip as well, so that a guest's blow starts in the host's physics when the host's own would. NET_FAIR=1 takes the
# yard to be such a fight; with a pretend 15 ms each way (a ping near 60 ms) the guest's swing is 36 ms behind the host's own without it,
# a few ms with it: it may not be more than 15 ms from it either way.
if python3 -c "import sys" >/dev/null 2>&1; then
	if delay_run 70 4 NET_FAIR=1 NET_OWN=8 NET_HAND=8 NET_LAG=15 && python3 tools/lat_join.py /tmp/va_netlat_host.log /tmp/va_netlat_guest.log --max-gap 15 > /tmp/va_netfair.log 2>&1; then
		echo "net (fair hands, 15 ms each way): ok ($(grep 'behind the host' /tmp/va_netfair.log | sed -e 's/^ *//'))"
	else
		echo "net (fair hands, 15 ms each way): FAIL (host $hs, guest $gs)"; cat /tmp/va_netfair.log; fail=1
	fi
	# The others ahead of the host's snapshots (Match._lead_for, Lead): the host's man walks to and fro in the yard, and the guest's picture
	# of him is set against where he is one way of the line on, when a blow of the guest's would reach him. Without the lead the picture is
	# 57 ms behind and 14 cm off while he walks, with it about level and 5 cm off: it may be no more than 30 ms behind and 9 cm off.
	if delay_run 70 4 NET_TGT=25 NET_TGT_ONLY=15 NET_LAG=15 && python3 tools/lat_tgt.py /tmp/va_netlat_host.log /tmp/va_netlat_guest.log --max-mean-cm 9 --max-shift-ms 30 > /tmp/va_nettgt.log 2>&1; then
		echo "net (the others ahead, 15 ms each way): ok ($(grep 'blow landing' /tmp/va_nettgt.log | sed -e 's/.*picture is //'))"
	else
		echo "net (the others ahead, 15 ms each way): FAIL (host $hs, guest $gs)"; cat /tmp/va_nettgt.log; fail=1
	fi
fi
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
# Friends who are not there (Friends, FriendPilot, FriendsStrip; tests/friend_probe.gd): a room opened as a host opens it, two friends
# brought in by the strip's own + button and F6 (each a game of this project, joining by address), who walk the yard, go into a stall
# when told (the host holds a man at a stall untouchable), pick a quarrel, fight in a free for all, and one is asked to leave and
# one is cut off. What the host sees is what a real friend's game shows him.
export NET_PORT=$((NET_PORT + 1))
if timeout 700 "$G" --headless --path . -- --probe friend_probe --port "$NET_PORT" > /tmp/va_friends.log 2>&1; then
	echo "net (friends): ok ($(grep -E '^FRIENDS' /tmp/va_friends.log))"
else
	echo "net (friends): FAIL"; grep -E "FAIL|RESULT|FRIENDS|^LOG " /tmp/va_friends.log | tail -40; fail=1
fi
# The friends through every mode of a room (tests/friend_modes.gd): the circles of a team fight (the friends walk into them), forge and
# fight, the endless arena's rewards, a campaign room's bout and gate votes; FRIENDS=full adds the tournament and the six single modes
# (another four minutes).
export NET_PORT=$((NET_PORT + 1))
friend_args="--quick"
[ "$FRIENDS" = full ] && friend_args=""
if timeout 2400 "$G" --headless --path . -- --probe friend_modes --port "$NET_PORT" $friend_args > /tmp/va_friend_modes.log 2>&1; then
	echo "net (friends, every mode): ok ($(grep -E '^FRIENDMODES' /tmp/va_friend_modes.log))"
else
	echo "net (friends, every mode): FAIL"; grep -E "FAIL|RESULT|FRIENDMODES|^LOG " /tmp/va_friend_modes.log | tail -40; fail=1
fi
# The diagnostic test (tools/diagnose.sh, scripts/diag/), quick and with no window: the plan, each part's game (the steps with their thread settings, the native core off), the release
# build made from the project's pack and Godot's release template where the templates are installed, the report with its summary. A part that needs a window is told as not run.
rm -f diagnose_report.txt
if HEADLESS=1 timeout 900 sh tools/diagnose.sh --quick > /tmp/va_diag.log 2>&1 && grep -q "== SUMMARY ==" diagnose_report.txt && grep -q "THE STEP" diagnose_report.txt && ! grep -E "PROBLEM|DID NOT FINISH" diagnose_report.txt | grep -qv "before the test began"; then
	echo "diag (the one test, quick, no window): ok ($(grep -c '^== [0-9]' diagnose_report.txt) parts, $(grep -c 'NOT RUN' diagnose_report.txt) not run here)"
else
	echo "diag (the one test, quick, no window): FAIL"; tail -30 /tmp/va_diag.log; grep -E "PROBLEM|NOT RUN|DID NOT FINISH" diagnose_report.txt | head -10; fail=1
fi
rm -f diagnose_report.txt
exit $fail
