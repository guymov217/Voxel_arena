extends Node
## A war hammer on a long haft (`-- --probe longhaftshots`, needs a display): swept right to
## left and back, filmed from behind like the fight camera; frames go to SHOT_DIR.
var m
var cam: Camera3D

static func long_hammer(grips) -> Dictionary:
	var d: Dictionary = Data.preset("warhammer").duplicate(true)
	var vox := []
	for v in d.voxels:
		if v[4] == "blunt" and v[3] != "wood":
			vox.append([v[0], v[1] + 26, v[2], v[3], v[4]])
	for y in 52:
		vox.append([0, y, 0, "wood", "grip" if y < 14 else "blunt"])
	d.voxels = vox
	d.name = "Long hammer"
	d.erase("stats")
	if grips != null:
		d.grips = grips
	return d

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var g = null if OS.get_environment("GRIPS") == "" else {"main": [0, 3, 0], "off": [0, 0, 0]}
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3, "loadout": {"main": long_hammer(g), "off": ""}})
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	var f: Fighter = m.me.f
	var pose := {"main": {"x": 2.0, "y": 0.2}, "power": true}
	m.me.drive = func(_e): return pose
	for i in 200:
		await get_tree().physics_frame
	var k := 0
	for leg in [[2.0, -2.0], [-2.0, 2.0]]:
		for i in 60:
			pose.main = {"x": lerpf(leg[0], leg[1], minf(1.0, i / 30.0)), "y": 0.2}
			await get_tree().physics_frame
			if i % 10 == 0:
				var t := f.torso.global_transform
				var back := t.basis * Vector3(0, 0, -1)
				back.y = 0
				cam.global_position = f.torso.global_position + back.normalized() * 3.6 + Vector3(0, 1.0, 0)
				cam.look_at(f.torso.global_position + Vector3(0, 0.1, 0), Vector3.UP)
				cam.fov = 60
				get_tree().paused = true
				for j in 3:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out.path_join("lh_%02d.png" % k))
				k += 1
				get_tree().paused = false
	get_tree().quit()
