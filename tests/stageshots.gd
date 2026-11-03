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
## - finale: the champion alone in the middle, his back to us, his axe raised to the crowd;
## - cut: the champion with the executioner's axe (the one the forge builds) brings it down on a
##   swordsman coming at him, edge first (KEY), the film camera close beside them;
## - spear: a man charges the champion's spear; it takes him in the face, his legs run on under
##   him and he goes over backwards, heels over head (KEY at the blow).
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
var best_f := -1
var key_tail := -1.0      # > 0: the shot ends this long after its KEY (a fight that runs until it)
var peek_on_key := false  # STAGE_PEEK frames round the KEY, not evenly through the shot
var peek_at := []

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
		"cut":
			await _cut()
		"spear":
			await _spear()
		_:
			print("STAGE: reveal, crowd, dragon, cheese, chaos, squad, finale, cut, spear")
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
		var due: bool = (t >= float(peek_at[peeked])) if peeked < peek_at.size() else (peek_at.is_empty() and not peek_on_key and t >= dur * float(peeked) / float(peek))
		if peek > 0 and peeked < peek and due:
			get_viewport().disable_3d = false
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("peek_%s_%d.png" % [shot, peeked]))
			peeked += 1
			get_viewport().disable_3d = true
	# A fight that never came to its moment: the hardest blow of the champion's is its moment.
	if key_tail > 0.0 and not keyed and best_f >= 0:
		_tag("KEY %d" % best_f)
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
		if key_tail > 0.0:
			dur = minf(dur, t + key_tail)
		if peek_on_key:
			peek_at = [t + 0.02, t + 0.3, t + 0.7, t + 1.3]

func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if rolling and J >= 20.0:
		_tag("HIT %d %d" % [_frame(), int(J)])
	if rolling and m and m.me and h.get("attacker") == m.me.f and J > best_j:
		best_j = J
		best_f = _frame()

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

