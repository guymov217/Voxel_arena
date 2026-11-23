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
## The record is kept whether or not the meter is shown (the stops of a game nobody had F3 on for are the ones to look at): a frame past HITCH_MS, a stretch of
## SLOW_WINDOW_S seconds in which the game ran under SLOW_SPEED of its speed or under SLOW_FPS frames a second (a game in slow motion has no long frame to show
## for it: its frames are all a little long), and the notes the game makes of its own starts (FpsMeter.note). The file is made at the game's start.
## In the game's own folder (user: where it can be found, as `host_check.txt` is): the project's, run from the editor or its .bat files, the executable's in an exported
## game; the user data folder (`user://`) if that one cannot be written. A game without a screen (the friends' games, the tests) keeps no record: they would write into
## the host's file (`force_record` is the tests' to say otherwise).
const LOG_FILE := "hitches.txt"
static var force_record := false
static var _log_path := ""

static func recording() -> bool:
	return force_record or DisplayServer.get_name() != "headless"

static func log_path() -> String:
	if _log_path != "":
		return _log_path
	var dir := OS.get_executable_path().get_base_dir() if (OS.has_feature("template") and not OS.has_feature("editor")) else ProjectSettings.globalize_path("res://").trim_suffix("/")
	var p := dir.path_join(LOG_FILE)
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f == null:
		p = ProjectSettings.globalize_path("user://" + LOG_FILE)   # (a folder the game may not write in: Program Files)
	else:
		f.close()
	_log_path = p
	return p
const SLOW_WINDOW_S := 2.0
const SLOW_SPEED := 0.97
const SLOW_FPS := 45.0

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
var _sw_t0 := -1.0          # the slow-stretch window: when it began (s), the physics steps then, the frames and the longest of them, those over 33 ms
var _sw_steps0 := 0
var _sw_frames := 0
var _sw_worst := 0.0
var _sw_over := 0
var _sw_n := 0              # the stretches written
var _sw_phys_us := 0        # in the window: what the frames' physics steps took by the wall clock (scripts and the engine's own steps)
var _ps_n := 0              # the physics steps of this frame so far, and when the first began (us): this node comes first in every frame
var _ps_t0 := 0
var _census_t := -100.0     # when the processor's census was last asked for (s)
var _census_thread: Thread = null

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100000   # (first in every frame's steps and in its process: the steps' cost is read between the two)
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
	if DisplayServer.get_name() != "headless":
		_log_session()

## Shown or put away (and the graphics card's own timing on only while it is shown: it costs).
func show_meter(on: bool) -> void:
	visible = on
	set_process(true)   # (the record is kept with the meter put away; only its text is not made)
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

func _physics_process(_dt: float) -> void:
	if _ps_n == 0:
		_ps_t0 = Time.get_ticks_usec()
	_ps_n += 1

func _process(_dt: float) -> void:
	var now_us := Time.get_ticks_usec()
	var now := now_us / 1e6
	if _ps_n > 0:
		_sw_phys_us += now_us - _ps_t0   # (this frame's steps, from the first one's start to here: all of them are done before any _process)
		_ps_n = 0
	if _last_us > 0:
		_frames.append([now, (now_us - _last_us) / 1000.0])
	_last_us = now_us
	_prof_frames += 1
	_hitch_check(now)
	_slow_check(now)
	while not _frames.is_empty() and now - float(_frames[0][0]) > WINDOW_S:
		_frames.pop_front()
	if not visible or now_us < _refresh_us:
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
	if not recording():
		return
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
	_log(line)
	_hitch_n += 1

