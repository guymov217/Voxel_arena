#!/bin/sh
# Network load test on this machine: a host and N guests (separate headless games over ENet on
# localhost) play a campaign bout together; each reports what it cost. All of them share this
# machine's CPU, so the times are worse than over a real network, where each has its own.
#   sh tools/net_load.sh [guests=7] [seconds=20] [stage=6]
G=${1:-7}; S=${2:-20}; ST=${3:-6}
GODOT=${GODOT:-/opt/godot/Godot_v4.7.2-stable_linux.x86_64}
PORT=$((17000 + $$ % 1000))
DIR=$(mktemp -d)
cd "$(dirname "$0")/.."
NET_PORT=$PORT NET_GUESTS=$G NET_SECONDS=$S NET_STAGE=$ST "$GODOT" --headless --path . -- --probe net_load_host > "$DIR/host.log" 2>&1 &
HOST=$!
sleep 3
i=0
while [ $i -lt "$G" ]; do
	NET_PORT=$PORT "$GODOT" --headless --path . -- --probe net_load_guest > "$DIR/guest$i.log" 2>&1 &
	i=$((i + 1))
done
wait $HOST
sleep 3
grep -h "LOAD\|HOST" "$DIR/host.log"
grep -h "GUEST" "$DIR"/guest*.log
pkill -f "probe net_load_guest" 2>/dev/null
rm -rf "$DIR"
