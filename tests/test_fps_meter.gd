extends Node
## The frame rate's meter (F3, FpsMeter): what it reads off the frames, and the key that shows it
## and puts it away, remembered in the settings.

var t

## A second of frames at sixty a second, and a slow one three seconds before: the mean is the
## last second's, the worst and the slow ones the last five seconds'.
func test_the_meter_reads_the_frames() -> void:
	var frames := []
	var now := 100.0
	frames.append([now - 3.0, 41.0])
	for i in 60:
		frames.append([now - 1.0 + (i + 1) / 60.0, 1000.0 / 60.0])
	var out: Array = FpsMeter.lines(frames, now, 60.0, {"physics": 2.5, "frame": 3.3, "draw": 4.0, "gpu": 6.5})
	t.eq(out.size(), 2, "two lines")
	var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(String(out[0]), "", true)
	t.check(plain.begins_with("60 FPS"), "the frames a second first (%s)" % plain)
	t.check(plain.contains("16.7 ms a frame"), "the last second's mean frame (%s)" % plain)
	t.check(plain.contains("worst in 5 s 41.0 ms") and plain.contains("1 frames over 33 ms"), "the worst of the last five seconds, and how many were slow (%s)" % plain)
	t.eq(String(out[1]), "physics 2.5 ms a step · frame without physics 3.3 ms (drawing 4.0 ms) · graphics card 6.5 ms", "and what the last frame's work took")
	# The steps a second the game really takes, beside the 120 it is meant to: red when it falls short.
	var kept: Array = FpsMeter.lines(frames, now, 60.0, {"physics": 2.5, "frame": 3.3, "draw": 4.0, "gpu": 6.5, "steps": 119.6})
	var plain_kept := RegEx.create_from_string("\\[[^\\]]*\\]").sub(String(kept[1]), "", true)
	t.check(plain_kept.ends_with("graphics card 6.5 ms · 120 of 120 steps a second"), "the steps it keeps (%s)" % plain_kept)
	var slow_run: Array = FpsMeter.lines(frames, now, 60.0, {"physics": 2.5, "frame": 3.3, "draw": 4.0, "gpu": 6.5, "steps": 84.0})
	t.check(String(slow_run[1]).contains("[color=#d9534f]84[/color] of 120 steps"), "and in red when the host falls behind (%s)" % String(slow_run[1]))
	# The C++ core, when the work says so: green when it is there, red when the game runs without it.
	var with_core: Array = FpsMeter.lines(frames, now, 60.0, {"physics": 2.5, "frame": 3.3, "draw": 4.0, "gpu": 6.5, "native": true})
	var plain_on := RegEx.create_from_string("\\[[^\\]]*\\]").sub(String(with_core[1]), "", true)
	t.check(plain_on.ends_with("native core on"), "the native core on (%s)" % plain_on)
	var no_core: Array = FpsMeter.lines(frames, now, 60.0, {"physics": 2.5, "frame": 3.3, "draw": 4.0, "gpu": 6.5, "native": false})
	var plain_off := RegEx.create_from_string("\\[[^\\]]*\\]").sub(String(no_core[1]), "", true)
	t.check(plain_off.ends_with("native core OFF (slower)") and String(no_core[1]).contains("#d9534f"), "and off, in red (%s)" % plain_off)
	# (Nothing slow: no frame counted.)
	var calm := RegEx.create_from_string("\\[[^\\]]*\\]").sub(String(FpsMeter.lines(frames.slice(1), now, 60.0, {})[0]), "", true)
	t.check(calm.contains("0 frames over 33 ms"), "nothing slow, nothing counted (%s)" % calm)

## Where the frame goes: the men's drawing and the match's work, and all the rest of what the frame without physics takes, with the
## draw calls beside them. Read only when the work has them (the meter's own lines are the same without).
func test_the_meter_says_where_the_frame_goes() -> void:
	var frames := [[99.5, 16.0]]
	var w := {"physics": 2.5, "frame": 5.0, "draw": 4.0, "gpu": 6.5, "men": 1.5, "match": 0.5, "calls": 180}
	var out: Array = FpsMeter.lines(frames, 100.0, 60.0, w)
	t.eq(out.size(), 3, "a third line")
	t.eq(String(out[2]), "in the frame: the men 1.5 ms · the match 0.5 ms · all the rest 3.0 ms · 180 draw calls", "the men, the match, what is left of the frame, the draw calls")
	# (The parts measured add up to more than the frame, as when one is timed over the other's frame: the rest is nothing, not less.)
	w.men = 7.0
	t.check(String(FpsMeter.lines(frames, 100.0, 60.0, w)[2]).contains("all the rest 0.0 ms"), "the rest is never below nothing")

