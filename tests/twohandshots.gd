extends Node
## Two-handed strokes (`-- --probe twohandshots`, needs a display): a longsword, a zweihander
## and a war hammer, each in both hands, held out right, left, high and low, and caught in the
## middle of a sweep, seen from the front and the side. PNGs go to SHOT_DIR.

const POSES := [
	{"name": "right", "x": 2.0, "y": 0.3},
	{"name": "left", "x": -2.0, "y": 0.3},
	{"name": "high", "x": 0.0, "y": 1.6},
	{"name": "low", "x": 0.6, "y": -1.0},
]
var m
var cam: Camera3D
var men := []

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 46.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3})
	m.me.f.teleport(Vector3(0, 0, 30))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	var pose := {"main": {"x": 0.2, "y": 0.2}, "power": true}
	for i in 3:
		var wk: String = ["longsword", "zweihander", "warhammer"][i]
		var e = m.spawn_fighter({"kind": "bot", "name": wk, "loadout": {"main": wk, "off": ""}, "team": 1, "pos": Vector3((i - 1) * 2.4, 0.1, 0.0), "yaw": PI, "skin": [0xc68a5a, 0xa8714a, 0xd9a57a][i]})
		e.erase("bot")
		e.drive = func(_e): return pose
		men.append(e.f)
	for i in 120:
		await get_tree().physics_frame
	for ps in POSES:
		pose.main = {"x": ps.x, "y": ps.y}
		for i in 150:
			await get_tree().physics_frame
		get_tree().paused = true
		await _snap(out, "two_%s_front.png" % ps.name, Vector3(0, 1.6, -6.0), Vector3(0, 1.1, 0))
		await _snap(out, "two_%s_side.png" % ps.name, Vector3(6.2, 1.8, -2.2), Vector3(0, 1.1, 0), 44.0)
		get_tree().paused = false
	# Caught in the middle of a sweep from right to left.
	pose.main = {"x": 2.0, "y": 0.3}
	for i in 150:
		await get_tree().physics_frame
	pose.main = {"x": -2.0, "y": 0.3}
	for i in 14:
		await get_tree().physics_frame
	get_tree().paused = true
	await _snap(out, "two_sweep_front.png", Vector3(0, 1.6, -6.0), Vector3(0, 1.1, 0))
	await _snap(out, "two_sweep_top.png", Vector3(0, 6.5, -2.5), Vector3(0, 0.9, 0), 50.0)
	get_tree().quit()
