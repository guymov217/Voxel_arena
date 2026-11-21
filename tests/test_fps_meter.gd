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
