extends Node
## The staged shots of the crowd trailer (`-- --probe stageshots`, needs a display; run through
## tools/make_blood_trailer.py, which records them with the movie maker at 120 frames a second).
## STAGE picks the shot:
## - reveal: the arena from the sky, a crane coming down over the full stands and the awnings to
##   the sand, where the champion walks in from the gate (ENTER THE ARENA);
## - crowd: low on the sand under the Emperor's box, the stands on their feet, a slow dolly;
## - dragon: the dragon pours its fire across the sand at a man running from it, the champion
##   in front with his axe up;
## - cheese: a wheel of cheese bowled along the sand takes a charging man off his feet;
## - chaos: a free-for-all seen from above the thick of it, the camera going round;
## - squad: friends, their names over their heads, against the minotaur and his wolves;
## - finale: the champion alone in the middle, his back to us, his axe raised to the crowd.
##
## Tags (stdout, and TAG_LOG when set): REC_START <frame> when the shot begins, KEY <frame> at its
## moment (the fire, the wheel's strike, the hardest blow), HIT <frame> <J>, REC_END <frame>.
## Until REC_START nothing 3D is drawn (the frames before it are black and cut away), so a fight
## that has to get going first costs next to nothing to record.

const CapsArt := preload("res://tests/capsuleart.gd")
const NAMES := ["IronWolf", "Ravenblade", "Kestrel"]

var menu
var m
var rec0 := 0
var rolling := false
var t := 0.0              # seconds since REC_START
var dur := 6.0
var cam_fn: Callable      # t -> [eye, at, fov, focus (0: no depth of field)]
var tick_fn: Callable     # t -> void, every physics step while rolling
var attrs: CameraAttributesPractical
var keyed := false
var best_j := 0.0

func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shot := OS.get_environment("STAGE")
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	seed(int(OS.get_environment("STAGE_SEED")) if OS.get_environment("STAGE_SEED") != "" else 5)
	match shot:
		"reveal":
			await _reveal()
		"crowd":
			await _crowd()
		"dragon":
			await _dragon()
		"cheese":
			await _cheese()
		"chaos":
			await _chaos()
		"squad":
			await _squad()
		"finale":
			await _finale()
		_:
			print("STAGE: reveal, crowd, dragon, cheese, chaos, squad, finale")
			get_tree().quit(1)
			return
	if OS.get_environment("STAGE_SECONDS") != "":
		dur = float(OS.get_environment("STAGE_SECONDS"))
	# Rolling: drawn from here on. (STAGE_PEEK=n: a check of the framing without the movie maker:
	# only n frames drawn, evenly through the shot, saved to SHOT_DIR as peek_<shot>_<k>.png.)
	var peek := int(OS.get_environment("STAGE_PEEK")) if OS.get_environment("STAGE_PEEK") != "" else 0
	get_viewport().disable_3d = peek > 0
	rec0 = Engine.get_frames_drawn()
	_tag("REC_START %d" % rec0)
	rolling = true
	var peeked := 0
	while t < dur:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if m.arena:
			m.arena.set_excitement(1.0)
		if tick_fn.is_valid():
			tick_fn.call(t)
		if peek > 0 and peeked < peek and t >= dur * float(peeked) / float(peek):
			get_viewport().disable_3d = false
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("peek_%s_%d.png" % [shot, peeked]))
			peeked += 1
			get_viewport().disable_3d = true
	_tag("REC_END %d" % _frame())
	get_tree().quit()

## The match the shot is staged in: the game's own picture at its best, its music off (the
## trailer lays its score over the fight's own sound), no HUD, the camera ours.
func _start(o: Dictionary) -> void:
	o.merge({"decrees": [], "hazards": [], "seed": 5}, false)
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	if m.killcam:
		m.killcam.queue_free()
		m.killcam = null
	_best_picture()
	# Nothing drawn until the shot rolls.
	get_viewport().disable_3d = true

func _best_picture() -> void:
	menu.apply_picture({"aa": OS.get_environment("TRAILER_AA") if OS.get_environment("TRAILER_AA") != "" else "msaa4", "voxelAO": true})
	var vp := get_viewport()
	var ss := float(OS.get_environment("TRAILER_SSAA")) if OS.get_environment("TRAILER_SSAA") != "" else 1.5
	if ss > 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = ss
	attrs = CameraAttributesPractical.new()

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		if m and m.arena:
			m.arena.set_excitement(1.0)

