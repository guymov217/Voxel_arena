extends Node
## One fighter's rise through the arena, for the rise trailer (`-- --probe shouldershots`, needs a
## display; run through tools/make_rise_trailer.py). SHOT picks the bout: who he faces and what he
## carries, from a slave with a stick to a champion in steel. He fights on autopilot and does not
## die (the foe does).
##
## Two cameras, cut between by the kill (CLIP_KILL, the frame the dry run saw the foe die on):
## - his helmet's: strapped to the right side of it like a GoPro (user), it moves and turns with
##   his head, a wide lens that takes in the blade in his fist and the man in front of him, and it
##   jolts at every hard blow given or taken;
## - for the kill of the big ones (the lion, the cyclops, the minotaur, the troll, the hydra), a
##   film camera: low on the sand off to one side, a long lens that stacks him and the beast
##   together, drifting slowly round them, the background melting away in its depth of field. The
##   editor plays this part in slow motion; after it the helmet again, looking down at what fell.
##
## Recorded at a frame for every physics step (--fixed-fps 120), so the editor has frames for
## motion blur and for a smooth slow motion. Drawn at the best the game can: MSAA, the voxels'
## corner shading, and supersampled (TRAILER_SSAA, the 3D drawn that much larger and scaled down).
##
## Two passes: CLIP_DRY=1 draws nothing and prints where the blows and deaths fall ("DEATH <frame>
## <kind> <s>", the foe's kind not "local"; "HIT <frame> <J>"); then CLIP_FROM=<frame> draws from
## there on, the frames before it black (cut afterwards).

