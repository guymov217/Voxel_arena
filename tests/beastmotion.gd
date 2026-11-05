extends Node
## The beasts of the new look moving and attacking (`-- --probe beastmotion`, needs a display): each
## goes for a man standing still a few strides off and is drawn three times: in its stride, in the
## wind-up of its first attack (a head drawn back, a paw raised, the tusks lowered, an elephant
## rearing), and as the blow lands (the joints of the new look's skins bent, the jaws open). ONLY: a
## comma list; STYLE: the look (human). PNGs to SHOT_DIR as motion_<beast>_<n>.png.

var m
var cam: Camera3D
var _warmed := false

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 34.0) -> void:
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

## What it is winding up, or bringing down: a part in its wind-up, or an elephant's rearing.
func _winding(b: Beast) -> Variant:
	for p in b.wind:
		if is_instance_valid(p) and float(b.wind[p]) > 0.0:
			return p
	if float(b.ai.get("stomp", 0.0)) > Beast.STOMP_DOWN:
		return "stomp"
	return null

func _shoot(out: String, kind: String, n: int, b: Beast, man: Fighter) -> void:
	get_tree().paused = true
	var box := AABB(b.torso.global_position, Vector3.ZERO)
	for p in b.parts:
		if is_instance_valid(p) and not p.severed:
			box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
	box = box.merge(AABB(man.torso.global_position - Vector3(0.4, 1.0, 0.4), Vector3(0.8, 2.0, 0.8)))
	var r := box.size.length() * 0.5
	var at := box.get_center()
	# From the side, a little ahead: the legs, the neck, the head and the man clear.
	await _snap(out, "motion_%s_%d.png" % [kind, n], at + Vector3(r * 1.9, r * 0.45, -r * 0.35), at, 38.0)
	RenderingServer.render_loop_enabled = false
	get_tree().paused = false

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 5})
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
	var list := ["lion", "tiger", "wolf", "hyena", "bear", "boar", "bull", "goat", "rat", "rhino", "elephant", "mammoth"]
	if only != "":
		list = Array(only.split(","))
	for kind in list:
		var s := float(Data.beasts[kind].scale) * float(Data.beasts[kind].get("grow", 1.0))
		# The man, standing still, and the beast a few of its own lengths off, facing him.
		Physique.forced = style
		var me = m.spawn_fighter({"kind": "bot", "name": "Mark", "loadout": {"main": "", "off": "", "armor": []}, "team": 0, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		me.erase("bot")
		me.drive = func(_e): return {}
		var b = m.spawn_beast({"beast": kind, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0 + 2.2 * s), "yaw": PI})
		Physique.forced = ""
		var beast: Beast = b.f
		var man: Fighter = me.f
		var shots := 0
		var wound_up = null
		var blow_at := -1
		var t := 0
		while t < 120 * 12 and shots < 3:
			await get_tree().physics_frame
			t += 1
			beast.target = man
			if shots == 0 and t == 40:
				await _shoot(out, kind, 0, beast, man)   # its stride
				shots = 1
				continue
			if shots == 1:
				var w = _winding(beast)
				if w != null:
					wound_up = w
					await _shoot(out, kind, 1, beast, man)   # the wind-up
					shots = 2
				continue
			if shots == 2:
				# The blow: the wind-up over, a few steps into it (the stomp: coming down).
				var going: bool = (wound_up is String and float(beast.ai.get("stomp", 0.0)) <= Beast.STOMP_DOWN and float(beast.ai.get("stomp", 0.0)) > 0.0) or (wound_up is VoxelPart and is_instance_valid(wound_up) and not beast.wind.has(wound_up) and beast.strikes.has(wound_up))
				if going and blow_at < 0:
					blow_at = t
				if blow_at >= 0 and t >= blow_at + 9:
					await _shoot(out, kind, 2, beast, man)
					shots = 3
		print("MOTION %s %d shots" % [kind, shots])
		for e in [b, me]:
			m.entities.erase(e)
			if is_instance_valid(e.f):
				var ws = e.f.get("weapons")
				if ws is Dictionary:
					for k in ws:
						if ws[k] != null and is_instance_valid(ws[k]):
							ws[k].queue_free()
				e.f.queue_free()
		await get_tree().process_frame
	get_tree().quit()
