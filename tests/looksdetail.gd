extends Node
## The arena's materials and life, close, each set up the same way every time (`-- --probe
## looksdetail`, needs a display): the stone of the wall and the gatehouse, the frescoes on the
## podium, the props in the gate's tunnel (wood, iron, rust), a brazier, the crowd at the height of
## a fight, Rome beyond the arena, what the fights left on the sand, armour and the leather grip of
## a sword on the sand close, three bots' faces, a tired man's sweat and a fallen one's sand (the men
## turned to the sun, so their faces are seen), the beasts' coats (a lion's head, a
## wolf, a boar and a goat, a crocodile), and the sun's shafts through the velarium. LOOK_TAG goes
## after each name; LOOK_ONLY=a,b shoots only those. Then (not with LOOK_TAG=before) the same view
## under each time of day, and the brazier and the sun's shafts at dusk and late in the day.
## Where a look is not in the build (an older one), its shot is the plain scene.

var m: Match
var out := ""
var tag := ""
var only: PackedStringArray = []

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	tag = OS.get_environment("LOOK_TAG")
	if OS.get_environment("LOOK_ONLY") != "":
		only = OS.get_environment("LOOK_ONLY").split(",")
	seed(9)
	await _scene("noon")
	var cam: Camera3D = m.cam
	# (The sun stands to the south-east: yaw 0.3 to 0.6 turns a man's front to it.)
	var plate = _bot("Plate", {"main": "gladius", "off": "", "armor": ["helmet", "lorica", "manica"]}, Vector3(2.5, 0, 3), 0.6)
	plate.drive = func(_e): return {"main": {"x": 0.25, "y": 0.35}}
	_bot("Sword", {"main": "longsword", "off": ""}, Vector3(4.5, 0, 3.5), PI)
	var faces := []
	for k in 3:
		faces.append(_bot(["Brutus", "Cassius", "Decimus"][k], {"main": "", "off": ""}, Vector3(-5.5 + k * 1.1, 0, 3), 0.3))
	var tired = _bot("Tired", {"main": "", "off": ""}, Vector3(-1.2, 0, 5.5), 0.3)
	var fallen = _bot("Fallen", {"main": "", "off": ""}, Vector3(-0.2, 0, 5.5), 0.3)
	var beasts := {}
	var bx := {"lion": Vector3(6, 0.1, 9), "wolf": Vector3(-7, 0.1, 9), "boar": Vector3(-5, 0.1, 10.5), "goat": Vector3(-3, 0.1, 9.5), "crocodile": Vector3(1.5, 0.1, 10)}
	for sp in bx:
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": bx[sp], "yaw": PI * 0.9, "harmless": true})
		e.f.sp = e.f.sp.duplicate()
		e.f.sp.speed = 0.0
		e.f.sp.lunge = 0.0
		e.f.sp.ai = "statue"
		beasts[sp] = e.f
	# A longsword dropped on the sand, its leather grip to be seen whole.
	var loose: Weapon = m.spawn_loose_weapon(Data.preset("longsword"), Vector3(3.0, 0.35, 7.2))
	RenderingServer.render_loop_enabled = false
	for i in 150:
		await get_tree().physics_frame
	RenderingServer.render_loop_enabled = true
	m.set_process(false)
	cam.set_process(false)
	# The faces: a lived-in look for each (bots' own marks, where the build has them).
	var phy = load("res://scripts/fighter/physique.gd")
	var ids := [["bot_stubble", "bot_scar_cheek"], ["bot_brows_thick", "bot_scar_lip"], ["bot_unibrow", "bot_stubble"]]
	for k in 3:
		var f: Fighter = faces[k].f
		f.face_ids = ids[k]
		phy.call("_faces", f)
	# Sweat on the tired one (where the shader has it), the sand on the fallen one's front.
	var vb = load("res://shaders/voxel_body.gdshader")
	if vb and (vb as Shader).code.contains("instance uniform float sweat"):
		for p in tired.f.parts:
			if is_instance_valid(p) and p.mmi:
				p.mmi.set_instance_shader_parameter("sweat", 1.0)
	var vp = load("res://scripts/voxel/voxel_part.gd")
	if (vp as Script).get_script_constant_map().has("DUST"):
		var ff: Fighter = fallen.f
		for n in ["torso", "thighL", "thighR"]:
			var p: VoxelPart = ff.by_name.get(n)
			if p:
				var front := Vector3(sin(ff.yaw), 0, cos(ff.yaw))
				p.wound(p.to_local(p.global_position + front * 0.12 * ff.S + Vector3(0, -0.05, 0)), 0.2 * ff.S, "dust")
	# What the fights left on the sand: the hollow a body left, blood soaking in.
	var fxs := FileAccess.get_file_as_string("res://scripts/game/fx.gd")
	if fxs.contains("\"body\":"):
		m.fx.footprint("body", Vector3(-9.4, 0, -9.0), 0.6, 1.0)
	m.fx.pool(Vector3(-8.6, 0, -8.2), 0.9, 0.5)
	m.arena.set_excitement(0.95)
	# (A moment for the blood to soak, the embers to rise and the crowd to get up; drawn, since the
	# particles only move as they are drawn.)
	for i in 40:
		await get_tree().process_frame
	await _shot(cam, "stone", Vector3(9.4, 1.7, -6.8), Vector3(15.2, 3.2, -1.5), 55.0)
	await _shot(cam, "frescoes", Vector3(1.2, 1.25, -11.8), Vector3(1.2, 1.15, -15.5), 55.0)
	await _shot(cam, "props", Vector3(15.35, 1.55, -0.1), Vector3(17.6, 0.55, 0.05), 58.0)
	await _shot(cam, "brazier", Vector3(4.1, 1.95, 10.4), Vector3(5.5, 1.35, 13.3), 50.0)
	await _shot(cam, "crowd", Vector3(3.0, 1.8, 2.0), Vector3(-8.0, 5.0, 14.0), 52.0)
	await _shot(cam, "skyline", Vector3(8.0, 19.0, -31.0), Vector3(-25.0, 9.0, 120.0), 60.0)
	await _shot(cam, "sand", Vector3(-7.0, 1.8, -6.2), Vector3(-10.4, 0.0, -10.4), 55.0)
	var pf: Fighter = plate.f
	await _shot(cam, "armour", pf.head.global_position + Vector3(sin(pf.yaw), 0.0, cos(pf.yaw)).rotated(Vector3.UP, 0.5) * 1.0 + Vector3(0, 0.1, 0), pf.torso.global_position + Vector3(0, 0.25, 0), 40.0)
	if loose and is_instance_valid(loose):
		var grip: Vector3 = loose.global_transform * loose.grip_main
		await _shot(cam, "grip", grip + Vector3(0.22, 0.42, 0.3), grip, 36.0)
	for k in 3:
		var f: Fighter = faces[k].f
		var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
		await _shot(cam, "face%d" % (k + 1), f.head.global_position + fwd * 0.75 + Vector3(0, 0.04, 0), f.head.global_position, 32.0)
	var tf: Fighter = tired.f
	var mid: Vector3 = (tf.torso.global_position + fallen.f.torso.global_position) * 0.5
	await _shot(cam, "body", mid + Vector3(sin(tf.yaw), 0, cos(tf.yaw)) * 1.9 + Vector3(0.4, 0.35, 0), mid + Vector3(0, 0.05, 0), 45.0)
	var lion: Fighter = beasts.lion
	if lion and lion.head:
		var lf := Vector3(sin(lion.yaw), 0, cos(lion.yaw)).rotated(Vector3.UP, 0.6)
		await _shot(cam, "lion", lion.head.global_position + lf * 1.3 + Vector3(0, 0.25, 0), lion.head.global_position, 40.0)
	await _shot(cam, "beasts", Vector3(-4.6, 1.6, 5.6), Vector3(-5.0, 0.5, 10.0), 55.0)
	var croc: Fighter = beasts.crocodile
	if croc and croc.torso:
		await _shot(cam, "croc", croc.torso.global_position + Vector3(1.6, 1.1, -1.4), croc.torso.global_position, 45.0)
	await _shot(cam, "shafts", Vector3(-6.0, 1.7, -7.0), Vector3(8.0, 8.5, 9.0), 65.0)
	await _shot(cam, "tod_noon", Vector3(-9.0, 2.2, -9.0), Vector3(6.0, 5.0, 10.0), 65.0)
	if tag == "before":
		get_tree().quit()
		return
	# The other times of day: a new bout each, the same views.
	for sky in ["golden", "overcast", "evening"]:
		if not only.is_empty() and not (only.has("tod_" + sky) or only.has("brazier_" + sky) or only.has("shafts_" + sky)):
			continue
		m.queue_free()
		await get_tree().process_frame
		await _scene(sky)
		cam = m.cam
		RenderingServer.render_loop_enabled = false
		for i in 60:
			await get_tree().physics_frame
		RenderingServer.render_loop_enabled = true
		m.set_process(false)
		cam.set_process(false)
		for i in 20:
			await get_tree().process_frame
		await _shot(cam, "tod_" + sky, Vector3(-9.0, 2.2, -9.0), Vector3(6.0, 5.0, 10.0), 65.0)
		if sky == "evening":
			await _shot(cam, "brazier_evening", Vector3(4.1, 1.95, 10.4), Vector3(5.5, 1.35, 13.3), 50.0)
		if sky == "golden":
			await _shot(cam, "shafts_golden", Vector3(-6.0, 1.7, -7.0), Vector3(8.0, 8.5, 9.0), 65.0)
	get_tree().quit()

func _scene(sky: String) -> void:
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 9, "loadout": {"main": "gladius", "off": ""}, "sky": sky})
	m.me.f.teleport(Vector3(0, 0, -6))
	m.me.f.visible = false
	await get_tree().process_frame

func _bot(name_: String, lo: Dictionary, at: Vector3, yaw: float):
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": lo, "team": 1, "pos": at, "yaw": yaw})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e

func _shot(cam: Camera3D, name_: String, from: Vector3, to: Vector3, fov: float) -> void:
	if not only.is_empty() and not only.has(name_):
		return
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [name_, tag]))
	print("saved ", name_)
