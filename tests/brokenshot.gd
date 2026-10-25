extends Node
## A longsword broken in two (`-- --probe brokenshot`, needs a display): the broken-off half on
## the sand, then in the other hand by its broken end. PNGs go to SHOT_DIR.

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 42.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3, "loadout": {"main": "gladius", "off": ""}})
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	var f: Fighter = m.me.f
	var box := {"i": {"main": {"x": 0.3, "y": 0.2}, "off": {"x": -0.3, "y": 0.1}}}
	m.me.drive = func(_e): return box.i
	for i in 60:
		await get_tree().physics_frame
	var w: Weapon = f.weapons.R
	var lo := INF
	var hi := -INF
	for v in w.vox:
		if v[4] != "grip":
			lo = minf(lo, float(v[1]))
			hi = maxf(hi, float(v[1]))
	var cut := int(round((lo + hi) * 0.5))
	var row := []
	for i in w.vox.size():
		if int(w.vox[i][1]) == cut:
			row.append(i)
	w.spend(row)
	for i in 120:
		await get_tree().physics_frame
	var piece: Weapon = m.combat.loose_weapons.back()
	var p := f.torso.global_position
	var yq := Quaternion(Vector3.UP, f.yaw)
	await _snap(out, "broken_sand.png", piece.global_position + yq * Vector3(0.9, 0.9, 1.2), piece.global_position, 40.0)
	f.pick_up("L", piece)
	for i in 90:
		await get_tree().physics_frame
	p = f.torso.global_position
	await _snap(out, "broken_held.png", p + yq * Vector3(0.4, 0.4, 2.4), p + Vector3(0, 0.1, 0), 46.0)
	get_tree().quit()