## The clock is looked at only while the meter is shown: the men's drawing, the match, the parts and the arms in their hands.
func test_the_scripts_are_timed_only_while_the_meter_is_shown() -> void:
	var fm := FpsMeter.new()
	add_child(fm)
	var was: bool = FpsMeter.prof_on
	fm.show_meter(false)
	t.check(not FpsMeter.prof_on, "not timed while it is put away")
	fm.show_meter(true)
	t.check(FpsMeter.prof_on and FpsMeter.prof_men_us == 0 and FpsMeter.prof_match_us == 0, "timed, from nothing, once it is shown")
	fm.queue_free()
	await get_tree().process_frame
	t.check(not FpsMeter.prof_on, "and not once it is gone")
	FpsMeter.prof_on = was

## F3 shows it and puts it away, and the settings keep which.
func test_f3_shows_the_meter_and_it_is_remembered() -> void:
	var fm := FpsMeter.new()
	add_child(fm)
	t.check(not fm.visible, "put away at first")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	fm._unhandled_input(key)
	t.check(fm.visible and bool(Save.get_value("settings", {}).get("fps_meter", false)), "F3 shows it, and the settings keep it shown")
	fm._unhandled_input(key)
	t.check(not fm.visible and not bool(Save.get_value("settings", {}).get("fps_meter", true)), "F3 again puts it away")
	fm.queue_free()
	var st: Dictionary = Save.get_value("settings", {})
	st["fps_meter"] = true
	Save.set_value("settings", st)
	var again := FpsMeter.new()
	add_child(again)
	t.check(again.visible, "shown when the game starts if it was left shown")
	again.queue_free()
	await get_tree().process_frame

## A frame past a tenth of a second is written to user://hitches.txt with what the game knows of it (to be sent on with a video of a
## game that stopped); a smooth stretch writes nothing, and four a second at most are kept.
func test_a_long_frame_is_written_to_the_hitch_record() -> void:
	FpsMeter.force_record = true
	var path := FpsMeter.log_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var fm := FpsMeter.new()
	add_child(fm)
	fm.show_meter(true)
	fm._frames = [[0.0, 16.0], [0.1, 16.0], [0.2, 17.0]]
	fm._hitch_check(0.2)
	t.check(not FileAccess.file_exists(path), "smooth frames write nothing")
	FpsMeter.msg_seen = {"spawn": 1, "snap": 8}
	fm._frames = [[0.0, 16.0], [0.1, 16.0], [0.4, 150.0]]
	fm._hitch_check(5.0)
	t.check(FileAccess.file_exists(path), "a frame of 150 ms is written")
	var text := FileAccess.get_file_as_string(path)
	t.check(text.contains("frame 150 ms") and text.contains("steps ") and text.contains("snap x8") and text.contains("spawn x1"), "with its length, its steps and the messages that came in (%s)" % text.left(200))
	fm._hitch_check(5.1)
	t.eq(FileAccess.get_file_as_string(path).split("\n", false).size(), 1, "another within a quarter of a second adds nothing")
	DirAccess.remove_absolute(path)
	FpsMeter.force_record = false
	fm.queue_free()
	await get_tree().process_frame

## A game in slow motion has no long frame to show for it (its frames are all a little long): a stretch in which it kept under 97% of its speed
## is written whether or not the meter is shown (user: the file never appeared; no frame was over 60 ms).
func test_a_stretch_under_speed_is_written_with_the_meter_put_away() -> void:
	FpsMeter.force_record = true
	var path := FpsMeter.log_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	t.check(is_equal_approx(FpsMeter.slow_speed(240, 2.0, 120.0, 1.0), 1.0), "240 steps in 2 s of 120 a second: the whole speed")
	t.check(is_equal_approx(FpsMeter.slow_speed(48, 2.0, 120.0, 0.2), 1.0), "a replay at a fifth of the time is not a game running slow")
	t.check(FpsMeter.slow_speed(100, 2.0, 120.0, 1.0) < 0.5, "100 steps in 2 s: under half")
	var fm := FpsMeter.new()
	add_child(fm)
	fm.show_meter(false)
	t.check(fm.is_processing(), "the meter put away still keeps the record")
	fm._frames = [[0.0, 40.0]]
	fm._slow_check(0.0)   # (the window begins)
	fm._frames = [[2.5, 40.0]]
	fm._slow_check(2.5)   # (it ends: no physics step in it)
	t.check(FileAccess.file_exists(path), "the stretch is written")
	var text := FileAccess.get_file_as_string(path)
	t.check(text.contains("SLOW 2.5 s") and text.contains("game speed 0%") and text.contains("men 0") and text.contains("room none"), "with its length, its speed and what was asked of the machine (%s)" % text.left(160))
	DirAccess.remove_absolute(path)
	FpsMeter.force_record = false
	FpsMeter.note("a note in the tests goes nowhere")
	t.check(not FileAccess.file_exists(path), "and a note is written only by a game with a screen")
	fm.queue_free()
	await get_tree().process_frame

