extends Node
## The monsters' size against a man (`-- --probe sizeshots`, needs a display): each beast beside a
## gladiator standing still, as big as it was modelled and as big as it now stands (its "grow" in
## data/beasts.json), from the side, the same camera for both. ONLY: a comma list; STYLE: the look
## (human). PNGs to SHOT_DIR as size_<beast>_before.png and size_<beast>_after.png.

var m
var cam: Camera3D
var _warmed := false

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 50.0) -> void:
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

## The beast at `size` (its own scale times that), its head toward the man (it faces -x), its
## front a yard and a bit off him.
func _beast(kind: String, size: float, front: float) -> Dictionary:
	var base := float(Data.beasts[kind].scale)
	var grow := float(Data.beasts[kind].get("grow", 1.0))
	var e = m.spawn_beast({"beast": kind, "team": Match.ENEMY_TEAM, "pos": Vector3(1.3 + front * size, 0.1, 0.0), "yaw": -PI / 2.0, "harmless": true, "scale": base * size / grow})
	e.f.sp = e.f.sp.duplicate()
	e.f.sp.speed = 0.0
	e.f.sp.lunge = 0.0
	e.f.sp.ai = "statue"
	return e

func _clear(e: Dictionary) -> void:
	m.entities.erase(e)
	if is_instance_valid(e.f):
		e.f.queue_free()

## How far its front (its head, its jaws) reaches before its middle, at its own scale (metres).
func _front(kind: String) -> float:
	var best := 0.0
	for d in Data.beasts[kind].parts:
		var half: float = float(d.grid[2]) * 0.0275 * float(d.scale) * 0.5
		best = maxf(best, float(d.pos[2]) + half)
	return best

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 7})
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
	var list := []
	for k in Data.beasts:
		if float(Data.beasts[k].get("grow", 1.0)) != 1.0:
			list.append(k)
	if only != "":
		list = Array(only.split(","))
	Physique.forced = style
	var me = m.spawn_fighter({"kind": "bot", "name": "Mark", "loadout": {"main": "gladius", "off": "", "armor": ["helmet"]}, "team": 0, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
	Physique.forced = ""
	me.erase("bot")
	me.drive = func(_e): return {}
	for kind in list:
		var grow := float(Data.beasts[kind].get("grow", 1.0))
		var front := _front(kind)
		var frame := AABB()
		for pass_i in 2:
			var size := 1.0 / grow if pass_i == 0 else 1.0
			Physique.forced = style
			var b := _beast(kind, size * grow, front)
			Physique.forced = ""
			for i in 120:
				await get_tree().physics_frame
			get_tree().paused = true
			if pass_i == 0:
				# (One camera for both, framed for the bigger: the before as it stood against it.)
				var box := AABB(me.f.torso.global_position, Vector3.ZERO)
				for p in me.f.parts:
					box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
				var top := 0.0
				var far := 0.0
				for p in b.f.parts:
					if is_instance_valid(p):
						top = maxf(top, p.global_position.y + p.half_ext.length())
						far = maxf(far, p.global_position.x + p.half_ext.length())
				box = box.merge(AABB(Vector3(0, 0, 0), Vector3(1.3 + (far - 1.3) * grow, top * grow, 0.1)))
				frame = box
			var c := frame.get_center()
			var span := maxf(frame.size.x, frame.size.y * 1.6) * 1.08
			var dist := span * 0.5 / tan(deg_to_rad(25.0))
			await _snap(out, "size_%s_%s.png" % [kind, "before" if pass_i == 0 else "after"], Vector3(c.x, c.y * 0.8 + 0.6, minf(dist, 12.0)), Vector3(c.x, c.y * 0.8, 0.0), 50.0 if dist <= 12.0 else rad_to_deg(2.0 * atan(span * 0.5 / 12.0)))
			RenderingServer.render_loop_enabled = false
			get_tree().paused = false
			_clear(b)
			await get_tree().process_frame
		print("SIZE %s done" % kind)
	get_tree().quit()
