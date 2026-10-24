extends Node
## One fighter's rise through the arena, filmed from just over his right shoulder, for the second
## trailer (`-- --probe shouldershots`, needs a display; run through tools/make_rise_trailer.py).
## SHOT picks the bout: who he faces and what he carries, from a slave with a stick to a champion
## in steel. He fights on autopilot and does not die (the foe does); the camera is strapped to
## the right side of his helmet like a GoPro: it moves and turns with his head, a wide lens, and
## jolts at every hard blow given or taken.
## Two passes as clipshots: CLIP_DRY=1 draws nothing and prints the frames of the blows and deaths
## ("DEATH <frame> <kind>", the foe's kind not "local"); CLIP_FROM=<frame> draws from there on.

const SHOTS := {
	"slave": {"enemy": "foe:drunk", "main": "stick", "off": "", "armor": [], "strength": 2.4},
	"recruit": {"enemy": "foe:recruit", "count": 2, "main": "gladius", "off": "roundShield", "armor": []},
	"lion": {"seed": 3, "enemy": "lion", "main": "gladius", "off": "scutum", "armor": ["manica"], "strength": 2.6},
	"cyclops": {"enemy": "foe:cyclops", "main": "spear", "off": "scutum", "armor": ["helmet", "manica"]},
	"minotaur": {"seed": 21, "enemy": "foe:minotaur", "main": "axe", "off": "roundShield", "armor": ["helmet", "manica", "greaves"], "strength": 2.8},
	"titan": {"enemy": "foe:titan", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0},
	"troll": {"enemy": "foe:troll", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0},
	"giant": {"enemy": "foe:giant", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0},
	"hydra": {"enemy": "hydra", "main": "zweihander", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 2.6},
}

var menu
var m
var seconds := 50.0
var started := false
var rec0 := 0
var from := 0
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_up := Vector3.UP
var trauma := 0.0      # the jolt of the last hard blow, dying away
var bob := 0.0         # the stride's phase
var t_cam := 0.0

func _ready() -> void:
	# After the match's own _process, which moves its camera every frame (cam.follow).
	process_priority = 1000
	var key := OS.get_environment("SHOT")
	if key == "" or not SHOTS.has(key):
		key = "recruit"
	var sh: Dictionary = SHOTS[key]
	seconds = float(OS.get_environment("CLIP_SECONDS")) if OS.get_environment("CLIP_SECONDS") != "" else seconds
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	var main = Data.shop.get("stick", {}).duplicate(true) if sh.main == "stick" else sh.main
	var o := {"mode": "training", "training": {"enemy": sh.enemy, "count": int(sh.get("count", 1)), "difficulty": 0.85, "immortal": true, "respawn": false},
		"loadout_override": {"main": main, "off": sh.off, "armor": sh.armor}}
	o["autopilot"] = true
	o["autopilot_diff"] = 1.0
	o["decrees"] = []
	o["hazards"] = []
	# The hero of the piece: hard to bring down and strong in the arm, so every bout is his.
	o["mods"] = {"toughness": 6.0, "strength": float(sh.get("strength", 1.8))}
	o["seed"] = int(OS.get_environment("CLIP_SEED")) if OS.get_environment("CLIP_SEED") != "" else int(sh.get("seed", 7))
	seed(int(o.seed))
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	# The game's own music off: the trailer lays its war drums over the fight's sounds (the
	# blows, the cries, the crowd), which are kept.
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	rec0 = Engine.get_frames_drawn()
	from = int(OS.get_environment("CLIP_FROM")) if OS.get_environment("CLIP_FROM") != "" else 0
	get_viewport().disable_3d = OS.get_environment("CLIP_DRY") == "1" or from > 0
	_tag("REC_START %d" % rec0)
	started = true
	# A war cry as he goes in.
	get_tree().create_timer(0.6).timeout.connect(func(): if m and m.me and is_instance_valid(m.me.f): m.say(m.me.f, "grunt", 1.0, "effort"))
	var dead := {}
	var t := 0.0
	var after := -1.0
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if from > 0 and _frame() >= from and get_viewport().disable_3d:
			get_viewport().disable_3d = false
		for e in m.entities:
			if is_instance_valid(e.f) and not e.f.alive and not dead.has(e.f):
				dead[e.f] = true
				_tag("DEATH %d %s %.1f" % [_frame(), str(e.kind), t])
				if after < 0.0 and e != m.me:
					after = t
		if after >= 0.0 and t - after > 3.0:
			break
	_tag("REC_END %d" % _frame())
	get_tree().quit()

func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

