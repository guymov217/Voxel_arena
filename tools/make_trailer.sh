#!/bin/sh
# The launch trailer, 1920x1080, from the game itself: bot fights cut round their best moment
# (tests/clipshots.gd), the forge building a weapon (tests/forgeclip.gd), the game's own boss
# music under it all (tests/musicbed.gd), title cards over the cuts and the logo at the end.
# Needs xvfb-run, ffmpeg and Pillow. Takes a few hours on a machine without a GPU.
#   tools/make_trailer.sh            -> docs/store/trailer.mp4 (work files in $TRAILER_TMP)
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
TMP=${TRAILER_TMP:-/tmp/wrecksmith_trailer}
OUT=docs/store
FPS=30
mkdir -p "$TMP"
PROJ="$TMP/project"
mkdir -p "$PROJ"
rm -rf "$PROJ"; mkdir -p "$PROJ"; tar --exclude=.git --exclude=docs/store -cf - . | tar -xf - -C "$PROJ"
printf '[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n[threading]\nworker_pool/max_threads=1\n' > "$PROJ/override.cfg"
XVFB="-screen 0 1920x1080x24"

# One fight, cut to LEAD seconds before its first death and TAIL after: $TMP/<scene>.mp4
shot() {   # scene lead tail
	k=$1; lead=$2; tail=$3
	[ -s "$TMP/$k.mp4" ] && return
	CLIP=$k CLIP_DRY=1 CLIP_SECONDS=60 timeout 1800 xvfb-run -a -s "$XVFB" "$G" --fixed-fps $FPS --path "$PROJ" -- --probe clipshots 2>&1 \
		| grep -E "^(DEATH|REC_)" > "$TMP/$k.dry"
	death=$(grep -m1 "^DEATH" "$TMP/$k.dry" | cut -d' ' -f2)
	[ -z "$death" ] && death=$(grep "^REC_END" "$TMP/$k.dry" | cut -d' ' -f2)
	[ -z "$death" ] && { echo "  $k: the dry run failed"; return; }
	start=$((death - lead * FPS)); [ $start -lt 0 ] && start=0
	stop=$((death + tail * FPS))
	rm -rf "$TMP/$k"; mkdir -p "$TMP/$k"
	CLIP=$k CLIP_FROM=$start CLIP_SECONDS=$(( (stop + FPS) / FPS + 1 )) timeout 7200 xvfb-run -a -s "$XVFB" "$G" \
		--write-movie "$TMP/$k/f.png" --fixed-fps $FPS --path "$PROJ" -- --probe clipshots 2>&1 | grep -E "^(DEATH|REC_)" > "$TMP/$k.rec"
	rec0=$(grep "^REC_START" "$TMP/$k.rec" | cut -d' ' -f2)
	d2=$(grep -m1 "^DEATH" "$TMP/$k.rec" | cut -d' ' -f2)
	[ -n "$d2" ] && [ "$d2" -gt "$start" ] && stop=$((d2 + tail * FPS))
	last=$(grep "^REC_END" "$TMP/$k.rec" | cut -d' ' -f2)
	[ -n "$last" ] && [ "$stop" -gt "$last" ] && stop=$last
	first=$((rec0 + start))
	ffmpeg -y -hide_banner -loglevel error -framerate $FPS -start_number $first -i "$TMP/$k/f%08d.png" \
		-frames:v $((stop - start)) -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -an "$TMP/$k.mp4" && echo "  $k: $(( (stop - start) / FPS )) s"
	rm -rf "$TMP/$k"
}

echo "== fights"
shot gorilla 4 1
shot duel 4 1
shot elephant 3 1
shot cyclops 3 1
shot bear 3 1
shot chicken 4 1

echo "== the forge"
if [ ! -s "$TMP/forge.mp4" ]; then
	rm -rf "$TMP/forge"; mkdir -p "$TMP/forge"
	FORGE_SECONDS=4 timeout 3600 xvfb-run -a -s "$XVFB" "$G" --write-movie "$TMP/forge/f.png" --fixed-fps $FPS --path "$PROJ" -- --probe forgeclip 2>&1 | grep -E "^REC_" > "$TMP/forge.rec"
	f0=$(grep "^REC_START" "$TMP/forge.rec" | cut -d' ' -f2)
	f1=$(grep "^REC_END" "$TMP/forge.rec" | cut -d' ' -f2)
	ffmpeg -y -hide_banner -loglevel error -framerate $FPS -start_number "$f0" -i "$TMP/forge/f%08d.png" -frames:v $((f1 - f0)) \
		-c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -an "$TMP/forge.mp4" && echo "  forge: $(( (f1 - f0) / FPS )) s"
	rm -rf "$TMP/forge"
fi

echo "== the music"
if [ ! -s "$TMP/music.wav" ]; then
	rm -rf "$TMP/music"; mkdir -p "$TMP/music"
	MUSIC_SECONDS=45 timeout 3600 xvfb-run -a -s "-screen 0 640x360x24" "$G" --write-movie "$TMP/music/f.png" --fixed-fps $FPS --path "$PROJ" -- --probe musicbed > /dev/null 2>&1
	cp "$TMP/music/f.wav" "$TMP/music.wav"
	rm -rf "$TMP/music"
fi

echo "== the cut"
python3 tools/trailer_cards.py "$TMP"
# The order, each shot's file and the card over it (cards/<n>.png, made above).
list="gorilla forge duel elephant cyclops bear chicken"
inputs=""; filt=""; n=0
for s in $list; do
	[ -s "$TMP/$s.mp4" ] || continue
	inputs="$inputs -i $TMP/$s.mp4"
	filt="$filt[$n:v]scale=1920:1080,setsar=1,fps=$FPS[v$n];"
	n=$((n + 1))
done
inputs="$inputs -loop 1 -t 4 -i $TMP/cards/end.png"
filt="$filt[$n:v]scale=1920:1080,setsar=1,fps=$FPS,format=yuv420p[v$n];"
cat=""; i=0
while [ $i -le $n ]; do cat="$cat[v$i]"; i=$((i + 1)); done
filt="$filt${cat}concat=n=$((n + 1)):v=1:a=0[cut];"
# The title cards over the cut at their times (cards.txt: file start end).
last="cut"; k=0
while read -r png t0 t1; do
	inputs="$inputs -i $TMP/cards/$png"
	idx=$((n + 1 + k))
	filt="$filt[$last][$idx:v]overlay=0:0:enable='between(t,$t0,$t1)'[o$k];"
	last="o$k"; k=$((k + 1))
done < "$TMP/cards/cards.txt"
inputs="$inputs -i $TMP/music.wav"
aidx=$((n + 1 + k))
total=$(python3 -c "import sys,subprocess;print(sum(float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',f]).decode()) for f in sys.argv[1:]) + 4)" $(for s in $list; do [ -s "$TMP/$s.mp4" ] && echo "$TMP/$s.mp4"; done))
filt="$filt[$last]format=yuv420p[vout];[$aidx:a]atrim=0:$total,afade=t=in:d=0.5,afade=t=out:st=$(python3 -c "print($total - 2)"):d=2[aout]"
eval ffmpeg -y -hide_banner -loglevel error $inputs -filter_complex "\"$filt\"" -map "[vout]" -map "[aout]" \
	-c:v libx264 -preset slow -crf 17 -c:a aac -b:a 192k -movflags +faststart -t "$total" "$OUT/trailer.mp4" \
	&& echo "saved $OUT/trailer.mp4 (${total} s)"
