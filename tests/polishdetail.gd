extends Node
## The arena's finer looks, each set up the same way every time (`-- --probe polishdetail`, needs
## a display): a gladiator in helmet and plate holding a gladius, close (the metal and what it
## shows); his blade bloodied; a bare-headed one's face at rest, blinking and hurt; prints in the
## sand (both feet, a peg, a body dragged); the whole arena from above (the clouds' shadows) and
## the stands from the sand (the cloth over them); a sword swung fast. POLISH_TAG goes after each
## name. Where a look is not in the game (an older build), its shot is the plain scene.

var m: Match
var out := ""
var tag := ""
var only: PackedStringArray = []   # POLISH_ONLY=blade,swing: just those shots

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	tag = OS.get_environment("POLISH_TAG")
	if OS.get_environment("POLISH_ONLY") != "":
		only = OS.get_environment("POLISH_ONLY").split(",")
	seed(9)
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 9, "loadout": {"main": "gladius", "off": ""}})
	m.me.f.teleport(Vector3(0, 0, -11))
	var cam: Camera3D = m.cam
	var a = m.spawn_fighter({"kind": "bot", "name": "Plate", "loadout": {"main": "gladius", "off": "", "armor": ["helmet", "lorica", "manica"]}, "team": 1, "pos": Vector3(2.5, 0, 3), "yaw": PI * 0.85})
	a.erase("bot")
	a.drive = func(_e): return {"main": {"x": 0.25, "y": 0.35}}
	var b = m.spawn_fighter({"kind": "bot", "name": "Bare", "loadout": {"main": "", "off": ""}, "team": 1, "pos": Vector3(-2.5, 0, 3), "yaw": PI})
	b.erase("bot")
	b.drive = func(_e): return {}
	var wk = m.spawn_fighter({"kind": "bot", "name": "Walker", "loadout": {"main": "", "off": ""}, "team": 1, "pos": Vector3(-6, 0, -8), "yaw": 0.0})
	wk.erase("bot")
	wk.drive = func(_e): return {"mz": 1.0}
	var sw = m.spawn_fighter({"kind": "bot", "name": "Swing", "loadout": {"main": "longsword", "off": ""}, "team": 1, "pos": Vector3(6, 0, -3), "yaw": -PI * 0.5})
	sw.erase("bot")
	var flip := {"t": 0}
	sw.drive = func(_e):
		flip.t += 1
		return {"main": {"x": 1.3 if (flip.t / 24) % 2 == 0 else -1.3, "y": 0.2}, "power": true}
	RenderingServer.render_loop_enabled = false
	for i in 150:
		await get_tree().physics_frame
	RenderingServer.render_loop_enabled = true
	m.set_process(false)
	cam.set_process(false)
	wk.drive = func(_e): return {}
	var fa: Fighter = a.f
	var fb: Fighter = b.f
	# Prints in the sand, as feet and a peg and a dragged body would leave them.
	if m.fx and m.fx.has_method("footprint"):
		for k in 6:
			var z := -3.0 + k * 0.42
			m.fx.footprint("footL" if k % 2 == 0 else "footR", Vector3(-4.0 + (-0.12 if k % 2 == 0 else 0.12), 0, z), 0.0, 1.0)
		for k in 4:
			m.fx.footprint("peg", Vector3(-3.0, 0, -3.0 + k * 0.5), 0.0, 1.0)
			m.fx.footprint("footR", Vector3(-2.75, 0, -2.75 + k * 0.5), 0.0, 1.0)
		for k in 5:
			m.fx.footprint("drag", Vector3(-1.6 + k * 0.05, 0, -3.0 + k * 0.3), 0.15, 1.0, 0.45)
	await _shot(cam, "prints", Vector3(-2.6, 2.6, 0.2), Vector3(-3.1, 0, -2.0), 50.0)
	var wp0: Vector3 = wk.f.torso.global_position
	await _shot(cam, "walked", Vector3(wp0.x + 1.6, 2.2, wp0.z - 0.4), Vector3(wp0.x, 0, wp0.z - 2.0), 55.0)
	# The blade bloodied where it struck (near its point and along the edge).
	var w = fa.weapons.R
	if w and is_instance_valid(w) and w.has_method("bloody"):
		var tip := Vector3.ZERO
		for v in w.vox:
			var p := Vector3(float(v[0]), float(v[1]), float(v[2])) * float(w.vs)
			if p.length() > tip.length():
				tip = p
		w.bloody(w.to_global(tip * 0.9), 0.85)
		w.bloody(w.to_global(tip * 0.7), 0.7)
	for i in 4:
		await get_tree().process_frame
	await _shot(cam, "metal", fa.head.global_position + Vector3(sin(fa.yaw), 0.15, cos(fa.yaw)) * 1.1 + Vector3(0.35, 0.1, 0), fa.torso.global_position + Vector3(0, 0.3, 0), 42.0)
	await _shot(cam, "helmet", fa.head.global_position + Vector3(sin(fa.yaw), 0.0, cos(fa.yaw)).rotated(Vector3.UP, 0.7) * 0.7 + Vector3(0, 0.35, 0), fa.head.global_position + Vector3(0, 0.1, 0), 40.0)
	if w and is_instance_valid(w):
		var tipw: Vector3 = w.to_global(Vector3(0, 0.6, 0))
		var gripw: Vector3 = w.global_position
		var mid := (tipw + gripw) * 0.5
		var along := (tipw - gripw).normalized()
		var side := along.cross(Vector3.UP).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		await _shot(cam, "blade", mid + side * 0.75 + Vector3(0, 0.25, 0), mid, 40.0)
	# A face at rest, blinking, hurt.
	var face_at: Vector3 = fb.head.global_position
	var fwd := Vector3(sin(fb.yaw), 0, cos(fb.yaw))
	var eye := face_at + fwd * 0.75 + Vector3(0, 0.04, 0)
	await _shot(cam, "face_rest", eye, face_at, 32.0)
	var phy = load("res://scripts/fighter/physique.gd")
	var can_face: bool = phy.get_script_method_list().any(func(d): return d.name == "express")
	if can_face:
		phy.call("express", fb, true, false)
	await _shot(cam, "face_blink", eye, face_at, 32.0)
	if can_face:
		phy.call("express", fb, false, true)
	await _shot(cam, "face_hurt", eye, face_at, 32.0)
	# The arena from above and the stands from the sand.
	await _shot(cam, "above", Vector3(10, 16, -14), Vector3(0, 0, 2), 60.0)
	await _shot(cam, "stands", Vector3(-4, 1.7, -6), Vector3(6, 9.0, 13), 60.0)
	# A sword swung fast: three moments, each the same number of ticks into a sweep (the same
	# moments with or without the trail, so the shots can be set side by side).
	var sf: Fighter = sw.f
	var sfw := Vector3(sin(sf.yaw), 0, cos(sf.yaw))
	var sside := sfw.cross(Vector3.UP)
	cam.fov = 55.0
	cam.global_position = sf.torso.global_position + sfw * 3.0 + sside * 1.2 + Vector3(0, 0.5, 0)
	cam.look_at(sf.torso.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	var base: int = int(flip.t) - int(flip.t) % 48 + 48
	var at := [8, 14, 32, 38]
	var k := 0 if only.is_empty() or only.has("swing") else at.size()
	var guard := 0
	# (Drawn only for the frames kept: the sweep is gathered every frame all the same.)
	RenderingServer.render_loop_enabled = false
	while k < at.size() and guard < 600:
		guard += 1
		var due := int(flip.t) >= base + int(at[k]) - 2
		RenderingServer.render_loop_enabled = due
		if due:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
		if due and int(flip.t) >= base + int(at[k]):
			get_viewport().get_texture().get_image().save_png(out.path_join("swing%d_%s.png" % [k, tag]))
			print("saved swing%d at %d" % [k, int(flip.t) - base])
			k += 1
	RenderingServer.render_loop_enabled = true
	get_tree().quit()

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