## A stretch of SLOW_WINDOW_S seconds, written if the game ran under its speed or its frames under SLOW_FPS (the physics steps it took against the
## 120 a second it is meant to, at the engine's time scale; what the machine was asked: the men on the sand, the bodies awake, the draw calls, and
## whether the room is over its budget and how many steps a frame it lets itself take). A window in which the game was not in front is no stretch.
func _slow_check(now: float) -> void:
	if not recording():
		return
	var ms := 0.0
	if _frames.size() > 0:
		ms = float((_frames[_frames.size() - 1] as Array)[1])
	if _sw_t0 < 0.0:
		_sw_t0 = now
		_sw_steps0 = Engine.get_physics_frames()
		_sw_phys_us = 0
		return
	_sw_frames += 1
	_sw_worst = maxf(_sw_worst, ms)
	if ms > SLOW_MS:
		_sw_over += 1
	var span := now - _sw_t0
	if span < SLOW_WINDOW_S:
		return
	var steps := Engine.get_physics_frames() - _sw_steps0
	var frames := _sw_frames
	var worst := _sw_worst
	var over := _sw_over
	var phys_ms := float(_sw_phys_us) / 1000.0
	_sw_t0 = now
	_sw_steps0 = Engine.get_physics_frames()
	_sw_frames = 0
	_sw_worst = 0.0
	_sw_over = 0
	_sw_phys_us = 0
	if DisplayServer.get_name() != "headless" and not DisplayServer.window_is_focused():
		return   # (behind another window the engine slows itself down)
	var speed := slow_speed(steps, span, float(Engine.physics_ticks_per_second), Engine.time_scale)
	var fps := float(frames) / span
	if speed >= SLOW_SPEED and fps >= SLOW_FPS:
		return
	var w := _work()
	var men := int(Combat.current.fighters.size()) if Combat.current != null else 0
	var room := ("%d peers%s, steps a frame %d" % [Net.peers.size(), " OVER BUDGET" if Net.overloaded else "", Engine.max_physics_steps_per_frame]) if Net.active() else "none"
	if Friends.live_pids.size() > 0:
		room += ", %d friend windows on this machine" % Friends.live_pids.size()
	var step_ms := phys_ms / float(maxi(1, steps))                         # what a step cost by the wall clock, the engine's own part and a preempted one in it
	var frame_ms := (span * 1000.0 - phys_ms) / float(maxi(1, frames))     # and a frame's rest: scripts, drawing, waiting on the card
	_log("%s  SLOW %.1f s  game speed %.0f%% (%.0f of %.0f steps a second)  %.0f frames a second, %d of %d over 33 ms, worst %.0f ms  a step %.1f ms, the rest of a frame %.1f ms (card %.1f)  men %d  bodies awake %d  draws %d  room %s  => %s" % [
		Time.get_datetime_string_from_system(), span, speed * 100.0, float(steps) / span, float(Engine.physics_ticks_per_second) * Engine.time_scale, fps, over, frames, worst,
		step_ms, frame_ms, float(w.get("gpu", 0.0)), men, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(w.get("calls", 0)), room,
		slow_cause(steps, span, phys_ms, float(Engine.physics_ticks_per_second))])
	_sw_n += 1
	_census_ask(now)

## What a slow stretch came of, by where its seconds went: the steps' share of the second (`phys_ms` of `span` s, the steps a second there should be at
## `ticks`), and what is left for the frames. A step dearer than the 8.3 ms there is for it, however it came to be (too many fighters for the processor, the
## processor shared: the CPU line that follows says which) is what slows the game; with steps within it and the frames not too dear, it was not getting the
## processor or was waiting.
static func slow_cause(steps: int, span: float, phys_ms: float, ticks: float) -> String:
	if steps <= 0 or span <= 0.0 or ticks <= 0.0:
		return "no physics step in the stretch"
	var step := phys_ms / float(steps)
	var budget := 1000.0 / ticks
	var share := phys_ms / (span * 1000.0)
	if step > budget * 1.05:
		return "STEPS TOO COSTLY: a step %.1f ms of the %.1f there is (%.0f ms of every second at full speed) and the steps are %.0f%% of the time" % [step, budget, step * ticks, share * 100.0]
	if share < 0.5:
		return "FRAMES TOO COSTLY: the steps are %.0f%% of the time, the frames the rest (drawing, scripts, waiting on the card)" % (share * 100.0)
	return "NEITHER: steps (%.1f ms) and frames are within what the machine does, yet it fell behind: it was not getting the processor (see the CPU line) or the card held it" % step

## The processor, as the processes of the machine share it: whom to ask is the system's (Windows: PowerShell's Get-Process, twice, three seconds apart; Linux: /proc), in a thread of
## its own, once in CENSUS_EVERY_S seconds and only in a slow stretch; the line comes after the stretch's.
const CENSUS_EVERY_S := 20.0
func _census_ask(now: float) -> void:
	if DisplayServer.get_name() == "headless" or _census_thread != null or now - _census_t < CENSUS_EVERY_S:
		return
	if not ["Windows", "Linux"].has(OS.get_name()):
		return
	_census_t = now
	_census_thread = Thread.new()
	_census_thread.start(_census_run.bind(Friends.live_pids))

func _census_run(friend_pids: PackedInt32Array) -> void:
	var samples := []   # [name, pid, % of one thread]
	if OS.get_name() == "Windows":
		var script := "$ErrorActionPreference='SilentlyContinue'; $a=@{}; Get-Process | ForEach-Object { $a[$_.Id] = $_.CPU }; Start-Sleep -Seconds 3; Get-Process | ForEach-Object { if ($a.ContainsKey($_.Id) -and $_.CPU -ne $null -and $a[$_.Id] -ne $null) { $d = [math]::Round(($_.CPU - $a[$_.Id]) * 100 / 3); if ($d -ge 2) { '{0}:{1}:{2}' -f $_.ProcessName, $_.Id, $d } } }"
		var out := []
		OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", script], out, false)
		for chunk in out:
			for l in String(chunk).split("\n", false):
				var f := l.strip_edges().split(":")
				if f.size() == 3 and String(f[1]).is_valid_int() and String(f[2]).is_valid_int():
					samples.append([String(f[0]), int(f[1]), int(f[2])])
	else:
		var a := _proc_jiffies()
		OS.delay_msec(3000)
		var b := _proc_jiffies()
		for pid in b:
			if a.has(pid):
				var d := int(round(float(int(b[pid][1]) - int(a[pid][1])) / 3.0))   # (jiffies of 1/100 s: a hundredth of a second a second is a percent)
				if d >= 2:
					samples.append([String(b[pid][0]), int(pid), d])
	call_deferred("_census_done", samples, friend_pids)

