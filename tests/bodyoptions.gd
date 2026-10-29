extends Node
## One man, bare, in a given look (LOOK) and body drawing (BODIES: blocky|smooth), arms a little
## out so the limbs show: front, three-quarter and a close-up of the arm and leg (`-- --probe
## bodyoptions`, needs a display). PNGs go to SHOT_DIR/<NAME>_<view>.png.
var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	RenderingServer.render_loop_enabled = true
	for i in 6:
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = false
	get_viewport().get_texture().get_image().save_png(out.path_join(name))

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	RenderingServer.render_loop_enabled = false   # (the software renderer: draw only the shots)
	var nm := OS.get_environment("NAME")
	OS.set_environment("VA_BODIES", OS.get_environment("BODIES") if OS.get_environment("BODIES") != "" else "blocky")
	Physique.forced = OS.get_environment("LOOK") if OS.get_environment("LOOK") != "" else "strong"
	# TUNE: a trial of the limbs' drawing (Physique.tune), as JSON.
	if OS.get_environment("TUNE") != "":
		Physique.tune = JSON.parse_string(OS.get_environment("TUNE"))
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3, "loadout": {"main": "", "off": ""}})
	m.me.f.teleport(Vector3(0, 0, 30))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	var e = m.spawn_fighter({"kind": "bot", "name": "Man", "loadout": {"main": "", "off": "", "armor": Array(OS.get_environment("ARMOR").split(",", false))}, "team": 1, "pos": Vector3(0, 0.1, 0.0), "yaw": PI, "skin": 0xc68a5a})
	e.erase("bot")
	var d := {"main": {"x": 0.9, "y": 0.0}, "off": {"x": -0.9, "y": 0.0}}
	e.drive = func(_e): return d
	for i in 120:
		await get_tree().physics_frame
		# BURN: his right thigh set alight a second before the shots.
		if i == 60 and OS.get_environment("BURN") != "":
			for p in e.f.parts:
				if p.part_name == "thighR":
					Fire.add_spot(p, "fire", 10.0)
	get_tree().paused = true
	# Drawn once, then every part drawn again from its voxels (what the game's resync_later does a
	# frame after spawn; with drawing off until now the shapes were lost with the first frame).
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await get_tree().process_frame
	for p in e.f.parts:
		p.resync()
		if p.skin:
			p.rebuild_skin()
	RenderingServer.render_loop_enabled = false
	var views := OS.get_environment("VIEWS").split(",") if OS.get_environment("VIEWS") != "" else PackedStringArray(["front", "three", "arm", "leg"])
	if views.has("front"):
		await _snap(out, nm + "_front.png", Vector3(0, 1.3, -4.4), Vector3(0, 1.0, 0), 40.0)
	if views.has("three"):
		await _snap(out, nm + "_three.png", Vector3(3.0, 1.5, -3.2), Vector3(0, 1.0, 0), 40.0)
	if views.has("arm"):
		await _snap(out, nm + "_arm.png", Vector3(-1.1, 1.5, -1.8), Vector3(-0.35, 1.3, 0), 34.0)
	if views.has("leg"):
		await _snap(out, nm + "_leg.png", Vector3(1.0, 0.8, -1.9), Vector3(0, 0.5, 0), 36.0)
	get_tree().quit()
