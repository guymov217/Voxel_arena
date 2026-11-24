extends Node
## What a physics step costs is read to where the frame's own work begins (`Net._time_steps`, `FpsMeter`): not to whatever ran in the process before the reader's own node (the user's record: a step
## read 9.4 ms by `Net` where the meter's own window said 5.9: about 5.5 ms of every frame, 2.7 ms a step at the two steps a frame of an overloaded host, held the room in its slow motion).

var t

## A node whose process comes before `Net`'s and takes `us` of every frame (a frame's own work, here before the reader).
class Burner extends Node:
	var us := 0
	func _init(prio: int, micro: int) -> void:
		process_priority = prio
		us = micro
	func _process(_dt: float) -> void:
		OS.delay_usec(us)

## A listener of the frame that takes `us` when it comes (a coroutine that waited for the frame: the staged builds).
class Waiter extends Node:
	var us := 0
	var on := true
	func _ready() -> void:
		_loop()
	func _loop() -> void:
		while on and is_inside_tree():
			await get_tree().process_frame
			OS.delay_usec(us)

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_step_is_not_read_dearer_for_what_the_frame_does_before_the_reader() -> void:
	var was_ms: float = Net.step_ms
	var was_over: bool = Net.overloaded
	Net.step_ms = 0.0
	Net._frame_steps = 0
	var b := Burner.new(-1000, 12000)   # (its process comes before Net's, as the meter's and whatever ran first did)
	add_child(b)
	var w := Waiter.new()
	w.us = 6000
	add_child(w)
	await _steps(60)
	var read: float = Net.step_ms
	t.check(read > 0.0 and read < 4.0, "the steps are read as the steps (%.2f ms), not with the 18 ms of work the frame did before Net's own process" % read)
	b.queue_free()
	w.on = false
	w.queue_free()
	await _steps(2)
	Net.step_ms = was_ms
	Net.overloaded = was_over

## A frame whose steps' end was not marked (a stale mark from an earlier frame) is read to now, as it was.
func test_the_window_falls_back_to_now_without_a_mark() -> void:
	var was_ms: float = Net.step_ms
	Net.step_ms = 0.0
	Net._frame_t0 = Time.get_ticks_usec() - 4000
	Net._frame_steps = 2
	Net._frame_end_us = Net._frame_t0 - 5   # (before the frame's first step: not this frame's)
	Net._time_steps()
	t.check(Net.step_ms >= 2.0 and Net.step_ms < 6.0, "read to now: 4 ms over two steps (%.2f)" % Net.step_ms)
	Net.step_ms = 0.0
	Net._frame_t0 = Time.get_ticks_usec() - 4000
	Net._frame_steps = 2
	Net._frame_end_us = Net._frame_t0 + 3000
	Net._time_steps()
	t.check(is_equal_approx(Net.step_ms, 1.5), "read to the mark: 3 ms over two steps (%.2f)" % Net.step_ms)
	Net.step_ms = was_ms

## The meter says where a slow stretch's frames went.
func test_the_composition_of_a_slow_frame_is_told() -> void:
	var fc := {"n": 10, "steps": 20, "pf": 120000, "between": 30000, "scripts": 50000, "inner": 90000, "tail": 70000}
	var s := FpsMeter.compose_text(fc, 12, 0.6)
	t.check(s.contains("a frame of 50.0 ms") and s.contains("steps 12.0 (2.0 of them") and s.contains("a step's gap 9.0") and s.contains("the last of a frame 7.0"), "the steps: %s" % s)
	t.check(s.contains("between them and the scripts 3.0, scripts 5.0, drawing and waiting 30.0"), "and the rest of the frame: %s" % s)
	t.check(FpsMeter.compose_text({"n": 0}, 5, 1.0).contains("no step"), "a stretch without steps says so")

## The meter itself, in a real frame loop: what ran between the steps and its process, and the scripts' process, are told apart.
func test_the_meter_tells_the_coroutines_from_the_scripts() -> void:
	var fm := FpsMeter.new()
	add_child(fm)
	var b := Burner.new(0, 9000)    # (a script of the frame: 9 ms)
	add_child(b)
	var w := Waiter.new()
	w.us = 5000                     # (a coroutine that waited for the frame: 5 ms)
	add_child(w)
	await _steps(5)
	fm._fc = {"n": 0, "steps": 0, "pf": 0, "between": 0, "scripts": 0, "inner": 0, "tail": 0}
	await _steps(50)
	var n := int(fm._fc.n)
	t.check(n >= 40, "frames with steps were counted (%d)" % n)
	var between := float(fm._fc.between) / 1000.0 / float(maxi(1, n))
	var scripts := float(fm._fc.scripts) / 1000.0 / float(maxi(1, n))
	var pf := float(fm._fc.pf) / 1000.0 / float(maxi(1, n))
	t.check(between > 4.0 and between < 9.0, "the coroutine's 5 ms is between the steps and the process (%.1f)" % between)
	t.check(scripts > 8.0 and scripts < 13.0, "the script's 9 ms is in the scripts (%.1f)" % scripts)
	t.check(pf < 4.0, "and neither is in the steps (%.1f)" % pf)
	b.queue_free()
	w.on = false
	w.queue_free()
	fm.queue_free()
	await _steps(2)