func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

func _key() -> void:
	if not keyed and rolling:
		keyed = true
		_tag("KEY %d" % _frame())

func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if rolling and J >= 20.0:
		_tag("HIT %d %d" % [_frame(), int(J)])

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _process(_dt: float) -> void:
	if not rolling or m == null or not cam_fn.is_valid():
		return
	var c: Array = cam_fn.call(t)
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.fov = float(c[2])
	cam.global_position = c[0]
	var fwd: Vector3 = (c[1] as Vector3) - (c[0] as Vector3)
	cam.look_at(c[1], Vector3.UP if absf(fwd.normalized().y) < 0.98 else Vector3.FORWARD)
	cam.reset_physics_interpolation()
	var focus := float(c[3]) if c.size() > 3 else 0.0
	if attrs and focus > 0.0:
		# A long lens's depth: what is far beyond the subject melts away.
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus + 2.0
		attrs.dof_blur_far_transition = 6.0
		attrs.dof_blur_near_enabled = false
		attrs.dof_blur_amount = 0.06
		cam.attributes = attrs
	else:
		cam.attributes = null

# ---------- the shots ----------

## The arena from the sky: the crane starts high over the stands on the far side, the whole bowl
## and its awnings below it, and comes down over the sand to the champion walking in from the
## west gate, ending low in front of him as he comes on (it leads him, backing away). (From the
## south: from the north it came down through the Emperor's box, a dark block across the frame.)
func _reveal() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(-12.0, 0, 0.4))
	hero.yaw = PI * 0.5
	m.me.drive = func(_e): return {"mz": 1.0, "sprint": false, "look": {"yaw": PI * 0.5, "pitch": 0.05}, "main": {"x": 0.3, "y": 0.75}}
	await _steps(60)
	dur = 9.0
	var e0 := Vector3(10.0, 27.0, -26.0)
	var a0 := Vector3(-2.0, 0.0, 0.0)
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var h: Vector3 = hero.torso.global_position
		var e1 := h + Vector3(4.6, -0.05, -1.7)
		var a1 := h + Vector3(0, 0.35, 0)
		# Down fast at first and slowing as it comes to him: the height on its own easing.
		var eye := e0.lerp(e1, u)
		eye.y = lerpf(e0.y, e1.y, 1.0 - pow(1.0 - clampf(tt / dur, 0.0, 1.0), 2.2))
		return [eye, a0.lerp(a1, _ease(tt / dur * 1.1)), lerpf(52.0, 40.0, u), 0.0 if u < 0.7 else eye.distance_to(h)]

## The crowd on its feet under the Emperor's box: low on the sand, a slow dolly along the wall.
func _crowd() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}})
	m.me.f.teleport(Vector3(0, 0, -8.0))
	await _steps(60)
	dur = 4.5
	cam_fn = func(tt: float) -> Array:
		var u := tt / dur
		return [Vector3(lerpf(-3.2, 2.6, u), 0.45 + 0.15 * u, 10.2), Vector3(lerpf(-1.0, 0.8, u), 5.4, 18.5), 46.0, 0.0]

