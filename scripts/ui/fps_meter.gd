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

var panel: PanelContainer
var label: RichTextLabel
var _frames: Array = []   # [when (s), how long (ms)] for the last WINDOW_S seconds
var _last_us := 0
var _refresh_us := 0   # when the text is next written, by the wall clock (slow motion slows the game's)

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
	_frames.clear()
	_last_us = 0
	_refresh_us = 0
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)

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
	while not _frames.is_empty() and now - float(_frames[0][0]) > WINDOW_S:
		_frames.pop_front()
	if now_us < _refresh_us:
		return
	_refresh_us = now_us + 250000
	_sync_net()
	label.text = "\n".join(lines(_frames, now, Engine.get_frames_per_second(), _work()))

## The work (ms), by the engine's own measures: the longest physics step and the longest frame
## without physics of the last second, the last frame's drawing.
func _work() -> Dictionary:
	var w := {"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "frame": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "draw": 0.0, "gpu": 0.0}
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
	return out

## Green when it is good, amber when it is getting bad, red when it is bad (`up`: more is better).
static func _grade(text: String, v: float, good: float, bad: float, up: bool) -> String:
	var ok := v >= good if up else v <= good
	var poor := v < bad if up else v > bad
	return "[color=%s]%s[/color]" % ["#d9534f" if poor else ("#7ac36a" if ok else "#e0b44c"), text]
