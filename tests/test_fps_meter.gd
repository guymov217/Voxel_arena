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