## The dragon pours its fire across the sand at a man running from it; the champion in front of
## it in gilded armour, his axe up. KEY when the fire comes.
func _dragon() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0, 0, 1.0))
	hero.yaw = 0.0
	var pose := {"look": {"yaw": 0.0, "pitch": 0.35}, "main": {"x": 0.15, "y": 1.6}, "off": {"x": -0.9, "y": 0.6}, "twist": 1.3}
	m.me.drive = func(_e): return pose
	var dragon = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(1.2, 0.1, -6.5), "yaw": -0.5, "harmless": true})
	dragon.f.sp = dragon.f.sp.duplicate()
	dragon.f.sp.speed = 0.0
	dragon.f.sp.lunge = 0.0
	dragon.f.sp.ai = "statue"
	var runner = m.spawn_fighter({"kind": "bot", "name": "Runner", "loadout": {"main": "spear", "off": "roundShield"}, "team": 2, "pos": Vector3(1.5, 0, -3.5), "yaw": -PI * 0.5})
	runner.erase("bot")
	runner.drive = func(_e): return {"mz": 1.0, "sprint": true, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": -0.3, "y": 1.2}}
	await _steps(120)
	dragon.f.target = runner.f
	var reach := float(dragon.f.sp.get("breathRange", 6.0))
	m._breath(dragon.f, "fire", reach)
	dur = 5.0
	var c: Vector3 = hero.torso.global_position
	var aimed := [false]
	tick_fn = func(_tt: float) -> void:
		var pouring: bool = m.streams.any(func(st): return st.b == dragon.f and float(st.t) < 0.75)
		if pouring and not aimed[0]:
			aimed[0] = true
			_key()
			# (The jet lit again the way the head points by now: the first burst goes where the
			# head was when it drew breath.)
			m.breath_at(dragon.f, "fire", dragon.f.mouth_dir(), reach, 1.6)
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var eye := c + Vector3(lerpf(2.6, 1.6, u), lerpf(-0.15, -0.3, u), lerpf(5.4, 4.0, u))
		return [eye, c + Vector3(-0.3, 0.9, -2.8), 46.0, eye.distance_to(c + Vector3(0, 0, -3.0))]

## A man charges; the champion bowls a wheel of cheese along the sand at his feet and it takes
## him clean off them. Low on the sand beside the wheel's way. KEY when he goes down.
func _cheese() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": "gladius", "off": "", "armor": ["helmet"]}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0, 0, -3.5))
	hero.yaw = 0.0
	var bowl := [false]
	m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": -0.2}, "main": {"x": 0.35, "y": -1.0 if bowl[0] else 0.4}, "crouch": bowl[0]}
	var foe = m.spawn_fighter({"kind": "bot", "name": "Brutus", "loadout": {"main": "warhammer", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0.3, 0, 6.0), "yaw": PI})
	foe.erase("bot")
	foe.drive = func(_e): return {"mz": 1.0, "sprint": true, "look": {"yaw": PI, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.3}}
	foe.f.mods.toughness = 4.0
	await _steps(30)
	dur = 4.5
	var thrown := [false]
	tick_fn = func(tt: float) -> void:
		if not thrown[0] and tt > 0.55:
			bowl[0] = true
		if not thrown[0] and tt > 0.75:
			thrown[0] = true
			# Bowled as the game bowls it: on its edge on the sand in front of him, rolling at
			# the man's feet.
			var to: Vector3 = foe.f.torso.global_position - hero.torso.global_position
			to.y = 0.0
			var fwd := to.normalized()
			var cp: Vector3 = hero.torso.global_position + fwd * 0.8
			var it: Dictionary = m.items.spawn("cheese", Vector3(cp.x, 0.21, cp.z), fwd * 8.0, hero)
			it.grounded = true
		if thrown[0] and is_instance_valid(foe.f) and foe.f.state != "stand":
			_key()
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var mid: Vector3 = (hero.torso.global_position + foe.f.torso.global_position) * 0.5 if is_instance_valid(foe.f) else hero.torso.global_position
		# (Wide enough for both of them as he comes on: at 42 degrees the man came in cut off.)
		var eye := Vector3(lerpf(4.0, 3.2, u), 0.32, lerpf(-1.8, 1.4, u))
		var at := Vector3(mid.x, 0.55, lerpf(mid.z - 0.6, mid.z + 1.6, u))
		return [eye, at, 50.0, eye.distance_to(at)]

## Everyone against everyone: seven fighters, seconds in (the sand already red), seen from above
## the thick of it and going round. (It looks at the knot where most are fighting, not at the
## middle of them all: spread over the sand, that was empty sand.)
func _chaos() -> void:
	_start({"mode": "ffa", "autopilot": true})
	var looks := [{"main": "axe", "off": "scutum"}, {"main": "longsword", "off": ""}, {"main": "mace", "off": "dagger"}, {"main": "spear", "off": "roundShield"}]
	for i in 3:
		var a := TAU * (float(i) / 3.0) + 0.6
		m.spawn_fighter({"kind": "bot", "name": "Brawler %d" % (i + 1), "loadout": looks[i % looks.size()], "team": 10 + i, "pos": Vector3(sin(a) * 3.5, 0, cos(a) * 3.5), "yaw": a + PI, "diff": 0.85})
	await _steps(int(120 * 4.5))
	dur = 5.5
	var turn0 := randf() * TAU
	var focus := [_thick()]
	tick_fn = func(_tt: float) -> void:
		focus[0] = (focus[0] as Vector3).lerp(_thick(), 1.5 / 120.0)
	cam_fn = func(tt: float) -> Array:
		var c: Vector3 = focus[0]
		var a := turn0 + tt * 0.2
		var eye := c + Vector3(sin(a) * 7.5, 4.8 - tt * 0.2, cos(a) * 7.5)
		var flat := Vector2(eye.x, eye.z)
		if flat.length() > 13.5:
			flat = flat.normalized() * 13.5
			eye = Vector3(flat.x, eye.y, flat.y)
		return [eye, c, 52.0, 0.0]

## Where the fighting is thickest: the living fighter with the most others within 3.5 m, and
## those others, their middle.
func _thick() -> Vector3:
	var live := []
	for e in m.entities:
		if is_instance_valid(e.f) and e.f.alive:
			live.append(e.f.torso.global_position)
	if live.is_empty():
		return Vector3(0, 0.8, 0)
	var best := -1
	var at := Vector3.ZERO
	for p in live:
		var near := []
		for q in live:
			if (q as Vector3).distance_to(p) < 3.5:
				near.append(q)
		if near.size() > best:
			best = near.size()
			at = Vector3.ZERO
			for q in near:
				at += q
			at /= near.size()
	at.y = 0.8
	return at

## Friends against the minotaur and his wolves: the three of them with their names over their
## heads, as online; behind them, low, going in.
func _squad() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}, "autopilot": true,
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	m.me.f.teleport(Vector3(0, 0, 0))
	var allies := [
		m.spawn_fighter({"kind": "bot", "name": NAMES[0], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "manica"]}, "team": 0, "pos": Vector3(-1.6, 0, -0.6), "yaw": 0.0, "diff": 0.9}),
		m.spawn_fighter({"kind": "bot", "name": NAMES[1], "loadout": {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, "team": 0, "pos": Vector3(1.6, 0, -0.6), "yaw": 0.0, "diff": 0.9}),
		m.spawn_fighter({"kind": "bot", "name": NAMES[2], "loadout": {"main": "longsword", "off": "", "armor": ["manica"]}, "team": 0, "pos": Vector3(0.4, 0, -1.8), "yaw": 0.0, "diff": 0.9}),
	]
	for al in allies:
		m._name_tag(al.f, String(al.spec.get("name", "")))
	var spec: Dictionary = m.enemy_spec({"e": "minotaur", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 6.5)
	spec.yaw = PI
	var boss = m.spawn_fighter(spec)
	for i in 2:
		m.spawn_beast({"beast": "wolf", "team": Match.ENEMY_TEAM, "pos": Vector3(-3.0 + 6.0 * i, 0.1, 5.5), "yaw": PI})
	await _steps(int(120 * 1.6))
	dur = 6.0
	cam_fn = func(tt: float) -> Array:
		var pts := [m.me.f.torso.global_position]
		for al in allies:
			if is_instance_valid(al.f) and al.f.alive:
				pts.append(al.f.torso.global_position)
		var sq := Vector3.ZERO
		for p in pts:
			sq += p
		sq /= pts.size()
		var bp: Vector3 = boss.f.torso.global_position if is_instance_valid(boss.f) else Vector3(0, 1.5, 6.0)
		var d := bp - sq
		d.y = 0.0
		d = d.normalized() if d.length() > 0.1 else Vector3(0, 0, 1)
		var side := d.cross(Vector3.UP)
		var u := _ease(tt / dur)
		# Off to the side of them, so the three names over their heads stand apart (from behind
		# they stood one over another).
		var eye := sq - d * lerpf(4.8, 3.4, u) + side * 2.6 + Vector3(0, 0.8, 0)
		var at := sq.lerp(bp, 0.6) + Vector3(0, 0.9, 0)
		return [eye, at, 50.0, eye.distance_to(at)]

## The champion alone in the middle, his back to us, his axe raised to the stands and the
## Emperor's box; low behind him, going in and up. The end card goes over it.
func _finale() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0, 0, 2.0))
	hero.yaw = 0.0
	m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.45}, "main": {"x": 0.1, "y": 1.7}, "off": {"x": -0.7, "y": 1.1}}
	await _steps(120)
	dur = 10.0
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var h: Vector3 = hero.torso.global_position
		var eye := h + Vector3(lerpf(0.9, 0.5, u), lerpf(-0.45, -0.2, u), lerpf(-4.2, -2.9, u))
		return [eye, Vector3(0, lerpf(2.4, 3.6, u), 12.0), 50.0, eye.distance_to(h)]

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
