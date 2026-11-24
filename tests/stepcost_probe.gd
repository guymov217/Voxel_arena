extends Node
## (scratch) Whether what a physics step costs depends on how many steps a frame takes (`-- --probe stepcost_probe`; env MEN (10), FRAME_MS (8: what a frame's own work is made to cost, to stand for the
## drawing and the scripts of a frame), SECS (6), CAPS ("2,3,4,6,12")). Real time on one core (`taskset -c 0`): for each cap of the steps a frame, a ring of bots fighting, the steps a second the game keeps, the
## frames a second, how many steps a frame took, and what a step cost by the wall clock from the first step's start to the frame's idle part (the `process_frame` signal: the steps' own, nothing of the frame's scripts).
var steps_in_frame := 0
var t_first := 0
var t_pf := 0
var win_us := 0       # the steps' wall time over the stretch
var win_steps := 0
var frames := 0
var measuring := false
var frame_ms := 8.0

func _physics_process(_dt: float) -> void:
	if steps_in_frame == 0:
		t_first = Time.get_ticks_usec()
	steps_in_frame += 1

func _on_pf() -> void:
	if steps_in_frame > 0 and measuring:
		win_us += Time.get_ticks_usec() - t_first
		win_steps += steps_in_frame
	steps_in_frame = 0

func _process(_dt: float) -> void:
	if measuring:
		frames += 1
	OS.delay_usec(int(frame_ms * 1000.0))   # (a frame's own work: drawing, scripts)

func _ready() -> void:
	get_tree().process_frame.connect(_on_pf)
	frame_ms = float(OS.get_environment("FRAME_MS")) if OS.get_environment("FRAME_MS") != "" else 8.0
	var men := int(OS.get_environment("MEN")) if OS.get_environment("MEN") != "" else 10
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 6
	var caps: PackedStringArray = (OS.get_environment("CAPS") if OS.get_environment("CAPS") != "" else "2,3,4,6,12").split(",")
	Net.overload_on = false
	Fighter.process_in_headless = true
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -20))
	var weapons := ["gladius", "axe", "mace", "spear"]
	for i in men:
		var a := TAU * i / men
		var pos := Vector3(sin(a) * 4.0, 0.1, cos(a) * 4.0)
		m.spawn_fighter({"kind": "bot", "name": "P%d" % i, "loadout": {"main": weapons[i % 4], "off": "roundShield" if i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
	for c in caps:
		Engine.max_physics_steps_per_frame = int(c)
		# the same fight for each cap would need the same men: they fight on, which is what is wanted (the load of a clump)
		for s in 2:
			await get_tree().create_timer(1.0).timeout   # (warm)
		win_us = 0
		win_steps = 0
		frames = 0
		var f0 := Engine.get_physics_frames()
		var w0 := Time.get_ticks_usec()
		measuring = true
		await get_tree().create_timer(float(secs)).timeout
		measuring = false
		var wall := float(Time.get_ticks_usec() - w0) / 1e6
		var steps := Engine.get_physics_frames() - f0
		var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
		print("STEPCOST cap %2s: %5.1f steps a second (%3.0f%% of 120), %4.1f frames a second, %.2f steps a frame, a step %.2f ms by the wall clock to the idle part, a frame's rest %.1f ms; %d alive" % [
			c, float(steps) / wall, float(steps) / wall / 1.2, float(frames) / wall, float(win_steps) / float(maxi(1, frames)), float(win_us) / 1000.0 / float(maxi(1, win_steps)),
			(wall * 1000.0 - float(win_us) / 1000.0) / float(maxi(1, frames)), alive])
	get_tree().quit(0)
