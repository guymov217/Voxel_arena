extends Node
## Both hands on a haft, close (`-- --probe gripshots`, needs a display): a longsword, a zweihander
## and a war hammer held in both hands by men in a cuirass and arm guards, at a guard, out to the
## left and out to the right; each seen close from over his guard hand's shoulder (as the fight
## camera has him) and from in front; then the man with the war hammer down on the sand, sitting,
## as a fall leaves him. PNGs go to SHOT_DIR. With SIDES=RL the same again held from the left side
## (J: the left hand at the guard, the right below it), the marks the mirror of the right's; SIDES=LR
## comes back to the right for the fall. POSES picks the poses, SKIP=<side>:<pose>,... leaves some out.
## STYLE: the look (human, the new one, unless "strong" asks for the classic).
## (The hands on the grip, not one on the other arm; the arms clear of the armour; no arm folded
## back over the head.)

const POSES := [
	{"name": "guard", "x": 0.2, "y": 0.2},
	{"name": "left", "x": -2.0, "y": 0.3},
	{"name": "right", "x": 2.0, "y": 0.3},
	# (Partway to the left, high and low: both hands still on the haft across his front, the other
	# forearm close to his chest, user image 7. Only when POSES asks for them.)
	{"name": "leftmid", "x": -1.0, "y": 0.3, "extra": true},
	{"name": "leftlow", "x": -1.1, "y": -0.35, "extra": true},
]
var m
var cam: Camera3D
var men := []

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 38.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	# (Drawn again after the steps undrawn: the light, the shadows and the eye's exposure take a
	# while to come back as they were, and the first frames were dark.)
	var warm := 4 if RenderingServer.render_loop_enabled else 40
	RenderingServer.render_loop_enabled = true
	for i in warm:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var sides := OS.get_environment("SIDES") if OS.get_environment("SIDES") != "" else "R"
	# (SWIVEL=0: the arm drawn as the bodies hold it, without the drawn wrist: a before picture.
	# OLDFALL=1: knocked down, the other hand stays on the haft, as it did: a before picture.)
	Fighter.swivel_on = OS.get_environment("SWIVEL") != "0"
	Fighter.off_lets_go_down = OS.get_environment("OLDFALL") != "1"
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
	# (Nothing drawn but the pictures themselves: the steps between them cost nothing to draw.)
	RenderingServer.render_loop_enabled = false
	var pose := {"main": {"x": 0.2, "y": 0.2}, "power": true}
	var only := OS.get_environment("POSES").split(",", false)
	Physique.forced = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	for i in 3:
		var wk: String = ["longsword", "zweihander", "warhammer"][i]
		var e = m.spawn_fighter({"kind": "bot", "name": wk, "loadout": {"main": wk, "off": "", "armor": ["lorica", "manica"]}, "team": 1, "pos": Vector3((i - 1) * 3.0, 0.1, 0.0), "yaw": PI, "skin": [0xc68a5a, 0xa8714a, 0xd9a57a][i]})
		e.erase("bot")
		e.drive = func(_e): return pose
		# (Held as a player holds it: a bot's blade turns to lead its stroke, and after a stroke out
		# to one side the war hammer's head was still turned over at the next guard.)
		e.f.is_bot = false
		men.append(e.f)
	Physique.forced = ""
	for i in 120:
		await get_tree().physics_frame
	# (SKIP=R:guard,...: a side's pose left out; SIDES=LR comes back to the right after the left.)
	var skip := OS.get_environment("SKIP").split(",", false)
	var held := "R"
	for sd in sides:
		var mx := 1.0 if sd == "R" else -1.0
		if sd != held:
			# J: the hands change over, the marks across with them (as PlayerInput does).
			for f in men:
				if f.has_method("switch_two_side"):
					f.switch_two_side()
			held = sd
			for i in 60:
				await get_tree().physics_frame
		for ps in POSES:
			if not only.is_empty() and not only.has(ps.name):
				continue
			if only.is_empty() and ps.get("extra", false):
				continue
			if skip.has("%s:%s" % [sd, ps.name]):
				continue
			pose.main = {"x": ps.x * mx, "y": ps.y}
			for i in 110:
				await get_tree().physics_frame
			get_tree().paused = true
			for k in men.size():
				var f: Fighter = men[k]
				var c: Vector3 = f.torso.global_position
				# Over his guard hand's shoulder (he faces -z: his right is -x), and from in front.
				var tag := ("%s_%d" % [ps.name, k]) + ("" if sd == "R" else "_lefthold")
				await _snap(out, "grip_%s_back.png" % tag, c + Vector3(-0.9 * mx, 0.55, 2.0), c + Vector3(0.1 * mx, 0.0, -0.6))
				await _snap(out, "grip_%s_front.png" % tag, c + Vector3(0.6 * mx, 0.35, -2.3), c + Vector3(0, 0.05, 0))
			get_tree().paused = false
			RenderingServer.render_loop_enabled = false
	# Down on the sand, sitting up, the hammer still in both hands: seen as he lands, sits and
	# sits on (user: "sometimes" an arm folded back over his head).
	var hf: Fighter = men[2]
	hf.fall(3.0, true)
	var t := 0
	for n in [40, 70, 110, 160]:
		while t < n:
			await get_tree().physics_frame
			t += 1
		get_tree().paused = true
		var hc: Vector3 = hf.torso.global_position
		if n == 70:
			await _snap(out, "grip_down_back.png", hc + Vector3(-0.8, 0.9, 2.0), hc)
			await _snap(out, "grip_down_front.png", hc + Vector3(0.5, 0.6, -2.2), hc)
		else:
			await _snap(out, "grip_down_%d_front.png" % n, hc + Vector3(0.5, 0.6, -2.2), hc)
		get_tree().paused = false
		RenderingServer.render_loop_enabled = false
	get_tree().quit()