const SHOTS := {
	"slave": {"enemy": "foe:drunk", "main": "stick", "off": "", "armor": [], "strength": 2.4},
	"recruit": {"enemy": "foe:recruit", "count": 2, "main": "gladius", "off": "roundShield", "armor": []},
	"lion": {"seed": 3, "enemy": "lion", "main": "gladius", "off": "scutum", "armor": ["manica"], "strength": 2.6, "cine": true},
	"cyclops": {"enemy": "foe:cyclops", "main": "spear", "off": "scutum", "armor": ["helmet", "manica"], "cine": true},
	"minotaur": {"seed": 21, "enemy": "foe:minotaur", "main": "axe", "off": "roundShield", "armor": ["helmet", "manica", "greaves"], "strength": 2.8, "cine": true},
	"titan": {"enemy": "foe:titan", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	"troll": {"enemy": "foe:troll", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	"giant": {"enemy": "foe:giant", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	"hydra": {"enemy": "hydra", "main": "zweihander", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 2.6, "cine": true},
}

## The film camera's part round the kill (seconds of the game's own time before and after it).
const CINE_BEFORE := 1.1
const CINE_AFTER := 1.3

var menu
var m
var seconds := 50.0
var started := false
var rec0 := 0
var from := 0
var kill := -1          # the frame of the kill (CLIP_KILL), or -1 in the dry run
var cine := false
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_up := Vector3.UP
var trauma := 0.0      # the jolt of the last hard blow, dying away
var t_cam := 0.0
var mode := "pov"
var foe = null          # the one the film camera frames
var cine_side := 1.0
var cine_t := 0.0
var cine_pos := Vector3.ZERO
var attrs: CameraAttributesPractical

func _ready() -> void:
	# After the match's own _process, which moves its camera every frame (cam.follow).
	process_priority = 1000
	var key := OS.get_environment("SHOT")
	if key == "" or not SHOTS.has(key):
		key = "recruit"
	var sh: Dictionary = SHOTS[key]
	seconds = float(OS.get_environment("CLIP_SECONDS")) if OS.get_environment("CLIP_SECONDS") != "" else seconds
	kill = int(OS.get_environment("CLIP_KILL")) if OS.get_environment("CLIP_KILL") != "" else -1
	cine = bool(sh.get("cine", false)) and OS.get_environment("CLIP_CINE") != "0"
	# The blows dealt in an order of their own, not the physics engine's: the undrawn pass and the
	# drawn one (its film camera's depth of field drawn too) then fight the same bout.
	Combat.canonical = true
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
	# The game's own music off: the trailer lays its score over the fight's sounds (the blows,
	# the cries, the crowd), which are kept.
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	_best_picture()
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

## The best the game draws: MSAA, the voxels' corner shading, the 3D supersampled.
func _best_picture() -> void:
	if OS.get_environment("CLIP_DRY") == "1":
		return
	menu.apply_picture({"aa": OS.get_environment("TRAILER_AA") if OS.get_environment("TRAILER_AA") != "" else "msaa4", "voxelAO": true})
	var vp := get_viewport()
	var ss := float(OS.get_environment("TRAILER_SSAA")) if OS.get_environment("TRAILER_SSAA") != "" else 1.5
	if ss > 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = ss
	attrs = CameraAttributesPractical.new()

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
	# (The game's own clock, not the wall's: the dry pass and the drawn one must cry out alike.)
	var now := float(Engine.get_physics_frames()) / 120.0
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
	var f := _frame()
	var want := "pov"
	if cine and kill > 0 and f >= kill - int(CINE_BEFORE * 120.0) and f < kill + int(CINE_AFTER * 120.0):
		want = "cine"
	if want != mode:
		mode = want
		if mode == "cine":
			_start_cine()
		else:
			cam_pos = Vector3.ZERO   # (the helmet's camera starts clean where it is)
			m.cam.attributes = null
	if mode == "cine":
		_cine(dt)
	else:
		_pov(dt)

## A camera strapped to the right side of his helmet, as a GoPro is (user): it sits on the head
## and turns with it, looking where he looks, a wide lens that takes in the blade in his fist and
## the man in front of him.
func _pov(dt: float) -> void:
	var a: Fighter = m.me.f
	var hp: VoxelPart = a.head if not a.head.severed else a.torso
	var head: Vector3 = hp.global_position
	# (His right is the head's -x, his front +z.)
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
	elif kill > 0 and _frame() >= kill and foe != null and is_instance_valid(foe):
		# The foe down: he looks down at what he felled.
		var to_d: Vector3 = (foe.torso.global_position - head).normalized()
		hfwd = hfwd.lerp(to_d, 0.45).normalized()
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

## The film camera comes in: on the side of the line between them that has the arena's middle
## behind it (the stands, not the wall, in the lens), low, as far off as a long lens wants.
func _start_cine() -> void:
	var ne = m.nearest_enemy(m.me)
	foe = ne.f if ne and is_instance_valid(ne.f) else foe
	cine_t = 0.0
	cine_pos = Vector3.ZERO
	var a: Fighter = m.me.f
	if foe == null:
		return
	var d: Vector3 = foe.torso.global_position - a.torso.global_position
	d.y = 0.0
	var s := Vector3.UP.cross(d.normalized())
	cine_side = 1.0 if s.dot(-a.torso.global_position) >= 0.0 else -1.0

func _cine(dt: float) -> void:
	var a: Fighter = m.me.f
	if foe == null or not is_instance_valid(foe):
		_pov(dt)
		return
	cine_t += dt
	var ha: Vector3 = a.torso.global_position
	var hf: Vector3 = foe.torso.global_position
	var fs: float = maxf(1.0, float(foe.S))
	var d := hf - ha
	d.y = 0.0
	var dist := maxf(0.6, d.length())
	d = d.normalized() if d.length_squared() > 1e-6 else Vector3(0, 0, 1)
	var s := Vector3.UP.cross(d) * cine_side
	# What it looks at: between them, nearer the foe, at the height of a man's chest (a giant's
	# belly); how far off it stands: far enough for both in a long lens.
	var mid: Vector3 = ha.lerp(hf, 0.58)
	mid.y = maxf(0.9, lerpf(ha.y, hf.y, 0.5) * 0.85)
	var span := dist + 1.2 * fs
	var fov := 34.0 + 6.0 * clampf(fs - 1.0, 0.0, 2.0)
	var back := span * 0.5 / tan(deg_to_rad(fov) * 0.5) * 1.15
	# Drifting round them, slowly, and in a little: a dolly on a curved track.
	var turn := -0.2 + cine_t * 0.12
	var off := (s * cos(turn) - d * sin(turn)).normalized() * back * (1.0 - 0.06 * minf(1.0, cine_t / 2.0))
	var want := mid + off + Vector3(0, -0.35 + 0.25 * fs, 0)
	want.y = maxf(0.35, want.y)
	# Inside the ring's wall.
	var flat := Vector2(want.x, want.z)
	if flat.length() > 13.5:
		flat = flat.normalized() * 13.5
		want = Vector3(flat.x, want.y, flat.y)
	if cine_pos == Vector3.ZERO:
		cine_pos = want
	cine_pos = cine_pos.lerp(want, minf(1.0, dt * 4.0))
	# A hand on the camera: a slow breath of drift.
	var breathe := Vector3(sin(cine_t * 1.3), sin(cine_t * 1.7 + 1.0) * 0.6, sin(cine_t * 1.1 + 2.0)) * 0.025
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = fov
	cam.near = 0.05
	cam.global_position = cine_pos + breathe
	cam.look_at(mid + Vector3(0, 0.1 * fs, 0), Vector3.UP)
	cam.reset_physics_interpolation()
	# The depth of a long lens: what is beyond them melts away.
	if attrs:
		var focus := cine_pos.distance_to(mid)
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus + 1.5 * fs
		attrs.dof_blur_far_transition = 4.0 * fs
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = maxf(0.3, focus - 2.5 * fs)
		attrs.dof_blur_near_transition = 1.0
		attrs.dof_blur_amount = 0.08
		cam.attributes = attrs

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too (the window build of
## Godot on Windows prints nothing to a pipe).
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var fl := FileAccess.open(path, FileAccess.WRITE)
	if fl:
		fl.store_string("\n".join(_tags) + "\n")