var cry_t := {}
func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if m and m.me and (h.get("attacker") == m.me.f or h.get("char") == m.me.f):
		trauma = minf(1.0, trauma + clampf(J / 60.0, 0.0, 0.8))
	if J >= 20.0:
		_tag("HIT %d %d" % [_frame(), int(J)])
	# The trailer is loud with the fight: the hero roars into his blows, and whoever is struck
	# cries out (men, giants and beasts in their own voices), more often and louder than in play.
	var now := Time.get_ticks_msec() / 1000.0
	var a = h.get("attacker")
	var c = h.get("char")
	if a == m.me.f and J > 12.0 and now - float(cry_t.get(a, -9.0)) > 1.1:
		cry_t[a] = now
		m.say(a, "grunt", 0.85, "effort")
	if c != null and is_instance_valid(c) and J > 8.0 and now - float(cry_t.get(c, -9.0)) > 0.8:
		cry_t[c] = now
		var grave: bool = bool(h.get("killed", false)) or not (h.get("res", {}) as Dictionary).get("severed", []).is_empty()
		m.say(c, Voices.hurt_call(c, J, grave), 0.9 if grave else 0.7, "grave" if grave else ("hurt" if J > 14.0 else "grunt"))

func _process(dt: float) -> void:
	if not started or m == null or m.me == null or not is_instance_valid(m.me.f):
		return
	t_cam += dt
	var a: Fighter = m.me.f
	var S: float = a.S
	var hp: VoxelPart = a.head if not a.head.severed else a.torso
	var head: Vector3 = hp.global_position
	# A camera strapped to the right side of his helmet, as a GoPro is (user): it sits on the
	# head and turns with it, looking where he looks, a wide lens that takes in the blade in
	# his fist and the man in front of him. (His right is the head's -x, his front +z.)
	var hb: Basis = hp.global_basis.orthonormalized()
	var hfwd: Vector3 = hb * Vector3(0, 0, 1)
	var body_fwd := Vector3(sin(a.yaw), 0, cos(a.yaw))
	if hfwd.dot(body_fwd) < 0.2:
		hfwd = body_fwd   # (the head knocked about or down: the body's line until it comes back)
	# A head thrown back by a blow had the lens on the sky: it keeps nearer his line and the
	# horizon than the head itself does.
	hfwd = (hfwd * 0.6 + body_fwd * 0.4).normalized()
	var ne = m.nearest_enemy(m.me)
	if ne and is_instance_valid(ne.f) and ne.f.alive:
		# His eyes are on the man: the lens leans a little his way.
		var to_f: Vector3 = (ne.f.torso.global_position - head).normalized()
		hfwd = hfwd.lerp(to_f, 0.2).normalized()
	var hup: Vector3 = hb * Vector3(0, 1, 0)
	# Out from the side of the helmet on its mount and a little forward, so the helmet's edge
	# is only the rim of the frame.
	var side: float = hp.half_ext.x + (0.14 if a.armor_kg > 0.0 else 0.11)
	var mount: Vector3 = hp.global_transform * Vector3(-side, hp.half_ext.y * 0.7, hp.half_ext.z * 0.4)
	# The jolt of a blow given or taken, dying away.
	trauma = maxf(0.0, trauma - dt * 1.6)
	var j := trauma * trauma
	var jolt := Vector3(sin(t_cam * 37.0), sin(t_cam * 43.0 + 1.0), sin(t_cam * 29.0 + 2.0)) * 0.05 * j
	if cam_pos == Vector3.ZERO:
		cam_pos = mount
		cam_look = hfwd
		cam_up = hup
	# Rigid on the head: the position follows at once, the turn a little smoothed (a head jitters
	# more than a camera on it shows).
	cam_pos = cam_pos.lerp(mount, minf(1.0, dt * 30.0))
	cam_look = cam_look.lerp(hfwd, minf(1.0, dt * 12.0)).normalized()
	cam_up = cam_up.lerp(hup.lerp(Vector3.UP, 0.6), minf(1.0, dt * 10.0)).normalized()
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 80.0
	cam.near = 0.03
	cam.global_position = cam_pos + jolt
	var look_at_p: Vector3 = cam_pos + cam_look * 4.0 + Vector3(sin(t_cam * 31.0), sin(t_cam * 41.0), 0) * 0.15 * j
	cam.look_at(look_at_p, cam_up if absf(cam_look.dot(cam_up)) < 0.95 else Vector3.UP)
	cam.reset_physics_interpolation()

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too (the window build of
## Godot on Windows prints nothing to a pipe).
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_tags) + "\n")