## Linux: pid -> [command, user + system jiffies], read off /proc.
static func _proc_jiffies() -> Dictionary:
	var out := {}
	var d := DirAccess.open("/proc")
	if d == null:
		return out
	for name in d.get_directories():
		if not String(name).is_valid_int():
			continue
		var f := FileAccess.open("/proc/%s/stat" % name, FileAccess.READ)
		if f == null:
			continue
		var line := f.get_line()
		var r := line.rfind(")")
		var l := line.find("(")
		if r < 0 or l < 0:
			continue
		var rest := line.substr(r + 2).split(" ")
		if rest.size() > 13:
			out[int(name)] = [line.substr(l + 1, r - l - 1), int(rest[11]) + int(rest[12])]
	return out

func _census_done(samples: Array, friend_pids: PackedInt32Array) -> void:
	if _census_thread != null:
		_census_thread.wait_to_finish()
		_census_thread = null
	_log("%s  CPU %s" % [Time.get_datetime_string_from_system(), census_line(samples, OS.get_processor_count(), friend_pids, OS.get_process_id())])

## The census as a line: how full the machine was (the busy processes' percent of one thread, together, of all its threads), this game, the friends' games
## (their pids, from Friends), and the busiest others by name (several of one name together), the way a slow stretch's CPU line reads.
static func census_line(samples: Array, threads: int, friend_pids: PackedInt32Array, self_pid: int) -> String:
	var total := 0
	var mine := 0
	var friends := 0
	var n_friends := 0
	var others := {}   # name -> [percent, how many]
	for s in samples:
		var pct := int(s[2])
		total += pct
		if int(s[1]) == self_pid:
			mine += pct
		elif friend_pids.has(int(s[1])):
			friends += pct
			n_friends += 1
		else:
			var o: Array = others.get(String(s[0]), [0, 0])
			others[String(s[0])] = [int(o[0]) + pct, int(o[1]) + 1]
	var names := others.keys()
	names.sort_custom(func(a, b): return int(others[a][0]) > int(others[b][0]))
	var parts := []
	for nm in names.slice(0, 6):
		parts.append("%s%s %d%%" % [nm, (" x%d" % int(others[nm][1])) if int(others[nm][1]) > 1 else "", int(others[nm][0])])
	var busy := float(total) / float(maxi(1, threads) * 100)
	return "over 3 s: the machine %.0f%% busy (%d threads; a percent here is of one thread)  this game %d%%  friend windows %d%% (%d)  others: %s" % [busy * 100.0, threads, mine, friends, n_friends, ", ".join(parts) if not parts.is_empty() else "none over 2%"]

## How much of its speed the game kept: the physics steps taken over the steps a second of the clock there should have been (the engine's
## ticks a second at its time scale: a replay in slow motion is not a game running slow).
static func slow_speed(steps: int, span: float, ticks: float, time_scale: float) -> float:
	if span <= 0.0 or ticks <= 0.0 or time_scale <= 0.0:
		return 1.0
	return float(steps) / span / (ticks * time_scale)

## A line in the record (the game's own start and end of a thing, from anywhere: `FpsMeter.note("match setup ...")`); not in the tests.
static func note(text: String) -> void:
	if not recording():
		return
	_log("%s  NOTE %s" % [Time.get_datetime_string_from_system(), text])

## The file `user://hitches.txt` made (or begun again, past HITCH_FILE_MAX) with what the machine is, then a line added.
static func _log(line: String) -> void:
	var f := FileAccess.open(log_path(), FileAccess.READ_WRITE if FileAccess.file_exists(log_path()) else FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > HITCH_FILE_MAX:
		f.close()
		f = FileAccess.open(log_path(), FileAccess.WRITE)   # (the oldest go: a new record from here)
		if f == null:
			return
		f.store_line(_machine())
	f.seek_end()
	f.store_line(line)
	f.close()

## The game's start: the file is there from now on, with what the machine is and where the file lies.
func _log_session() -> void:
	var f := FileAccess.open(log_path(), FileAccess.READ_WRITE if FileAccess.file_exists(log_path()) else FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > HITCH_FILE_MAX:
		f.close()
		f = FileAccess.open(log_path(), FileAccess.WRITE)
		if f == null:
			return
	f.seek_end()
	f.store_line("")
	f.store_line("%s  SESSION START  %s" % [Time.get_datetime_string_from_system(), _machine()])
	f.close()
	print("Performance log (frames over %.0f ms, stretches under %.0f%% speed, match starts): %s" % [HITCH_MS, SLOW_SPEED * 100.0, log_path()])

static func _machine() -> String:
	var gpu := RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "none"
	return "%s, %s (%d threads), graphics %s, Godot %s, game %s, window %s" % [OS.get_name(), OS.get_processor_name(), OS.get_processor_count(), gpu, String(Engine.get_version_info().get("string", "?")), String(ProjectSettings.get_setting("application/config/version", "?")), str(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else "none"]

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
