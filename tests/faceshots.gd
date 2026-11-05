extends Node
## Faces close (`-- --probe faceshots`, needs a display): six men of the strong look in a row, bots
## with their own faces (hair, beard, the pieces chance gives them) and men with face pieces chosen,
## each seen from in front and from three-quarters, close. FINE=0: the heads as their voxels are
## (a before picture). PNGs to SHOT_DIR.

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 24.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	var warm := 4 if RenderingServer.render_loop_enabled else 40
	RenderingServer.render_loop_enabled = true
	for i in warm:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	Physique.fine_heads = OS.get_environment("FINE") != "0"
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
	RenderingServer.render_loop_enabled = false
	var men := []
	var specs := [
		{"name": "Marcus Varro", "skin": 0xc68a5a, "faces": []},
		{"name": "Gaius Brennus", "skin": 0xe8b894, "faces": ["eyes_blue", "mouth_grin"]},
		{"name": "Tiberius Afer", "skin": 0x7a4e34, "faces": ["eyes_angry", "mouth_stern"]},
		{"name": "Quintus Rufus", "skin": 0xd9a57a, "faces": ["eyes_green", "mouth_smirk"], "armor": ["beard_full"]},
		{"name": "Decimus Crassus", "skin": 0xa8714a, "faces": ["eyes_wink", "mouth_snarl"]},
		{"name": "Lucius Atticus", "skin": 0xc89870, "faces": ["eyes_side", "mouth_shout"], "armor": ["beard_goatee"]},
	]
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var e = m.spawn_fighter({"kind": "bot", "name": sp.name, "loadout": {"main": "", "off": "", "armor": sp.get("armor", [])}, "team": 1, "pos": Vector3((i - 2.5) * 1.6, 0.1, 0.0), "yaw": PI, "skin": sp.skin})
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.1, "y": 0.1}, "off": {"x": -0.35, "y": 0.1}}
		var f: Fighter = e.f
		if not (sp.faces as Array).is_empty():
			f.face_ids = sp.faces
			Physique.dress(f)
		men.append(f)
	for i in 150:
		await get_tree().physics_frame
	get_tree().paused = true
	# BOTH=1: the heads as their voxels are first (front only), then the fine ones, in one run.
	var sets := [Physique.fine_heads]
	if OS.get_environment("BOTH") == "1":
		sets = [false, true]
	for fine in sets:
		if fine != Physique.fine_heads or sets.size() > 1:
			Physique.fine_heads = fine
			for f in men:
				Physique.dress(f)
		var tag := "" if sets.size() == 1 else ("_fine" if fine else "_now")
		for k in men.size():
			var f: Fighter = men[k]
			var h: Vector3 = f.head.global_position
			# He faces -z.
			await _snap(out, "face_%d_front%s.png" % [k, tag], h + Vector3(0.0, 0.05, -1.25), h + Vector3(0, 0.0, 0))
			if fine or sets.size() == 1:
				await _snap(out, "face_%d_three%s.png" % [k, tag], h + Vector3(0.75, 0.12, -1.0), h + Vector3(0, -0.02, 0))
	get_tree().quit()
