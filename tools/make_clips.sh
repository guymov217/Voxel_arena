#!/bin/sh
# Vertical 1080x1920 clips for TikTok, Shorts and Reels, cut from bot fights (tests/clipshots.gd).
# Needs xvfb-run, ffmpeg and Pillow. Each scene runs twice: once without drawing, to find where
# the fight ends (the first death), then drawn with the movie maker from 12 s before that to 3 s
# after it, with the hook text on top and the end card over the last seconds.
#   tools/make_clips.sh                 every scene
#   tools/make_clips.sh gorilla bear    some of them
# Output: docs/store/clips/clip_<scene>.mp4 (work files in $CLIP_TMP, default /tmp/wrecksmith_clips)
G=${GODOT:-$(command -v godot 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
OUT=docs/store/clips
TMP=${CLIP_TMP:-/tmp/wrecksmith_clips}
mkdir -p "$OUT" "$TMP"
FPS=30
LEAD=${CLIP_LEAD:-12}   # seconds before the death
TAIL=3                  # seconds after it
END=2                   # seconds of end card

hook_of() {
	case $1 in
		gorilla) echo "he wanted to fight the gorilla" ;;
		cyclops) echo "1 spear vs 1 cyclops" ;;
		elephant) echo "never stand in front of the elephant" ;;
		bear) echo "axe vs bear, who wins" ;;
		duel) echo "real physics sword fight" ;;
		zweihander) echo "the zweihander solves problems" ;;
		chicken) echo "i forged a chicken. it works" ;;
		*) echo "WRECKSMITH" ;;
	esac
}

# The movie maker takes its size from the project settings, so the clips are drawn from a copy of
# the project whose override.cfg makes the window portrait (the project itself is left alone).
PROJ="$TMP/project"
mkdir -p "$PROJ"
if command -v rsync >/dev/null 2>&1; then rsync -a --delete --exclude .git ./ "$PROJ/"; else rm -rf "$PROJ"; mkdir -p "$PROJ"; tar --exclude=.git -cf - . | tar -xf - -C "$PROJ"; fi
# One worker thread: the physics then plays the same fight in both runs (tools/replay_check.sh).
printf '[display]\nwindow/size/viewport_width=1080\nwindow/size/viewport_height=1920\n[threading]\nworker_pool/max_threads=1\n' > "$PROJ/override.cfg"
XVFB="-screen 0 1080x1920x24"

scenes=${*:-"gorilla cyclops elephant bear duel zweihander chicken"}
for k in $scenes; do
	echo "== $k"
	CLIP=$k CLIP_DRY=1 CLIP_SECONDS=60 timeout 1800 xvfb-run -a -s "$XVFB" "$G" \
		--resolution 1080x1920 --fixed-fps $FPS --path "$PROJ" -- --probe clipshots 2>&1 \
		| grep -E "^(HIT|DEATH|REC_)" > "$TMP/$k.dry"
	death=$(grep -m1 "^DEATH" "$TMP/$k.dry" | cut -d' ' -f2)
	last=$(grep "^REC_END" "$TMP/$k.dry" | cut -d' ' -f2)
	[ -z "$death" ] && death=$last   # nobody fell: the last seconds
	[ -z "$death" ] && { echo "  the dry run failed"; continue; }
	start=$((death - LEAD * FPS)); [ $start -lt 0 ] && start=0
	stop=$((death + TAIL * FPS))
	echo "  death at frame $death: drawing $start..$stop"
	rm -rf "$TMP/$k"; mkdir -p "$TMP/$k"
	CLIP=$k CLIP_FROM=$start CLIP_SECONDS=$(( (stop + FPS) / FPS + 1 )) timeout 7200 xvfb-run -a -s "$XVFB" "$G" \
		--resolution 1080x1920 --write-movie "$TMP/$k/f.png" --fixed-fps $FPS --path "$PROJ" -- --probe clipshots 2>&1 \
		| grep -E "^(HIT|DEATH|REC_)" > "$TMP/$k.rec"
	# The movie's frame 0 is the menu's first frame: REC_START says where the fight began.
	rec0=$(grep "^REC_START" "$TMP/$k.rec" | cut -d' ' -f2)
	d2=$(grep -m1 "^DEATH" "$TMP/$k.rec" | cut -d' ' -f2)
	if [ -n "$d2" ] && [ "$d2" != "$death" ]; then
		echo "  note: the drawn fight fell at frame $d2, not $death"
		[ "$d2" -gt "$start" ] && stop=$((d2 + TAIL * FPS))
	fi
	last2=$(grep "^REC_END" "$TMP/$k.rec" | cut -d' ' -f2)
	[ -n "$last2" ] && [ "$stop" -gt "$last2" ] && stop=$last2
	first=$((rec0 + start))
	n=$((stop - start))
	python3 tools/clip_overlays.py "$(hook_of "$k")" "$TMP/$k.hook.png" "$TMP/$k.end.png"
	dur=$(echo "$n $FPS" | awk '{printf "%.3f", $1 / $2}')
	endt=$(echo "$dur $END" | awk '{printf "%.3f", $1 - $2}')
	ffmpeg -y -hide_banner -loglevel error \
		-framerate $FPS -start_number $first -i "$TMP/$k/f%08d.png" \
		-ss "$(echo "$first $FPS" | awk '{printf "%.3f", $1 / $2}')" -i "$TMP/$k/f.wav" \
		-loop 1 -i "$TMP/$k.hook.png" -loop 1 -i "$TMP/$k.end.png" \
		-filter_complex "[0:v][2:v]overlay=0:0:enable='lt(t,$endt)'[a];[3:v]format=rgba,fade=t=in:st=$endt:d=0.3:alpha=1[e];[a][e]overlay=0:0:enable='gte(t,$endt)',format=yuv420p[v];[1:a]afade=t=out:st=$endt:d=$END[au]" \
		-map "[v]" -map "[au]" -frames:v $n -t "$dur" -c:v libx264 -preset slow -crf 18 -c:a aac -b:a 192k -movflags +faststart \
		"$OUT/clip_$k.mp4" && echo "  saved $OUT/clip_$k.mp4 (${dur} s)"
done