## Friends against the minotaur and his wolves (BRING YOUR FRIENDS): the champion and three
## friends, their names over their heads as online, abreast across the sand; they charge the
## minotaur together and meet him. Low behind the line as it runs, the four of them across the
## frame and the minotaur over them in the middle; KEY at the first hard blow of the clash. (Left
## to themselves from the start, they bunched into a scrum and the names stood one over another.)
func _squad() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}, "autopilot": true,
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var line := [m.me]
	m.me.f.teleport(Vector3(-1.1, 0, -4.5))
	m.me.f.yaw = 0.0
	var kit := [{"main": "gladius", "off": "scutum", "armor": ["helmet", "manica"]}, {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, {"main": "longsword", "off": "", "armor": ["manica"]}]
	var xs := [-3.4, 1.2, 3.5]
	for i in 3:
		var al = m.spawn_fighter({"kind": "bot", "name": NAMES[i], "loadout": kit[i], "team": 0, "pos": Vector3(xs[i], 0, -4.5), "yaw": 0.0, "diff": 0.9})
		m._name_tag(al.f, NAMES[i])
		line.append(al)
	var spec: Dictionary = m.enemy_spec({"e": "minotaur", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 6.5)
	spec.yaw = PI
	var boss = m.spawn_fighter(spec)
	# He stands his ground, roaring, until they are nearly on him (going for them at once, he met
	# them half a second in and there was no charge to see).
	boss.drive = func(_e): return {"look": {"yaw": PI, "pitch": 0.2}, "main": {"x": 0.5, "y": 1.3}}
	for i in 2:
		m.spawn_beast({"beast": "wolf", "team": Match.ENEMY_TEAM, "pos": Vector3(-4.0 + 8.0 * i, 0.1, 7.5), "yaw": PI})
	# The charge: all four run at him together, weapons up, until they are on him; then each
	# fights as he will.
	var charge := func(e): return {"mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.2}}
	for e in line:
		e.drive = charge
	await _steps(20)
	dur = 6.5
	key_tail = 3.2
	var let_go := [false]
	tick_fn = func(tt: float) -> void:
		if not let_go[0] and (tt > 2.2 or (is_instance_valid(boss.f) and m.me.f.torso.global_position.distance_to(boss.f.torso.global_position) < 3.4)):
			let_go[0] = true
			for e in line:
				e.erase("drive")
			boss.erase("drive")
	var on_hit := func(h: Dictionary) -> void:
		if rolling and float(h.get("J", 0.0)) >= 25.0 and (h.get("char") == boss.f or h.get("attacker") == boss.f):
			_key()
	m.combat.hit.connect(on_hit)
	cam_fn = func(tt: float) -> Array:
		var c := Vector3.ZERO
		var n := 0
		for e in line:
			if is_instance_valid(e.f) and e.f.alive:
				c += e.f.torso.global_position
				n += 1
		c = c / maxf(1, n)
		var bp: Vector3 = boss.f.torso.global_position if is_instance_valid(boss.f) else Vector3(0, 1.5, 5.5)
		# Low behind the running line, then, once they are on him, held off and a little higher,
		# over their shoulders (pushed on into the scrum, a man's back filled the frame).
		var u := _ease(tt / 2.0)
		var eye := Vector3(c.x * 0.5, lerpf(0.55, 1.15, u), c.z - lerpf(3.6, 4.4, u))
		var at := Vector3(bp.x * 0.6, bp.y + 0.55, bp.z)
		return [eye, at, 54.0, eye.distance_to(Vector3(c.x, 1.0, c.z))]

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

## A film camera on two fighters: low beside the line between them on the side of `side_ref`
## (the stands behind them, not the wall), as far as a long lens wants for both, looking at their
## middle; `push` brings it in over the shot.
func _film2(a: Fighter, b: Fighter, side_ref: Vector3, back: float, height: float, fov: float) -> Array:
	var pa: Vector3 = a.torso.global_position
	var pb: Vector3 = b.torso.global_position if is_instance_valid(b) else pa + Vector3(1, 0, 0)
	var mid := pa.lerp(pb, 0.5)
	var d := pb - pa
	d.y = 0.0
	d = d.normalized() if d.length() > 0.05 else Vector3(1, 0, 0)
	var s := Vector3.UP.cross(d)
	if s.dot(side_ref) < 0.0:
		s = -s
	var eye := mid + s * back
	eye.y = height
	var flat := Vector2(eye.x, eye.z)
	if flat.length() > 13.5:
		flat = flat.normalized() * 13.5
		eye = Vector3(flat.x, eye.y, flat.y)
	var at := mid + Vector3(0, 0.15, 0)
	return [eye, at, fov, eye.distance_to(at)]

## The cut: the champion, gilded, with the executioner's axe (the very one the forge builds, for
## the cut from the anvil to the arena). A swordsman comes on at a walk, his blade up over his
## head; the champion raises the axe high and, as the man comes into reach, brings it straight
## down through him with all he has, edge first: the chop is the KEY (or a limb coming off,
## should it). The blow itself is the game's own, as hard as the swing is fast. (Swept across,
## the axe met him with its flat or its haft whatever the timing; a free fight took a limb off in
## one run and not in another.) The film camera close beside them, low, the Emperor's box behind.
func _cut() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": "executionerAxe", "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.mods.strength = float(OS.get_environment("CUT_STR")) if OS.get_environment("CUT_STR") != "" else 4.5
	hero.mods.toughness = 6.0
	hero.teleport(Vector3(-1.6, 0, 0))
	hero.yaw = PI * 0.5
	var foe = m.spawn_fighter({"kind": "bot", "name": "Verus", "loadout": {"main": "gladius", "off": "", "armor": ["helmet"]}, "team": Match.ENEMY_TEAM, "pos": Vector3(5.0, 0, 0), "yaw": -PI * 0.5})
	foe.erase("bot")
	var cut_done := [false]
	foe.drive = func(_e): return {} if cut_done[0] else {"mz": 1.0, "sprint": OS.get_environment("CUT_RUN") == "1", "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.2, "y": 1.5}}
	var reach := float(OS.get_environment("CUT_REACH")) if OS.get_environment("CUT_REACH") != "" else 1.6
	var height := float(OS.get_environment("CUT_Y")) if OS.get_environment("CUT_Y") != "" else 0.62
	var swing_t := [-1.0]
	var chop := OS.get_environment("CUT_MODE") != "sweep"
	var edge := float(OS.get_environment("CUT_TWIST")) if OS.get_environment("CUT_TWIST") != "" else 0.0
	var swing_s := float(OS.get_environment("CUT_SWING")) if OS.get_environment("CUT_SWING") != "" else 0.1
	m.me.drive = func(_e):
		var to: Vector3 = foe.f.torso.global_position - hero.torso.global_position
		var yaw := atan2(to.x, to.z) if Vector2(to.x, to.z).length() > 0.3 else PI * 0.5
		var k := -1.0
		if swing_t[0] >= 0.0:
			k = clampf((t - swing_t[0]) / swing_s, 0.0, 1.0)
		if chop:
			# Raised high over his head, then straight down through the man's raised arm.
			var y := 1.65 if k < 0.0 else lerpf(1.65, -0.7, k)
			return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.12, "y": y}, "power": k >= 0.0 and k < 1.0, "twist": edge}
		var x := 0.85 if k < 0.0 else lerpf(0.85, -0.95, k)
		return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": x, "y": height}, "power": k >= 0.0 and k < 1.0, "twist": edge}
	await _steps(30)
	dur = 7.0
	key_tail = 2.6
	peek_on_key = true
	tick_fn = func(tt: float) -> void:
		if swing_t[0] < 0.0 and is_instance_valid(foe.f) and Vector2(foe.f.torso.global_position.x - hero.torso.global_position.x, foe.f.torso.global_position.z - hero.torso.global_position.z).length() < reach:
			swing_t[0] = tt
		if OS.get_environment("STAGE_DEBUG") == "1" and int(tt * 120.0) % 12 == 0:
			print("DBG t=%.2f gap=%.2f swing=%.2f foe=%s" % [tt, Vector2(foe.f.torso.global_position.x - hero.torso.global_position.x, foe.f.torso.global_position.z - hero.torso.global_position.z).length(), swing_t[0], foe.f.state])
	var on_hit := func(h: Dictionary) -> void:
		if rolling and h.get("attacker") == hero and h.get("char") == foe.f:
			var sev: Array = (h.res.get("severed", []) as Array) if h.get("res") is Dictionary else []
			if OS.get_environment("STAGE_DEBUG") == "1":
				print("DBG blow %s J=%.0f severed %d type %s" % [String(h.part.name) if h.get("part") is Node else "-", float(h.get("J", 0.0)), sev.size(), str(h.get("type", "?"))])
			# The chop landing (the edge into him, J 50 and over), or a limb coming off.
			if not sev.is_empty() or float(h.get("J", 0.0)) >= 50.0:
				cut_done[0] = true
				_key()
	m.combat.hit.connect(on_hit)
	cam_fn = func(tt: float) -> Array:
		return _film2(hero, foe.f, Vector3(0, 0, -1), 3.4, 1.0, 40.0)

## The spear: a man with a sword raised charges the champion across the sand; the champion sets
## his feet and thrusts for the face. It takes him there: the head stops and is driven back while
## the legs run on under him, and he goes over backwards, heels over head, onto his back (a man
## running into a bar; user: a man speared in the head goes over backwards, not off through the
## air). The fall is his own body's: the blow takes his footing (he goes limp, as a man struck
## senseless does) and the head is stopped where the legs keep the run's speed, lifting as they
## swing. KEY at the blow. The camera low and square to the charge, wide enough for the fall.
func _spear() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": "spear", "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.mods.strength = 3.0
	hero.mods.toughness = 6.0
	hero.teleport(Vector3(-2.5, 0, 0))
	hero.yaw = PI * 0.5
	var foe = m.spawn_fighter({"kind": "bot", "name": "Crixus", "loadout": {"main": "gladius", "off": "", "armor": []}, "team": Match.ENEMY_TEAM, "pos": Vector3(6.5, 0, float(OS.get_environment("SPEAR_Z")) if OS.get_environment("SPEAR_Z") != "" else 0.32), "yaw": -PI * 0.5})
	foe.erase("bot")
	foe.f.mods.toughness = 4.0
	var struck := [false]
	var thrust := [false]
	var aim_y := float(OS.get_environment("SPEAR_Y")) if OS.get_environment("SPEAR_Y") != "" else 0.18
	# He runs at the point itself (a stuntman runs at his mark): his line bends onto the spear's
	# tip as he comes, so his face meets it however the champion's arm holds it.
	foe.drive = func(_e):
		if struck[0]:
			return {}
		var w = hero.weapons.get("R")
		var at: Vector3 = (w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)) if w else hero.head.global_position
		var to: Vector3 = at - foe.f.head.global_position
		return {"mz": 1.0, "sprint": true, "look": {"yaw": atan2(to.x, to.z), "pitch": 0.0}, "main": {"x": 0.3, "y": 1.4}}
	m.me.drive = func(_e):
		var to: Vector3 = foe.f.head.global_position - hero.head.global_position
		var yaw := atan2(to.x, to.z)
		return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.0, "y": aim_y}, "thrust": 1.0 if thrust[0] and not struck[0] else 0.0}
	await _steps(30)
	dur = 6.0
	key_tail = 3.0
	peek_on_key = true
	var on_hit := func(h: Dictionary) -> void:
		if not rolling or struck[0] or h.get("attacker") != hero or h.get("char") != foe.f:
			return
		struck[0] = true
		_key()
		if OS.get_environment("STAGE_DEBUG") == "1":
			print("DBG struck %s J=%.0f" % [String(h.part.name) if h.get("part") is Node else "-", float(h.get("J", 0.0))])
		var v: Vector3 = foe.f.torso.linear_velocity
		_over_backwards(foe.f, Vector3(v.x, 0, v.z).normalized() if Vector2(v.x, v.z).length() > 0.5 else Vector3(-1, 0, 0))
	m.combat.hit.connect(on_hit)
	tick_fn = func(_tt: float) -> void:
		if is_instance_valid(foe.f) and not thrust[0] and foe.f.head.global_position.distance_to(hero.head.global_position) < 2.7:
			thrust[0] = true
		if OS.get_environment("STAGE_DEBUG") == "1" and int(_tt * 120.0) % 6 == 0:
			var up: Vector3 = foe.f.torso.global_transform.basis.y.normalized()
			var w = hero.weapons.get("R")
			var tip: Vector3 = (w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)) if w else Vector3.ZERO
			print("DBG t=%.2f foe=%s head=%s tip=%s tilt=%.0f" % [_tt, foe.f.state, str(foe.f.head.global_position.snapped(Vector3.ONE * 0.01)), str(tip.snapped(Vector3.ONE * 0.01)), rad_to_deg(atan2(up.x, up.y))])
	cam_fn = func(tt: float) -> Array:
		var pf: Vector3 = foe.f.torso.global_position if is_instance_valid(foe.f) else Vector3.ZERO
		var mid := hero.torso.global_position.lerp(pf, 0.55)
		var eye := Vector3(mid.x, 0.75, mid.z - 5.2)
		return [eye, mid + Vector3(0, 0.35, 0), 44.0, eye.distance_to(mid)]

## A running man stopped by the head: limp (the blow takes his footing), his head and shoulders
## stopped and driven back the way he came, his hips and legs keeping the run's speed and
## lifting, so he turns over backwards about his middle. `run` the way he was running.
func _over_backwards(f: Fighter, run: Vector3) -> void:
	f.fall(2.5, true)
	var hips: float = f.torso.global_position.y - 0.25 * f.S
	for p in f.parts:
		if p.severed:
			continue
		var h: float = (p.global_position.y - hips) / f.S
		var v: Vector3 = p.linear_velocity
		var along := v.dot(run)
		if h > 0.0:
			# Above the hips: stopped, and driven back the more the higher (the head most).
			p.linear_velocity = v - run * along - run * (1.6 + 2.2 * h)
		else:
			# The hips and legs run on, and swing up.
			p.linear_velocity = v + run * 0.6 + Vector3(0, 2.8 * minf(1.0, -h * 1.6) + 0.8, 0)

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
