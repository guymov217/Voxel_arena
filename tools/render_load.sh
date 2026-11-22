#!/bin/sh
# What a frame asks of the renderer with N men on the sand, drawn for real (#298l): draw calls, objects, primitives (all passes, the sun's shadow cascades included), what the
# engine's renderer takes of the processor to record a frame, and the scripts' frame. With no graphics card it runs on Mesa's software Vulkan (lavapipe) under Xvfb: the "gpu(sw)"
# figure is then the software rasteriser's and means nothing in itself (a frame takes seconds), but the counts do, and so does the engine's own recording time; set side by side,
# two runs say how much more or less the card is asked (primitives, draw calls) when a knob is turned. With a card, drop VK_ICD_FILENAMES and the Xvfb wrapper and it is a real figure.
#   sh tools/render_load.sh                     8 men standing, in armour, 320x180
#   N=2 ARMOR=0 sh tools/render_load.sh         2 bare men      (ARMOR_IDS=lorica,manica one set of pieces)
#   SHADOWS=0 QUALITY=low MSAA=0 SCALE=0.75 FOG=0 SSIL=0 sh tools/render_load.sh      the knobs (Arena.apply_quality, the sun's shadows, MSAA, 3D scale, volumetric fog, SSIL)
# The first run compiles the renderer's pipelines on the processor and takes several minutes; Godot keeps them for the next (XDG_DATA_HOME). Each frame takes seconds, so FRAMES and
# WARM are few (8 and 12). Needs Xvfb (xvfb-run) and Mesa's lavapipe (libvulkan_lvp) where there is no card. Godot: $GODOT, or `godot` on the PATH.
G=${GODOT:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}
cd "$(dirname "$0")/.." || exit 1
export N=${N:-8} BEHAVIOR=${BEHAVIOR:-idle} FRAMES=${FRAMES:-8} WARM=${WARM:-12} ARMOR=${ARMOR:-1}
ICD=${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}
if [ -f "$ICD" ]; then
	export VK_ICD_FILENAMES="$ICD" LP_NUM_THREADS=${LP_NUM_THREADS:-2}
fi
if command -v xvfb-run >/dev/null 2>&1 && [ -z "$DISPLAY" ]; then
	xvfb-run -a -s "-screen 0 1280x720x24" "$G" --rendering-driver vulkan --resolution ${RES:-320x180} --path . -- --probe render298 2>&1 | grep -E "^RENDER|SCRIPT ERROR|PARSE ERROR|Vulkan "
else
	"$G" --rendering-driver vulkan --resolution ${RES:-320x180} --path . -- --probe render298 2>&1 | grep -E "^RENDER|SCRIPT ERROR|PARSE ERROR|Vulkan "
fi
