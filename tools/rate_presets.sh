#!/bin/sh
# The arsenal's ratings (data/weapon_ratings.json, what WeaponRating ranks a forged weapon among): every weapon of the arsenal that a bot can fight a duel with, put through the rating battery
# (scripts/game/weapon_rating.gd) in JOBS games at once, the table written whole when all of them are done.
# Make it again after a change to the battery, to a weapon, to how a man fights or to the physics (a test holds the table to the battery's stamp, nothing else says that it is old):
#   sh tools/rate_presets.sh              (the arsenal in 3 games at once; GODOT names the program, JOBS the games)
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
JOBS=${JOBS:-3}
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d)
# One worker thread, as the tests run: with the physics' jobs spread over the pool the order they come back in changes from run to run, and with it every bout; on one the same bouts come out the same
# every time, so the table can be made again and be the same (override.cfg, only while this runs; one of your own is left as it is).
mark="; rate_presets.sh: one worker thread while the arsenal is rated (removed after)"
ours=0
if [ ! -f override.cfg ] || head -n 1 override.cfg | grep -qF "$mark"; then
	printf '%s\n[threading]\n\nworker_pool/max_threads=1\n' "$mark" > override.cfg
	ours=1
else
	echo "override.cfg of your own: the arsenal is rated with it (and may not come out the same every time)" >&2
fi
cleanup() { rm -rf "$work"; [ "$ours" -eq 1 ] && rm -f override.cfg; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
python3 - "$work" "$JOBS" <<'EOF' || exit 1
import json, sys
work, n = sys.argv[1], int(sys.argv[2])
presets = json.load(open('data/presets.json'))['presets']
keys = [k for k, v in presets.items() if v.get('kind', 'weapon') != 'shield' and not v.get('shoots')]
for i in range(n):
    json.dump({"presets": keys[i::n], "out": "%s/out_%d.json" % (work, i)}, open("%s/job_%d.json" % (work, i), "w"))
print("%d weapons in %d games" % (len(keys), n))
EOF
i=0
while [ "$i" -lt "$JOBS" ]; do
	"$G" --headless --fixed-fps 120 --path . -- --rate "$work/job_$i.json" > "$work/log_$i.txt" 2>&1 &
	i=$((i + 1))
done
wait
python3 - "$work" "$JOBS" <<'EOF' || { echo "the table was not made"; tail -n 20 "$work"/log_*.txt; exit 1; }
import json, sys
work, n = sys.argv[1], int(sys.argv[2])
table, stamp = {}, None
for i in range(n):
    out = json.load(open("%s/out_%d.json" % (work, i)))
    if out.get("state") != "done":
        raise SystemExit("game %d did not finish (%s)" % (i, out.get("state")))
    if stamp not in (None, out["stamp"]):
        raise SystemExit("the games were not of one battery")
    stamp = out["stamp"]
    table.update(out["presets"])
for k, v in table.items():
    print("%-16s %5.1f   won %s of %s" % (k, v["score"], int(v["won"]), v["of"]))
with open("data/weapon_ratings.json", "w") as f:
    json.dump({"version": 1, "stamp": stamp, "presets": table}, f, indent=1, sort_keys=True)
    f.write("\n")
print("data/weapon_ratings.json: %d weapons, battery %s" % (len(table), stamp))
EOF
