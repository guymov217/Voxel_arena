extends Node
## The giants and the beasts in both looks (`-- --probe creatureshots`, needs a display): each giant
## and each beast as the classic look draws it beside the new look's, in the sun, then the new
## one close (FACE=1: and a beast's head close, from in front). ONLY: a comma list (cyclops, giant, minotaur, troll, titan, lion, wolf...). PNGs to
## SHOT_DIR.

var m
var cam: Camera3D
var _warmed := false

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 30.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	# (The first picture waits for the shaders; after it a few frames bring the scene up to date.)
	var warm := 4 if RenderingServer.render_loop_enabled else (5 if _warmed else 40)
	RenderingServer.render_loop_enabled = true
	for i in warm:
		await get_tree().process_frame
	_warmed = true
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _beast(sp: String, pos: Vector3, style: String) -> Dictionary:
	Physique.forced = style
	var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": pos, "yaw": 0.35, "harmless": true})
	Physique.forced = ""
	e.f.sp = e.f.sp.duplicate()
	e.f.sp.speed = 0.0
	e.f.sp.lunge = 0.0
	e.f.sp.ai = "statue"
	return e

func _giant(type: String, pos: Vector3, style: String) -> Dictionary:
	var spec: Dictionary = m.enemy_spec({"e": type}, 0, 1)
	spec["pos"] = pos
	spec["yaw"] = 0.0
	Physique.forced = style
	var e = m.spawn_fighter(spec)
	Physique.forced = ""
	e.erase("bot")
	e.drive = func(_e): return {"main": {"x": 0.3, "y": -0.6}, "off": {"x": -0.3, "y": -0.6}}
	return e

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -30))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	RenderingServer.render_loop_enabled = false
	var list := ["cyclops", "giant", "minotaur", "troll", "titan", "lion", "wolf", "tiger", "bear", "boar", "elephant", "dragon"]
	if only == "beasts":
		list = Data.beasts.keys()
		only = ""
	elif only != "":
		# (In the order asked: a beast left out of the list above was never drawn.)
		list = Array(only.split(","))
		only = ""
	for kind in list:
		if only != "" and not only.split(",").has(kind):
			continue
		var giant: bool = ["cyclops", "giant", "minotaur", "troll", "titan"].has(kind)
		var s := 1.0
		var a
		var b
		if giant:
			s = float(Data.enemy_type(kind).get("mods", {}).get("bodyScale", 2.5))
			a = _giant(kind, Vector3(-1.2 * s, 0.1, 0.0), "strong")
			b = _giant(kind, Vector3(1.2 * s, 0.1, 0.0), "human")
		else:
			# (As big as it stands: a monster grown past its model stood into the one beside it.)
			s = float(Data.beasts[kind].scale) * float(Data.beasts[kind].get("grow", 1.0)) * 0.8
			a = _beast(kind, Vector3(-1.3 * s, 0.1, 0.0), "strong")
			b = _beast(kind, Vector3(1.3 * s, 0.1, 0.0), "human")
		RenderingServer.render_loop_enabled = false
		for i in 150:
			await get_tree().physics_frame
		get_tree().paused = true
		var h := 1.9 * s if giant else 1.2 * s
		var nm: String = "polyphemus" if kind == "giant" else String(kind)
		if not giant:
			# A beast framed by its real size: the box round both of them (wings, necks, tails).
			var box := AABB(a.f.torso.global_position, Vector3.ZERO)
			for e in [a, b]:
				for p in e.f.parts:
					if is_instance_valid(p) and not p.severed:
						box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
			var c := box.get_center()
			var r := box.size.length() * 0.5
			# (Inside the arena's wall however big they are: the camera no further than 12.5 m from
			# them, the view widened to take them in; farther, the grown dragon was seen from the
			# stands, over the wall.)
			var dist := minf(r * 1.9, 12.5)
			var fov := clampf(rad_to_deg(2.0 * atan(r * 0.69 / dist)), 40.0, 75.0)
			await _snap(out, "%s_pair.png" % nm, c + Vector3(0.0, dist * 0.35 / 1.9, dist), c, fov)
			if OS.get_environment("FACE") == "1" and b.f.get("head") != null:
				# (FACE: the new look's head close, from in front of it)
				var hp: Vector3 = (b.f.head as Node3D).global_position
				var fw: Vector3 = (b.f.head as Node3D).global_transform.basis.z.normalized()
				var hr: float = (b.f.head as VoxelPart).half_ext.length()
				await _snap(out, "%s_face.png" % nm, hp + fw * hr * 3.2 + Vector3(0.0, hr * 0.5, 0.0), hp, 34.0)
			if OS.get_environment("PAIRONLY") != "1":
				var bb := AABB(b.f.torso.global_position, Vector3.ZERO)
				for p in b.f.parts:
					if is_instance_valid(p) and not p.severed:
						bb = bb.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
				var cb := bb.get_center()
				var rb := bb.size.length() * 0.5
				await _snap(out, "%s_new.png" % nm, cb + Vector3(rb * 1.2, rb * 0.45, rb * 1.6), cb, 40.0)
			get_tree().paused = false
			for e in [a, b]:
				_clear(e)
			await get_tree().process_frame
			continue
		# (Inside the arena's wall however big he is: farther off, the camera stood in the stands.)
		var dist := minf(h * 2.4, 12.0)
		var fov := clampf(rad_to_deg(2.0 * atan(h * 0.62 / dist)), 30.0, 70.0)
		await _snap(out, "%s_pair.png" % nm, Vector3(0, h * 0.55 * dist / (h * 2.4), dist), Vector3(0, h * 0.45, 0), fov)
		var fb: Vector3 = b.f.torso.global_position
		var hd: Vector3 = b.f.head.global_position if b.f.head else fb
		if OS.get_environment("PAIRONLY") == "1":
			pass
		elif giant:
			await _snap(out, "%s_head.png" % nm, hd + Vector3(h * 0.12, h * 0.03, h * 0.42), hd, 30.0)
		else:
			await _snap(out, "%s_new.png" % nm, fb + Vector3(h * 0.9, h * 0.35, h * 1.3), fb, 32.0)
		get_tree().paused = false
		for e in [a, b]:
			_clear(e)
		await get_tree().process_frame
	get_tree().quit()

## Gone, and what it held with it (a giant's hammer and shield lay on in the sand, in front of the
## beasts drawn after him).
func _clear(e: Dictionary) -> void:
	m.entities.erase(e)
	if not is_instance_valid(e.f):
		return
	var ws = e.f.get("weapons")
	if ws is Dictionary:
		for k in ws:
			var w = ws[k]
			if w != null and is_instance_valid(w):
				w.queue_free()
	e.f.queue_free()
