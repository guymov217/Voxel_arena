extends Node
## The key art (`-- --probe keyart`, needs a display): the frame the poster and the logo
## capsules are made from (tools/make_keyart.py). A champion in gilded armour in the middle of the
## sand with a ruby-set axe raised; behind him a dragon pours fire across the arena at a second
## man, the stands full and roaring. KEYART_VIEW "poster" (run the window 1200x1800) or "wide"
## (2560x1080) frames it upright or wide; the PNG goes to SHOT_DIR/keyart_<view>.png.

const AXE := {"name": "Wrecker", "kind": "weapon", "twoHanded": false, "sharpness": 0.9, "voxels": [
	[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "grip"], [0, 2, 0, "wood", "grip"], [0, 3, 0, "wood", "grip"],
	[0, 4, 0, "wood", "blunt"], [0, 5, 0, "wood", "blunt"], [0, 6, 0, "wood", "blunt"], [0, 7, 0, "wood", "blunt"],
	[0, 8, 0, "wood", "blunt"], [0, 9, 0, "gold", "blunt"], [0, 10, 0, "gold", "blunt"], [0, 11, 0, "gold", "blunt"],
	[1, 9, 0, "steel", "blunt"], [1, 10, 0, "ruby", "blunt"], [1, 11, 0, "steel", "blunt"],
	[2, 8, 0, "steel", "blunt"], [2, 9, 0, "steel", "blunt"], [2, 10, 0, "steel", "blunt"], [2, 11, 0, "steel", "blunt"], [2, 12, 0, "steel", "blunt"],
	[3, 7, 0, "steel", "edge"], [3, 8, 0, "steel", "blunt"], [3, 9, 0, "steel", "blunt"], [3, 10, 0, "steel", "blunt"], [3, 11, 0, "steel", "blunt"], [3, 12, 0, "steel", "blunt"], [3, 13, 0, "steel", "edge"],
	[4, 6, 0, "steel", "edge"], [4, 7, 0, "steel", "edge"], [4, 8, 0, "steel", "edge"], [4, 9, 0, "steel", "edge"], [4, 10, 0, "steel", "edge"], [4, 11, 0, "steel", "edge"], [4, 12, 0, "steel", "edge"], [4, 13, 0, "steel", "edge"], [4, 14, 0, "steel", "edge"],
	[-1, 10, 0, "steel", "point"], [-2, 10, 0, "steel", "point"], [0, 12, 0, "steel", "point"], [0, 13, 0, "steel", "point"]]}

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var view := OS.get_environment("KEYART_VIEW")
	if view == "":
		view = "poster"
	seed(7)
	# The fight plays out unseen (each frame of the ultra picture is slow to draw on a machine
	# without a GPU); only the last frames are drawn.
	RenderingServer.render_loop_enabled = false
	Engine.max_physics_steps_per_frame = 64
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "seed": 11,
		"loadout": {"main": AXE, "off": "", "armor": ["goldHelmet", "goldLorica", "manica", "greaves", "cape"]}})
	if m.killcam:
		m.killcam.queue_free()
		m.killcam = null
	if m.arena and m.arena.env:
		Arena.apply_quality(m.arena.env, m.arena.sun, "ultra")
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0, 0, 1.0))
	hero.yaw = PI
	# The axe up over his head, the other arm out: facing the camera, his back to the dragon.
	var pose := {"look": {"yaw": 0.0, "pitch": 0.35}, "main": {"x": 0.15, "y": 1.6}, "off": {"x": -0.9, "y": 0.6}, "twist": 1.3}
	m.me.drive = func(_e): return pose
	hero.yaw = 0.0
	# The dragon behind him, its fire poured across the sand at a man running from it.
	var dragon = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(1.2, 0.1, -6.5), "yaw": -0.5, "harmless": true})
	dragon.f.sp = dragon.f.sp.duplicate()
	dragon.f.sp.speed = 0.0
	dragon.f.sp.lunge = 0.0
	dragon.f.sp.ai = "statue"
	var runner = m.spawn_fighter({"kind": "bot", "name": "Runner", "loadout": {"main": "spear", "off": "roundShield"}, "team": 2, "pos": Vector3(-1.5, 0, -3.5), "yaw": -PI * 0.5})
	runner.erase("bot")
	runner.drive = func(_e): return {"mz": 1.0, "sprint": false, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": -0.3, "y": 1.2}}
	if m.arena:
		m.arena.set_excitement(1.0)
	for i in 120 * 2:
		await get_tree().physics_frame
		if m.arena:
			m.arena.set_excitement(1.0)
	dragon.f.target = runner.f
	m._breath(dragon.f, "fire", float(dragon.f.sp.get("breathRange", 6.0)))
	for i in int(120 * 0.75):
		await get_tree().physics_frame
	var cam: Camera3D = m.cam
	cam.set_process(false)
	m.set_process(false)
	var c: Vector3 = hero.torso.global_position
	if view == "poster":
		cam.fov = 52.0
		cam.global_position = c + Vector3(1.0, -0.45, 4.9)
		cam.look_at(c + Vector3(0.3, 1.45, -2.0), Vector3.UP)
	else:
		cam.fov = 46.0
		cam.global_position = c + Vector3(1.6, -0.3, 4.0)
		cam.look_at(c + Vector3(-0.3, 0.8, -2.5), Vector3.UP)
	RenderingServer.render_loop_enabled = true
	for k in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("keyart_%s.png" % view))
	print("saved keyart_", view)
	get_tree().quit()
