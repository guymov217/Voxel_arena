extends Node
## Store shots of single moments (`-- --probe momentshots`, needs a display; 1920x1080): the
## forge with two weapons on the anvil, a blade landing with the blood still in the air, a
## thunder pot going off among the fighters, and a nail pot bursting on a man. Time is all but
## stopped a few ticks after the moment so the spray, the sparks and the nails hang in the
## frame. PNGs go to SHOT_DIR; SHOT_ONLY picks one.

var menu
var out := ""
var big: Dictionary = {}
var want_j := 30.0

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("SHOT_ONLY")
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await _ticks(60)
	for job in [["09_forge_executioner", "executionerAxe", Vector2(0.75, 0.3), 1.0], ["10_forge_chair", "chair", Vector2(-0.7, 0.3), 1.0]]:
		if only == "" or only == job[0]:
			await _forge(job[0], job[1], job[2], job[3])
	if only == "" or only == "11_blood_strike":
		await _strike()
	if only == "" or only == "12_thunder_pot":
		await _pot("12_thunder_pot", "pot_thunder")
	if only == "" or only == "13_nail_pot":
		await _pot("13_nail_pot", "pot_nail")
	get_tree().quit()

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _save(nm: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("saved ", nm)

func _freeze(on: bool) -> void:
	Engine.time_scale = 0.0005 if on else 1.0

func _forge(nm: String, preset: String, orbit: Vector2, dist: float) -> void:
	var fg = load("res://scripts/ui/forge.gd").new()
	menu.add_child(fg)
	fg.open(Data.preset(preset), 900, func(_d, _c): pass)
	fg.orbit = orbit
	fg.dist *= dist
	fg._place_camera()
	await _ticks(30)
	await _save(nm)
	fg.queue_free()
	await _ticks(5)

func _start(mode: String) -> Match:
	menu.start({"mode": mode, "autopilot": true, "decrees": [], "hazards": []})
	var m: Match = menu.match_
	menu.hud.visible = false
	return m

## A camera `dist` from `c`, on the side nobody blocks, a little above, looking at it.
func _frame(m: Match, c: Vector3, across: Vector3, dist: float, fov: float, up := 0.25, skip := []) -> void:
	across.y = 0
	if across.length() < 0.1:
		across = Vector3(1, 0, 0)
	var side := across.normalized().cross(Vector3.UP)
	var clear := func(sd: Vector3) -> float:
		var eye: Vector3 = c + sd * dist
		var worst := 9.0
		for e in m.entities:
			if not is_instance_valid(e.f) or skip.has(e.f):
				continue
			var q: Vector3 = e.f.torso.global_position
			var t := clampf((q - eye).dot(c - eye) / maxf(0.01, (c - eye).length_squared()), 0.0, 0.85)
			worst = minf(worst, q.distance_to(eye.lerp(c, t)))
		return worst - (c + sd).length() * 0.01
	if clear.call(-side) > clear.call(side):
		side = -side
	m.set_process(false)
	m.cam.fov = fov
	m.cam.global_position = c + side * dist + Vector3(0, up, 0)
	m.cam.look_at(c, Vector3.UP)

func _on_hit(h: Dictionary) -> void:
	if big.is_empty() and h.get("weapon") != null and float(h.get("J", 0.0)) > want_j and ["edge", "point"].has(h.get("type")) and h.get("p") is Vector3:
		big = h

## A blade lands: wait for a hard cut, let the blood fly for a few ticks, stop time, frame it close.
func _strike() -> void:
	var m := _start("duel")
	await _ticks(240)
	big = {}
	m.combat.hit.connect(_on_hit)
	var waited := 0
	want_j = 30.0
	while big.is_empty() and waited < 120 * 60:
		await get_tree().physics_frame
		waited += 1
		if waited % 900 == 0:
			want_j *= 0.75
	await _ticks(5)
	_freeze(true)
	var a = big.attacker
	var v = big.char
	_frame(m, big.p, (v.torso.global_position - a.torso.global_position) if a is Fighter and v is Fighter else Vector3.RIGHT, 1.7, 42.0, 0.15, [a, v])
	await _save("11_blood_strike")
	_freeze(false)
	print("  J=%.0f waited %.1f s" % [float(big.J), waited / 120.0])

## A pot breaks among the fighters: thunder (the blast) or nails (a burst of iron).
func _pot(nm: String, type: String) -> void:
	var m := _start("ffa" if type == "pot_thunder" else "duel")
	await _ticks(120 * 5)
	# The two fighters closest together are the target.
	var live := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive)
	var pa: Fighter = live[0].f
	var pb: Fighter = live[min(1, live.size() - 1)].f
	var best := INF
	for x in live:
		for y in live:
			if x != y and x.f.torso.global_position.distance_to(y.f.torso.global_position) < best:
				best = x.f.torso.global_position.distance_to(y.f.torso.global_position)
				pa = x.f
				pb = y.f
	var c := (pa.torso.global_position + pb.torso.global_position) * 0.5
	if type == "pot_thunder":
		var at := Vector3(c.x, 0.25, c.z)
		m.throwables.explode(type, at, null)
		await _ticks(13)
		_freeze(true)
		_frame(m, c + Vector3(0, 0.3, 0), pb.torso.global_position - pa.torso.global_position, 4.6, 55.0, 0.5)
	else:
		# Broken on the man's chest, from the camera's side.
		var dir := (pb.torso.global_position - pa.torso.global_position).normalized()
		var at := pb.torso.global_position - dir * 0.28 + Vector3(0, 0.1, 0)
		m.throwables.explode(type, at, pa, dir, pb, pb.torso)
		await _ticks(4)
		_freeze(true)
		_frame(m, pb.torso.global_position, dir, 2.3, 48.0, 0.2, [pa, pb])
	await _save(nm)
	_freeze(false)
