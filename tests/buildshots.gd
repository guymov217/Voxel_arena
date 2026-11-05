extends Node
## The new look's men (`-- --probe buildshots`, needs a display): the three builds side by side,
## a man in armour, a man cut open and a man with his forearm broken through, from in front, from
## three-quarters, from behind and close. STYLE=strong: the same men in the old look (a before
## picture); BOTH=1: both, the old first. PNGs to SHOT_DIR.

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
	var styles := [OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"]
	if OS.get_environment("BOTH") == "1":
		styles = ["strong", "human"]
	Physique.forced = styles[0]
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
	var specs := [
		{"name": "Marcus Varro", "skin": 0xc68a5a, "build": "hero"},
		{"name": "Gaius Brennus", "skin": 0xe8b894, "build": "champion"},
		{"name": "Tiberius Afer", "skin": 0x7a4e34, "build": "brute"},
		{"name": "Quintus Rufus", "skin": 0xd9a57a, "build": "hero", "armor": ["helmet", "lorica", "manica", "greaves"]},
		{"name": "Decimus Crassus", "skin": 0xa8714a, "build": "champion"},
		{"name": "Lucius Atticus", "skin": 0xc89870, "build": "brute"},
		{"name": "Old Veteran", "skin": 0xb07a52, "build": "champion", "body": true},
		{"name": "Designed Armour", "skin": 0xc68a5a, "build": "brute", "designs": true},
	]
	var men := []
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var arm: Array = sp.get("armor", [])
		if sp.get("designs", false):
			# Pieces made at the armourer's bench (Armory.design_piece): a steel cuirass capped over
			# the shoulders, bronze greaves, painted iron bracers; and a crest of plates standing up
			# off a helmet (the bench lets plates stand out from the part).
			var crest := Armory.design_piece("head", "bronze", 0.45, 1.0, false, true, "Crested helm")
			var cells: Array = crest.parts.head
			for y in range(6, 9):
				for z in range(0, 5):
					cells.append([2, y, z])
			arm = Armory.register([Armory.design_piece("torso", "steel", 0.25, 1.0, false, true, "Cuirass"),
				Armory.design_piece("shins", "bronze", 0.2, 0.85, false, false, "Greaves"),
				Armory.design_piece("forearms", "iron", 0.3, 0.9, false, false, "Bracers"), crest])
		var spec := {"kind": "bot", "name": sp.name, "loadout": {"main": "", "off": "", "armor": arm}, "team": 1, "pos": Vector3((i - 2.5) * 1.3, 0.1, 0.0), "yaw": 0.0, "skin": sp.skin}
		if sp.get("body", false):
			# A veteran of the campaign: a peg for his left shin, a hook and a blade for his hands,
			# old wounds healed into scars on his chest and his thigh.
			var b := Body.empty()
			var dent := []
			for x in range(6, 10):
				for y in range(13, 16):
					for z in [8, 9]:
						dent.append((x * 22 + y) * 10 + z)   # (the torso's grid: 16 x 22 x 10, the front at z 9)
			b.scars = {"torso": dent}
			b.missing = ["shinL", "forearmR", "forearmL"]
			spec["body"] = Body.apply(Body.apply(Body.apply(b, "peg:shinL"), "blade:forearmR"), "hook:forearmL")
		var e = m.spawn_fighter(spec)
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.15, "y": 0.0}, "off": {"x": -0.3, "y": -0.2}}
		var f: Fighter = e.f
		f.build_pref = sp.build
		Physique.dress(f)
		men.append(f)
	for i in 120:
		await get_tree().physics_frame
	# The fifth man cut open across the belly and the thigh; the sixth's right forearm broken through.
	var cut: Fighter = men[4]
	var h: Vector3 = cut.torso.half_ext
	cut.torso.remove_voxels(Array(cut.torso.voxels_within(Vector3(0.04, -0.06, h.z), 0.075)))
	var th: VoxelPart = cut.by_name.thighL
	th.remove_voxels(Array(th.voxels_within(Vector3(0.0, 0.05, th.half_ext.z), 0.05)))
	var arm: VoxelPart = men[5].by_name.forearmR
	arm.set_kink(Vector3.ZERO, 0.9, 64)
	for i in 30:
		await get_tree().physics_frame
	get_tree().paused = true
	for st in styles:
		if st != Physique.forced:
			Physique.forced = st
			for f in men:
				Physique.dress(f)
		var tag := "_" + String(st)
		var quick := OS.get_environment("QUICK") == "1"
		# The three builds (the first three men), then each of the others close.
		var cx: float = men[1].torso.global_position.x
		await _snap(out, "builds_front%s.png" % tag, Vector3(cx, 1.0, 4.5), Vector3(cx, 0.92, 0), 30.0)
		if not quick:
			await _snap(out, "builds_three%s.png" % tag, Vector3(cx + 2.9, 1.35, 3.7), Vector3(cx, 0.92, 0), 30.0)
			await _snap(out, "builds_back%s.png" % tag, Vector3(cx - 0.4, 1.45, -4.5), Vector3(cx, 0.95, 0), 30.0)
		var ap: Vector3 = men[3].torso.global_position
		await _snap(out, "armour%s.png" % tag, ap + Vector3(1.3, -0.1, 2.9), Vector3(ap.x, 0.95, ap.z), 34.0)
		var hh: Vector3 = men[3].head.global_position
		await _snap(out, "helmet%s.png" % tag, hh + Vector3(0.55, 0.08, 1.1), hh + Vector3(0, -0.04, 0), 26.0)
		if not quick:
			var fh: Vector3 = men[0].head.global_position
			await _snap(out, "face%s.png" % tag, fh + Vector3(0.45, 0.06, 1.15), fh + Vector3(0, -0.03, 0), 26.0)
		var c: Vector3 = men[4].torso.global_position
		await _snap(out, "wound%s.png" % tag, c + Vector3(0.35, -0.05, 1.25), c + Vector3(-0.05, -0.25, 0), 32.0)
		var a: Vector3 = arm.global_position
		await _snap(out, "broken%s.png" % tag, a + Vector3(0.8, 0.2, 1.0), a + Vector3(0, -0.05, 0), 32.0)
		var vp: Vector3 = men[6].torso.global_position
		await _snap(out, "veteran%s.png" % tag, vp + Vector3(1.4, -0.1, 2.9), Vector3(vp.x, 0.9, vp.z), 34.0)
		var dp: Vector3 = men[7].torso.global_position
		await _snap(out, "designed%s.png" % tag, dp + Vector3(1.2, 0.0, 2.6), Vector3(dp.x, 1.0, dp.z), 34.0)
	get_tree().quit()
