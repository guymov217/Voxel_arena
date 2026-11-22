#!/bin/sh
# Network load test on this machine: a host and N guests (separate headless games over ENet on
# localhost) play a campaign bout together (or an arena mode); each reports what it cost. All of them
# share this machine's CPU, so the times are worse than over a real network, where each has its own.
#   sh tools/net_load.sh [guests=7] [seconds=20] [stage=6]
# NET_MODE=ffa|teams|hill|lastLimb|king|... plays that arena mode instead of the campaign (stage is then unused).
# NET_BOTS=0 puts no bots beside the guests (a room of eight is then eight fighters, as the fight screen makes it: without NET_BOTS the fight's usual
# three bots come too, 11 fighters in a room of eight, which the sand does not hold, FightOpts.MAX_FIGHTERS); NET_FPS=60 caps the host's frames a second
# as a window's vsync does (the host prints the frames it really made).
# HOST_CPUS=0 GUEST_CPUS=1-3 pins the host to its own core(s) and the guests to the others (taskset), so the
# guests' work does not take the host's time: nearer to a real room, where every player has a computer.
# NET_LAG=100 NET_LOSS=3 makes every guest's line poor (a pretend 100 ms and 3% loss, both ways).
G=${1:-7}; S=${2:-20}; ST=${3:-6}
GODOT=${GODOT:-/opt/godot/Godot_v4.7.2-stable_linux.x86_64}
PORT=$((17000 + $$ % 1000))
DIR=$(mktemp -d)
cd "$(dirname "$0")/.."
pin() { if [ -n "$1" ] && command -v taskset >/dev/null 2>&1; then echo "taskset -c $1"; fi; }
NET_MODE=${NET_MODE:-campaign}
NET_PORT=$PORT NET_GUESTS=$G NET_SECONDS=$S NET_STAGE=$ST NET_MODE=$NET_MODE $(pin "$HOST_CPUS") "$GODOT" --headless --path . -- --probe net_load_host > "$DIR/host.log" 2>&1 &
HOST=$!
sleep 3
i=0
while [ $i -lt "$G" ]; do
	NET_PORT=$PORT $(pin "$GUEST_CPUS") "$GODOT" --headless --path . -- --probe net_load_guest > "$DIR/guest$i.log" 2>&1 &
	i=$((i + 1))
done
wait $HOST
sleep 3
grep -h "LOAD\|HOST" "$DIR/host.log"
grep -h "GUEST" "$DIR"/guest*.log
pkill -f "probe net_load_guest" 2>/dev/null
rm -rf "$DIR"
