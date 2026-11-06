extends Node
## A man in armour in the new look, all round (`-- --probe armourshots`, needs a display): a galea,
## a lorica, a manica and greaves on a man standing at ease, from in front, from behind, from either
## side and from three-quarters, close: to see the pieces lie straight and alike on both sides of
## him (user: the lorica did not look symmetrical, nor as one was made). STYLE: the look (human).
## PNGs to SHOT_DIR as armour_<view>.png. SETS: other sets to wear, `;` between sets and `,`
## between pieces (every piece the smith sells, on the new men: user), as armour_<n>_<view>.png;
## VIEWS: which views (front,back,left,right,three).

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 30.0) -> void:
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
	Physique.forced = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
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
	var sets: Array = [["helmet", "lorica", "manica", "greaves"]]
	if OS.get_environment("SETS") != "":
		sets = Array(OS.get_environment("SETS").split(";", false)).map(func(t): return Array(String(t).split(",", false)))
	var views: Array = Array(OS.get_environment("VIEWS").split(",", false)) if OS.get_environment("VIEWS") != "" else ["front", "back", "left", "right", "three"]
	for si in sets.size():
		var e = m.spawn_fighter({"kind": "bot", "name": "Quintus Rufus", "loadout": {"main": "", "off": "", "armor": sets[si]}, "team": 1, "pos": Vector3(0.0, 0.1, 0.0), "yaw": 0.0, "skin": 0xd9a57a})
		e.erase("bot")
		# At ease: both hands low at his sides, alike.
		e.drive = func(_e): return {"main": {"x": 0.35, "y": -0.9}, "off": {"x": -0.35, "y": -0.9}}
		var f: Fighter = e.f
		f.build_pref = "hero"
		Physique.dress(f)
		get_tree().paused = false
		for i in 150:
			await get_tree().physics_frame
		get_tree().paused = true
		var c: Vector3 = f.torso.global_position
		var at := Vector3(c.x, c.y + 0.05, c.z)
		var tag := "" if OS.get_environment("SETS") == "" else "%d_" % si
		# (He faces +z.)
		var where := {"front": Vector3(0.0, 0.25, 2.6), "back": Vector3(0.0, 0.3, -2.6), "left": Vector3(2.6, 0.25, 0.0), "right": Vector3(-2.6, 0.25, 0.0), "three": Vector3(1.6, 0.6, 2.0)}
		for v in views:
			await _snap(out, "armour_%s%s.png" % [tag, v], at + where[v], at)
		print("set %d: %s" % [si, ", ".join(sets[si])])
		get_tree().paused = false
		f.teleport(Vector3(0.0, 0.0, -40.0 - 6.0 * si))   # (out of the next one's pictures)
	get_tree().quit()