## The file is begun again past its size, with what the machine is at the head.
func test_the_record_begins_again_past_its_size_with_the_machine_at_its_head() -> void:
	FpsMeter.force_record = true
	var path := FpsMeter.log_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x".repeat(FpsMeter.HITCH_FILE_MAX + 10))
	f.close()
	FpsMeter._log("a line")
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	t.eq(lines.size(), 2, "the old record is gone, a head and the line are there")
	t.check(String(lines[0]).contains("Godot") and String(lines[0]).contains("threads"), "the head says what the machine is (%s)" % String(lines[0]).left(100))
	t.eq(String(lines[1]), "a line", "and the line follows")
	DirAccess.remove_absolute(path)
	FpsMeter.force_record = false

## A slow stretch says what it came of (the slow-motion's diagnosis): steps dearer than the 8.3 ms there is, frames dearer than the steps, or neither
## (the game was not getting the processor).
func test_a_slow_stretch_says_what_it_came_of() -> void:
	t.check(FpsMeter.slow_cause(60, 2.0, 1200.0, 120.0).begins_with("STEPS TOO COSTLY"), "60 steps of 20 ms in two seconds: the steps")
	t.check(FpsMeter.slow_cause(240, 2.0, 400.0, 120.0).begins_with("FRAMES TOO COSTLY"), "steps of 1.7 ms and a fifth of the time: the frames")
	t.check(FpsMeter.slow_cause(200, 2.0, 1400.0, 120.0).begins_with("NEITHER"), "steps of 7 ms, most of the time, behind all the same: not getting the processor")
	t.check(FpsMeter.slow_cause(0, 2.0, 0.0, 120.0).begins_with("no physics step"), "no step at all says so")
	var text := FpsMeter.slow_cause(60, 2.0, 1200.0, 120.0)
	t.check(text.contains("20.0 ms") and text.contains("8.3"), "with the step's cost and the budget (%s)" % text)

## The processor's census as a line: who had it.
func test_the_census_names_who_had_the_processor() -> void:
	var samples := [["godot", 100, 98], ["godot", 101, 27], ["godot", 102, 27], ["obs64", 200, 41], ["chrome", 300, 12], ["chrome", 301, 10]]
	var line := FpsMeter.census_line(samples, 8, PackedInt32Array([101, 102]), 100)
	t.check(line.contains("27% busy") and line.contains("8 threads"), "the machine's fullness: 215 of 800 (%s)" % line)
	t.check(line.contains("this game 98%"), "this game")
	t.check(line.contains("friend windows 54% (2)"), "the friends' games by their pids, together")
	t.check(line.contains("obs64 41%") and line.contains("chrome x2 22%"), "the others by name, several of a name together")
	t.check(FpsMeter.census_line([], 4, PackedInt32Array(), 1).contains("none over 2%"), "an empty machine says so")
	if OS.get_name() == "Linux":
		var j := FpsMeter._proc_jiffies()
		t.check(j.has(OS.get_process_id()) and String(j[OS.get_process_id()][0]) != "", "on Linux the census reads /proc: this game is in it")

## What the frame's steps took, by the wall clock: read between this node's first physics step of a frame and its process (it comes first in both).
func test_the_steps_of_a_frame_are_timed_between_the_first_step_and_the_process() -> void:
	var fm := FpsMeter.new()
	add_child(fm)
	t.eq(fm.process_priority, -100000, "first in every frame")
	fm._process(0.0)   # (the first frame begins the stretch's window)
	fm._physics_process(0.0)
	OS.delay_usec(3000)
	fm._physics_process(0.0)
	fm._process(0.0)
	t.check(fm._sw_phys_us >= 3000, "the frame's steps took at least the 3 ms they were held for (%d us)" % fm._sw_phys_us)
	t.eq(fm._ps_n, 0, "and the count starts anew")
	fm.queue_free()
	var fr := Friends.new()
	add_child(fr)
	fr.friends.append({"pid": 4000000, "persona": 0, "name": "x", "at": 0})
	fr.changed.emit()
	t.eq(Array(Friends.live_pids), [4000000], "the friends' games' pids are kept for the census")
	fr.friends.clear()   # (kill_all would stop a game of that pid)
	fr.queue_free()
	await get_tree().process_frame
	t.eq(Friends.live_pids.size(), 0, "and let go with the friends")

## The record lies in the game's folder (the project's, run from the editor; the executable's, exported), not in the user data folder where nobody finds it.
func test_the_record_is_kept_in_the_games_folder() -> void:
	var p := FpsMeter.log_path()
	t.check(p.get_file() == "hitches.txt", "it is called hitches.txt (%s)" % p)
	t.check(p.get_base_dir() == ProjectSettings.globalize_path("res://").trim_suffix("/"), "in the project's folder (%s)" % p.get_base_dir())
	t.check(not FpsMeter.recording(), "and a game without a screen (the friends' games, these tests) keeps none of its own: it would write in the host's")
