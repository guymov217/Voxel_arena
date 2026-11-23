class_name FpsMeter
extends CanvasLayer
## F3 anywhere (the menus, the yard, a fight; in a room the connection's meter, NetMeter, comes
## and goes with it): the frame rate in the top left corner, and what the frames take, to be
## read off the player's own machine and sent on (user). Over the last second the frames a
## second and the mean frame; over the last five seconds the longest frame and how many took
## longer than a thirtieth of a second; and the work, by the engine's own measures: the longest
## physics step and the longest frame without physics (scripts, drawing, waiting on the graphics
## card) of the last second, and the last frame's drawing on the processor and on the graphics
## card. Green when it is good, amber when it is getting bad, red when it is bad. Kept on or off
## in the settings ("fps_meter").

const SLOW_MS := 1000.0 / 30.0
const WINDOW_S := 5.0
## A frame longer than this, with the meter on, is written to `user://hitches.txt` with what the game knows of it (a line a frame, four a
## second at most, the file kept under HITCH_FILE_MAX bytes): to be sent on with the video of a game that stopped, so that a stop can be
## told apart from a slow stretch and its cause looked for (the steps the frame had to take, a man built or freed, a message of the room).
const HITCH_MS := 60.0
const HITCH_FILE_MAX := 200000

## What the frame's own scripts take, counted only while the meter is shown (each of them looks at the clock only then): the men's
## drawing (Fighter, VoxelPart, Weapon) and the match's, in microseconds since the meter last read them.
static var prof_on := false
static var prof_men_us := 0
static var prof_match_us := 0

var panel: PanelContainer
var label: RichTextLabel
var _frames: Array = []   # [when (s), how long (ms)] for the last WINDOW_S seconds
var _last_us := 0
var _refresh_us := 0   # when the text is next written, by the wall clock (slow motion slows the game's)
var _prof_frames := 0   # the frames since the scripts' times were last read
var _prof := {"men": 0.0, "match": 0.0}   # and what they came to a frame (ms)
var _steps: Array = []   # [when (us), the physics steps taken so far] over the last second: the steps a second the game really keeps
## What the room said this frame, by kind of message (Net._count_in, only while the meter is on): the hitch record's.
static var msg_seen := {}
var _hitch_steps := 0       # the physics frames at the last frame's start
var _hitch_nodes := 0       # and the nodes then
var _hitch_t := -10.0       # when the last hitch was written (s)
var _hitch_n := 0

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.82)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 14)
	label.add_theme_font_size_override("bold_font_size", 14)
	panel.add_child(label)
	show_meter(bool(Save.get_value("settings", {}).get("fps_meter", false)))

## Shown or put away (and the graphics card's own timing on only while it is shown: it costs).
func show_meter(on: bool) -> void:
	visible = on
	set_process(on)
	prof_on = on
	prof_men_us = 0
	prof_match_us = 0
	_prof_frames = 0
	_frames.clear()
	_last_us = 0
	_refresh_us = 0
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)

func _exit_tree() -> void:
	prof_on = false

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.is_echo() and e.keycode == KEY_F3:
		show_meter(not visible)
		var st: Dictionary = Save.get_value("settings", {})
		st["fps_meter"] = visible
		Save.set_value("settings", st)
		if Net.active():
			Net.show_meter(visible)

## The connection's meter goes with the frame rate's whenever a room is open. (The frame rate's stays on from the last time,
## and the connection's only came with a press of F3 in the room: a video of a game that stuttered had every number but the
## ones that say why.)
func _sync_net() -> void:
	var want := visible and Net.active()
	if want != (Net.meter != null and is_instance_valid(Net.meter)):
		Net.show_meter(want)

func _process(_dt: float) -> void:
	var now_us := Time.get_ticks_usec()
	var now := now_us / 1e6
	if _last_us > 0:
		_frames.append([now, (now_us - _last_us) / 1000.0])
	_last_us = now_us
	_prof_frames += 1
	_hitch_check(now)
	while not _frames.is_empty() and now - float(_frames[0][0]) > WINDOW_S:
		_frames.pop_front()
	if now_us < _refresh_us:
		return
	_refresh_us = now_us + 250000
	_prof = {"men": prof_men_us / 1000.0 / _prof_frames, "match": prof_match_us / 1000.0 / _prof_frames}
	_steps.append([now_us, Engine.get_physics_frames()])
	while _steps.size() > 2 and now_us - int(_steps[0][0]) > 1100000:
		_steps.pop_front()
	prof_men_us = 0
	prof_match_us = 0
	_prof_frames = 0
	_sync_net()
	label.text = "\n".join(lines(_frames, now, Engine.get_frames_per_second(), _work()))

## A frame past HITCH_MS goes to the record with what is known of it. (The numbers are the engine's, read at the start of the frame after: the
## steps it took, the nodes made or freed in it, the longest physics step and the frame without physics of the last second, drawing and the
## graphics card, the messages of the room that came in, the men's drawing and the match's.)
func _hitch_check(now: float) -> void:
	var steps := Engine.get_physics_frames()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var ms := 0.0
	if _frames.size() > 0:
		ms = float((_frames[_frames.size() - 1] as Array)[1])
	var d_steps := steps - _hitch_steps
	var d_nodes := nodes - _hitch_nodes
	_hitch_steps = steps
	_hitch_nodes = nodes
	var seen := msg_seen
	msg_seen = {}
	if ms < HITCH_MS or now - _hitch_t < 0.25 or _frames.size() < 3:
		return
	_hitch_t = now
	var w := _work()
	var msgs := []
	for k in seen:
		msgs.append("%s x%d" % [k, int(seen[k])])
	msgs.sort()
	var line := "%s  game %.1f s  frame %.0f ms  steps %d  nodes %+d  physics(max) %.1f  frame-no-physics %.1f (drawing %.1f, card %.1f)  men %.1f match %.1f  draws %d  room %s  msgs [%s]" % [
		Time.get_datetime_string_from_system(), now, ms, d_steps, d_nodes, float(w.get("physics", 0.0)), float(w.get("frame", 0.0)), float(w.get("draw", 0.0)), float(w.get("gpu", 0.0)),
		float(w.get("men", 0.0)), float(w.get("match", 0.0)), int(w.get("calls", 0)), ("%d peers" % Net.peers.size()) if Net.active() else "none", ", ".join(msgs)]
	var path := "user://hitches.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > HITCH_FILE_MAX:
		f.close()
		f = FileAccess.open(path, FileAccess.WRITE)   # (the oldest go: a new record from here)
		if f == null:
			return
	f.seek_end()
	f.store_line(line)
	f.close()
	_hitch_n += 1

## The work (ms), by the engine's own measures: the longest physics step and the longest frame
## without physics of the last second, the last frame's drawing.
func _work() -> Dictionary:
	var w := {"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "frame": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "draw": 0.0, "gpu": 0.0, "native": Greedy.core() != null,
		"men": float(_prof.men), "match": float(_prof.match), "calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}
	# (The steps the game really takes a second of the 120 it is meant to: under it the host cannot keep up, and everything runs slow.)
	if _steps.size() >= 2:
		var span := float(int(_steps[_steps.size() - 1][0]) - int(_steps[0][0])) / 1e6
		if span > 0.4:
			w["steps"] = float(int(_steps[_steps.size() - 1][1]) - int(_steps[0][1])) / span
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		var rid := get_viewport().get_viewport_rid()
		w.draw = RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		w.gpu = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return w

## What the meter reads: `frames` [when (s), how long (ms)], `now` (s), the engine's frames a
## second, the `work` (ms: physics, frame, draw, gpu).
static func lines(frames: Array, now: float, fps: float, work: Dictionary) -> Array:
	var sum := 0.0
	var n := 0
	var worst := 0.0
	var slow := 0
	for fr in frames:
		var ms := float(fr[1])
		worst = maxf(worst, ms)
		if ms > SLOW_MS:
			slow += 1
		if now - float(fr[0]) <= 1.0:
			sum += ms
			n += 1
	var mean := sum / n if n > 0 else 0.0
	var out := []
	out.append(Loc.t("%s FPS · %s ms a frame · worst in 5 s %s ms · %s frames over 33 ms") % [
		_grade("[b]%d[/b]" % roundi(fps), fps, 55.0, 30.0, true),
		_grade("%.1f" % mean, mean, 18.0, SLOW_MS, false),
		_grade("%.1f" % worst, worst, 25.0, 50.0, false),
		_grade("%d" % slow, float(slow), 0.0, 5.0, false)] + "   [color=#9a8f80](F3)[/color]")
	out.append(Loc.t("physics %.1f ms a step · frame without physics %.1f ms (drawing %.1f ms) · graphics card %.1f ms") % [float(work.get("physics", 0.0)), float(work.get("frame", 0.0)), float(work.get("draw", 0.0)), float(work.get("gpu", 0.0))])
	if work.has("steps"):
		var rate := float(work.get("steps"))
		var want := float(Engine.physics_ticks_per_second)
		out[1] = String(out[1]) + " · " + _grade("%d" % roundi(rate), rate, want * 0.97, want * 0.85, true) + " of %d steps a second" % roundi(want)
	# (Whether the C++ core is loaded: without it, a step costs a fifth more and the machine looks slow for no reason one could see.)
	if work.has("native"):
		var on: bool = bool(work.get("native"))
		out[1] = String(out[1]) + "   [color=%s]%s[/color]" % ["#7ac36a" if on else "#d9534f", "native core on" if on else "native core OFF (slower)"]
	# (Where the frame without physics goes: the men's drawing, the match's own work, and all the rest: the other scripts, the engine and
	# the waiting on the graphics card. The draw calls beside them: what a slow graphics card is asked.)
	if work.has("men"):
		var frame := float(work.get("frame", 0.0))
		var men := float(work.get("men", 0.0))
		var mat := float(work.get("match", 0.0))
		out.append("in the frame: the men %.1f ms · the match %.1f ms · all the rest %.1f ms · %d draw calls" % [men, mat, maxf(0.0, frame - men - mat), int(work.get("calls", 0))])
	return out

## Green when it is good, amber when it is getting bad, red when it is bad (`up`: more is better).
static func _grade(text: String, v: float, good: float, bad: float, up: bool) -> String:
	var ok := v >= good if up else v <= good
	var poor := v < bad if up else v > bad
	return "[color=%s]%s[/color]" % ["#d9534f" if poor else ("#7ac36a" if ok else "#e0b44c"), text]
