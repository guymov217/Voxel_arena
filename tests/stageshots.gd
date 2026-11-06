extends Node
## The staged shots of the crowd trailer (`-- --probe stageshots`, needs a display; run through
## tools/make_blood_trailer.py, which records them with the movie maker at 120 frames a second).
## STAGE picks the shot:
## - reveal: the arena from the sky, a crane coming down over the full stands and the awnings to
##   the sand, where the champion walks in from the gate (ENTER THE ARENA);
## - crowd: low on the sand under the Emperor's box, the stands on their feet, a slow dolly;
## - maul: a lion runs at a man backing away from it, leaps, and bears him down under it on the
##   sand, its jaws at him (NOT EVERY FOE IS A MAN);
## - dragon: the dragon pours its fire across the sand at a man running from it, and the
##   champion charges it, his axe up, the camera low behind him;
## - cheese: a wheel of cheese bowled along the sand takes a charging man off his feet;
## - chaos: a free-for-all, six strong men close together, seen low and close on the thick of
##   it, the camera going round;
## - squad: friends, their names over their heads, charge the troll, which sweeps three of them
##   flying with one blow;
## - finale: the champion alone in the middle, his back to us, his axe raised to the crowd;
## - cut: the champion with the executioner's axe (the one the forge builds) brings it down on a
##   swordsman coming at him, edge first (KEY), the film camera close beside them;
## - spear: a man charges the champion, who throws his spear into his face: his legs run on under
##   him and he goes over backwards, dead (KEY at the blow).
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
	# (A peek draws nothing but its frames: on a software renderer the drawing, not the game, is
	# what takes the time, even with the 3D off.)
	if OS.get_environment("STAGE_PEEK") != "":
		RenderingServer.render_loop_enabled = false
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
		"maul":
			await _maul()
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
			print("STAGE: reveal, crowd, maul, dragon, cheese, chaos, squad, finale, cut, spear")
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
			RenderingServer.render_loop_enabled = true
			# (Held still a few frames first: the light, the shadows and the eye's exposure take a
			# while to come back after frames undrawn, and the first one drawn was dark.)
			get_tree().paused = true
			for i in (int(OS.get_environment("STAGE_PEEK_WARM")) if OS.get_environment("STAGE_PEEK_WARM") != "" else 24):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("peek_%s_%d.png" % [shot, peeked]))
			get_tree().paused = false
			peeked += 1
			get_viewport().disable_3d = true
			RenderingServer.render_loop_enabled = false
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

## The arena from the sky: the crane starts high over the sand, inside the ring of the awnings,
## the whole bowl and the sails round it below, and comes down to the champion walking in from the
## west gate, ending low in front of him as he comes on (it leads him, backing away). (From over
## the stands it came down through the sails, the cloth across the whole frame: user; from the
## north, through the Emperor's box.) The Emperor in his box.
func _reveal() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(-12.0, 0, 0.4))
	hero.yaw = PI * 0.5
	m.me.drive = func(_e): return {"mz": 1.0, "sprint": false, "look": {"yaw": PI * 0.5, "pitch": 0.05}, "main": {"x": 0.3, "y": 0.75}}
	_emperor()
	await _steps(60)
	dur = 9.0
	var e0 := Vector3(3.0, 27.0, -4.0)
	var a0 := Vector3(-3.0, 0.0, 2.5)
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var h: Vector3 = hero.torso.global_position
		var e1 := h + Vector3(4.6, -0.05, -1.7)
		var a1 := h + Vector3(0, 0.35, 0)
		# Down fast at first and slowing as it comes to him: the height on its own easing.
		var eye := e0.lerp(e1, u)
		eye.y = lerpf(e0.y, e1.y, 1.0 - pow(1.0 - clampf(tt / dur, 0.0, 1.0), 2.2))
		return [eye, a0.lerp(a1, _ease(tt / dur * 1.1)), lerpf(52.0, 40.0, u), 0.0 if u < 0.7 else eye.distance_to(h)]

## The crowd on its feet under the Emperor's box: low on the sand, a slow dolly along the wall, the
## Emperor in his box over them, his hand raised (user: put an Emperor in the box).
func _crowd() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}})
	m.me.f.teleport(Vector3(0, 0, -8.0))
	_emperor(true)
	await _steps(60)
	dur = 4.5
	cam_fn = func(tt: float) -> Array:
		var u := tt / dur
		return [Vector3(lerpf(-3.2, 2.6, u), 0.45 + 0.15 * u, 10.2), Vector3(lerpf(-1.0, 0.8, u), 5.4, 18.5), 46.0, 0.0]

## The lion (NOT EVERY FOE IS A MAN): a man in a helmet backs away across the sand, his spear out at
## a lion that comes on low; it runs at him and, four strides off, leaps: it takes him in the chest
## in the air and bears him down on his back under its weight, and its jaws go at him there (user:
## in the lion's scene something real has to happen). The leap is the game's own lunge thrown
## harder; the man's fall his own body's. Low on the sand, square to the run, the lion crossing the
## frame; KEY as it strikes him.
func _maul() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}})
	_emperor(true)   # (his box in the shot: the Emperor in it, user)
	m.me.f.teleport(Vector3(0, 0, -12.0))
	var man = m.spawn_fighter({"kind": "bot", "name": "Spiculus", "loadout": {"main": "spear", "off": "roundShield", "armor": ["helmet", "manica"]}, "team": 2, "pos": Vector3(2.6, 0, 0.3), "yaw": -PI * 0.5})
	man.erase("bot")
	var down := [false]
	man.drive = func(_e): return {} if down[0] else {"mz": -0.45, "look": {"yaw": -PI * 0.5, "pitch": 0.05}, "main": {"x": 0.25, "y": 0.35}, "off": {"x": -0.45, "y": 0.7}}
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(-5.2, 0.1, 0.0), "yaw": PI * 0.5})
	var lf = lion.f
	lf.sp = lf.sp.duplicate()
	lf.target = man.f
	await _steps(30)
	dur = 5.0
	key_tail = 2.6
	var leapt := [false]
	var bites := [0, 0.0]
	var leap_at := float(OS.get_environment("MAUL_AT")) if OS.get_environment("MAUL_AT") != "" else 4.4
	tick_fn = func(tt: float) -> void:
		if not is_instance_valid(lf) or not is_instance_valid(man.f):
			return
		var to: Vector3 = man.f.torso.global_position - lf.torso.global_position
		to.y = 0.0
		var dist := to.length()
		if not leapt[0]:
			# On at him at a run (no circling, no feint: it has made up its mind).
			if lf.ai.mode != "charge":
				lf.ai.mode = "charge"
				lf.ai.t = 3.0
			lf.ai.bite_cool = 9.0
			if dist < leap_at:
				# The leap: as fast along as lands it on his chest in the time it is in the air,
				# and as fast up as keeps it there that long (the game's lunge, thrown harder).
				leapt[0] = true
				lf.ai.bite_cool = 0.0
				var air := float(OS.get_environment("MAUL_AIR")) if OS.get_environment("MAUL_AIR") != "" else 0.55
				var lv: Vector3 = lf.torso.linear_velocity
				var along: float = Vector2(lv.x, lv.z).dot(Vector2(to.x, to.z).normalized())
				lf.sp.lunge = maxf(0.5, (dist - 0.6) / air - along)
				var mass := 0.0
				for p in lf.parts:
					mass += p.mass
				lf._lunge(to.normalized(), mass, false)
				lf.torso.apply_central_impulse(Vector3(0, mass * maxf(0.0, 9.8 * air * 0.5 - 1.2), 0))
		if down[0] and is_instance_valid(man.f):
			# On him: it walks up over him until its chest is over his, its forepaws either side
			# of him, and stays there (stopped where it struck him, it stood beside him, user).
			var over: Vector3 = man.f.torso.global_position - lf.torso.global_position
			over.y = 0.0
			var fwd: Vector3 = lf.torso.global_transform.basis.z
			fwd.y = 0.0
			var want: Vector3 = over - fwd.normalized() * 0.55 * lf.S
			if want.length() > 0.15:
				var v: Vector3 = want.limit_length(1.6)
				lf.torso.linear_velocity = Vector3(v.x, lf.torso.linear_velocity.y, v.z)
		if down[0] and int(bites[0]) < 4 and tt - float(bites[1]) > 0.42:
			# On him: the jaws at his throat and his chest, again and again.
			bites[0] = int(bites[0]) + 1
			bites[1] = tt
			var aim: Vector3 = (man.f.torso.global_position + Vector3(0, 0.15, 0)) - lf.head.global_position
			lf._strike(lf.head, 0.3, 0.0, [lf.head, aim.normalized() * 30.0 * lf.head.mass], 0.0)
		if OS.get_environment("STAGE_DEBUG") == "1" and int(tt * 120.0) % 12 == 0:
			print("DBG t=%.2f dist=%.2f mode=%s leapt=%s down=%s lion_y=%.2f" % [tt, dist, str(lf.ai.mode), leapt[0], down[0], lf.torso.global_position.y])
	var on_hit := func(h: Dictionary) -> void:
		if not rolling or h.get("attacker") != lf or h.get("char") != man.f or down[0]:
			return
		down[0] = true
		_key()
		# Borne down under its weight: off his feet, driven back the way it leapt, the lion on him.
		var dir: Vector3 = lf.torso.linear_velocity
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.5 else Vector3(1, 0, 0)
		man.f.fall(3.0, true)
		for p in man.f.parts:
			if not p.severed:
				var hgt: float = p.global_position.y - man.f.torso.global_position.y + 0.3
				p.linear_velocity += dir * (2.2 + 1.4 * maxf(0.0, hgt)) + Vector3(0, -0.6, 0)
		# It stands over him now, and does nothing but bite. (Its body and legs pass over his: met by
		# them it stopped a stride short and stood beside him. Its jaws still meet him.)
		lf.sp.ai = "statue"
		lf.sp.speed = 0.0
		for a in lf.parts:
			if a != lf.head:
				for b in man.f.parts:
					a.add_collision_exception_with(b)
	m.combat.hit.connect(on_hit)
	cam_fn = func(tt: float) -> Array:
		var pm: Vector3 = man.f.torso.global_position if is_instance_valid(man.f) else Vector3(2.6, 0.8, 0)
		var pl: Vector3 = lf.torso.global_position if is_instance_valid(lf) else Vector3(-2, 0.8, 0)
		var mid := pm.lerp(pl, 0.45)
		var u := _ease(tt / dur)
		var eye := Vector3(mid.x + lerpf(-0.6, 0.4, u), lerpf(0.55, 0.8, u), mid.z - lerpf(6.0, 4.6, u))
		return [eye, mid + Vector3(0, 0.25, 0), 44.0, eye.distance_to(mid)]

## The dragon pours its fire across the sand at a man running from it, and the champion charges
## it through the smoke, his axe up: low behind him as he runs at it, the dragon over him and the
## fire across the frame (user: not a man standing there facing the camera). KEY when the fire
## comes.
func _dragon() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0.6, 0, 8.5))
	hero.yaw = PI
	var run := [false]
	m.me.drive = func(_e): return {"mz": 1.0 if run[0] else 0.0, "sprint": run[0], "look": {"yaw": PI, "pitch": 0.15}, "main": {"x": 0.15, "y": 1.6}, "off": {"x": -0.9, "y": 0.6}, "twist": 1.3}
	var dragon = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(1.2, 0.1, -6.5), "yaw": -0.3, "harmless": true})
	dragon.f.sp = dragon.f.sp.duplicate()
	dragon.f.sp.speed = 0.0
	dragon.f.sp.lunge = 0.0
	dragon.f.sp.ai = "statue"
	var runner = m.spawn_fighter({"kind": "bot", "name": "Runner", "loadout": {"main": "spear", "off": "roundShield"}, "team": 2, "pos": Vector3(4.5, 0, -1.5), "yaw": -PI * 0.5})
	runner.erase("bot")
	runner.drive = func(_e): return {"mz": 1.0, "sprint": true, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": -0.3, "y": 1.2}}
	await _steps(90)
	dragon.f.target = runner.f
	var reach := float(dragon.f.sp.get("breathRange", 6.0))
	m._breath(dragon.f, "fire", reach)
	dur = 5.0
	var aimed := [false]
	tick_fn = func(tt: float) -> void:
		if tt > 0.4:
			run[0] = true
		var pouring: bool = m.streams.any(func(st): return st.b == dragon.f and float(st.t) < 0.75)
		if pouring and not aimed[0]:
			aimed[0] = true
			_key()
			# (The jet lit again the way the head points by now: the first burst goes where the
			# head was when it drew breath.)
			m.breath_at(dragon.f, "fire", dragon.f.mouth_dir(), reach, 1.6)
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var u := _ease(tt / dur)
		var eye := h + Vector3(lerpf(1.6, 1.1, u), lerpf(-0.1, 0.05, u), lerpf(3.4, 2.6, u))
		var dh: Vector3 = dragon.f.head.global_position if is_instance_valid(dragon.f) and dragon.f.head else Vector3(1.2, 3.0, -6.5)
		var at := h.lerp(dh, 0.6) + Vector3(0, 0.4, 0)
		return [eye, at, 50.0, eye.distance_to(h)]

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

## Everyone against everyone (CHOOSE YOUR CHAOS): six fighters close together, seconds in, every
## one of them strong in the arm and fighting for his life, so the blows land hard and take limbs
## off (user: sharp, clear and brutal); seen low and close on the thick of it, the camera going
## round slowly, the background melting away. (From above at seven yards they were specks.)
func _chaos() -> void:
	_start({"mode": "ffa", "autopilot": true})
	var looks := [{"main": "axe", "off": "scutum"}, {"main": "longsword", "off": ""}]
	for i in 2:
		m.spawn_fighter({"kind": "bot", "name": "Brawler %d" % (i + 1), "loadout": looks[i], "team": 10 + i, "pos": Vector3(0, 0, 9.0 + i), "yaw": PI, "diff": 0.95})
	# All six in a ring a few strides across, facing in: the free-for-all's own three, two more and
	# the champion.
	var ring := []
	for e in m.entities:
		if is_instance_valid(e.f) and not (e.f is Beast):
			ring.append(e)
	for i in ring.size():
		var a := TAU * (float(i) / float(ring.size())) + 0.6
		ring[i].f.teleport(Vector3(sin(a) * 2.5, 0, cos(a) * 2.5))
		ring[i].f.yaw = a + PI
		ring[i].f.mods.strength = 2.4
		ring[i].f.mods.toughness = 2.5
	var lead := float(OS.get_environment("CHAOS_LEAD")) if OS.get_environment("CHAOS_LEAD") != "" else 2.5
	await _steps(int(120 * lead))
	dur = 5.5
	var turn0 := randf() * TAU
	var focus := [_thick()]
	tick_fn = func(_tt: float) -> void:
		focus[0] = (focus[0] as Vector3).lerp(_thick(), 1.2 / 120.0)
	cam_fn = func(tt: float) -> Array:
		var c: Vector3 = focus[0]
		var a := turn0 + tt * 0.16
		var r := lerpf(5.4, 4.6, _ease(tt / dur))
		var eye := c + Vector3(sin(a) * r, lerpf(2.1, 1.7, _ease(tt / dur)), cos(a) * r)
		var flat := Vector2(eye.x, eye.z)
		if flat.length() > 13.5:
			flat = flat.normalized() * 13.5
			eye = Vector3(flat.x, eye.y, flat.y)
		return [eye, c + Vector3(0, 0.05, 0), 46.0, eye.distance_to(c)]

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

## Friends against the troll (BRING YOUR FRIENDS): the champion and three friends, their names
## over their heads as online, abreast across the sand, charge it together; it waits with its plank
## drawn back and, as they come into its reach, sweeps it across in one blow that sends the three in
## front flying (user: they all charge and the troll sweeps all three flying with one blow). Low
## behind the line as it runs, the troll over them in the middle; KEY at the sweep's blow.
func _squad() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false}, "autopilot": true,
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	_emperor(true)   # (his box in the shot: the Emperor in it, user)
	var line := [m.me]
	m.me.f.teleport(Vector3(-3.6, 0, -6.2))
	m.me.f.yaw = 0.0
	var kit := [{"main": "gladius", "off": "scutum", "armor": ["helmet", "manica"]}, {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, {"main": "longsword", "off": "", "armor": ["manica"]}]
	var xs := [-1.3, 0.2, 1.7]
	var friends := []
	for i in 3:
		var al = m.spawn_fighter({"kind": "bot", "name": NAMES[i], "loadout": kit[i], "team": 0, "pos": Vector3(xs[i], 0, -4.8), "yaw": 0.0, "diff": 0.9})
		m._name_tag(al.f, NAMES[i])
		line.append(al)
		friends.append(al.f)
	var spec: Dictionary = m.enemy_spec({"e": "troll", "boss": true}, 0, 1)
	spec.pos = Vector3(-0.4, 0.1, 5.5)
	spec.yaw = PI
	var troll = m.spawn_fighter(spec)
	var tf: Fighter = troll.f
	# It waits, the plank drawn back to its right; then the sweep, across and low, all it has.
	var sweep := [-1.0]
	var sweep_s := float(OS.get_environment("SWEEP_S")) if OS.get_environment("SWEEP_S") != "" else 0.32
	var sweep_y := float(OS.get_environment("SWEEP_Y")) if OS.get_environment("SWEEP_Y") != "" else -0.55
	troll.drive = func(_e):
		var k := -1.0 if sweep[0] < 0.0 else clampf((t - sweep[0]) / sweep_s, 0.0, 1.0)
		var x := 1.7 if k < 0.0 else lerpf(1.7, -1.9, k)
		return {"look": {"yaw": PI, "pitch": 0.0}, "main": {"x": x, "y": sweep_y if k >= 0.0 else 0.4}, "power": k >= 0.0}
	# The charge: all four run at it together, weapons up.
	var charge := func(e): return {"mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.2}}
	for e in line:
		e.drive = charge
	await _steps(20)
	dur = 6.5
	key_tail = 3.4
	var flung := {}
	tick_fn = func(tt: float) -> void:
		if sweep[0] < 0.0:
			var near := 99.0
			for f in friends:
				if is_instance_valid(f):
					near = minf(near, Vector2(f.torso.global_position.x - tf.torso.global_position.x, f.torso.global_position.z - tf.torso.global_position.z).length())
			var at_d := float(OS.get_environment("SWEEP_AT")) if OS.get_environment("SWEEP_AT") != "" else 3.3
			if near < at_d:
				sweep[0] = t
		if OS.get_environment("STAGE_DEBUG") == "1" and int(tt * 120.0) % 12 == 0:
			print("DBG t=%.2f sweep=%.2f flung=%d" % [tt, sweep[0], flung.size()])
	# Struck by the plank, a man is thrown off his feet the way it swept, up and over.
	var on_hit := func(h: Dictionary) -> void:
		if not rolling or h.get("attacker") != tf or not friends.has(h.get("char")) or flung.has(h.get("char")):
			return
		var f: Fighter = h.char
		flung[f] = true
		_key()
		var across := (tf.global_transform.basis * Vector3(-1, 0, 0)).normalized()
		var away: Vector3 = (f.torso.global_position - tf.torso.global_position)
		away.y = 0.0
		away = away.normalized()
		f.fall(3.0, true)
		for p in f.parts:
			if not p.severed:
				p.linear_velocity += across * 6.5 + away * 2.5 + Vector3(0, 4.2, 0)
				p.angular_velocity += away.cross(Vector3.UP) * 4.0
	m.combat.hit.connect(on_hit)
	cam_fn = func(tt: float) -> Array:
		var c := Vector3.ZERO
		var n := 0
		for e in line:
			if is_instance_valid(e.f) and e.f.alive and not flung.has(e.f):
				c += e.f.torso.global_position
				n += 1
		c = c / maxf(1, n) if n > 0 else Vector3(0, 0, 1.5)
		var bp: Vector3 = tf.torso.global_position if is_instance_valid(tf) else Vector3(0, 2.5, 5.5)
		# Low behind the running line, then, as they meet it, held off and a little higher, wide
		# enough for the men flying.
		var u := _ease(tt / 2.2)
		var eye := Vector3(c.x * 0.4, lerpf(0.6, 1.4, u), c.z - lerpf(3.8, 5.6, u))
		var at := Vector3(bp.x * 0.5, lerpf(bp.y + 0.6, bp.y, u), bp.z - 1.0)
		return [eye, at, lerpf(54.0, 60.0, u), eye.distance_to(Vector3(c.x, 1.0, c.z))]

## The champion alone in the middle, his back to us, his axe raised to the stands and the
## Emperor's box; low behind him, going in and up. The end card goes over it.
func _finale() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": CapsArt.AXE, "off": "", "armor": CapsArt.GILT}})
	_emperor(true)
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

## The Emperor in his box over the north stands: in his laurel, a gilded cuirass and his cloak,
## looking down on the sand, his right hand raised when `raise`: on a floor of his own (the box's
## is drawn, not solid), and held there once he stands.
func _emperor(raise := false) -> Fighter:
	# (The box's floor is drawn, not solid: stood on it he sank through to the stands under it and
	# was gone behind its rail, an empty box in the shot, user. A floor of his own under him.)
	var floor_b := StaticBody3D.new()
	floor_b.collision_layer = VoxelPart.LAYER_WORLD
	floor_b.collision_mask = 0
	var fs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(3.0, 0.3, 2.0)
	fs.shape = fbox
	floor_b.add_child(fs)
	m.add_child(floor_b)
	floor_b.global_position = Vector3(0, 3.45, 17.1)
	var spec: Dictionary = m.enemy_spec({"e": "emperor"}, 0, 1)
	spec.team = 3
	spec.loadout = {"main": "", "off": "", "armor": ["hat_laurel", "goldLorica", "cape"]}
	spec.pos = Vector3(0, 3.75, 17.0)
	spec.yaw = PI
	var e = m.spawn_fighter(spec)
	e.erase("bot")
	e.drive = func(_e): return {"look": {"yaw": PI, "pitch": -0.3}, "main": {"x": 0.25, "y": 1.45 if raise else 0.15}, "off": {"x": -0.3, "y": 0.0}}
	var f: Fighter = e.f
	if OS.get_environment("STAGE_DEBUG") == "1":
		print("EMPEROR spawned at %s torso %s alive %s" % [spec.pos, f.torso.global_position, f.alive])
	# (Standing as the game stands him, then held: a body on the box's edge slid off it.)
	await _steps(45)
	if OS.get_environment("STAGE_DEBUG") == "1":
		print("EMPEROR after 45 steps: torso %s head %s alive %s state %s" % [f.torso.global_position, f.head.global_position, f.alive, f.state])
	for p in f.parts:
		p.freeze = true
	for w in f.weapons.values():
		if w:
			w.freeze = true
	return f

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
	_emperor(true)   # (his box in the shot: the Emperor in it, user)
	var hero: Fighter = m.me.f
	hero.mods.strength = float(OS.get_environment("CUT_STR")) if OS.get_environment("CUT_STR") != "" else 4.5
	hero.mods.toughness = 6.0
	hero.teleport(Vector3(-1.6, 0, 0))
	hero.yaw = PI * 0.5
	var foe = m.spawn_fighter({"kind": "bot", "name": "Verus", "loadout": {"main": "gladius", "off": "", "armor": ["helmet"]}, "team": Match.ENEMY_TEAM, "pos": Vector3(5.0, 0, 0), "yaw": -PI * 0.5})
	foe.erase("bot")
	var cut_done := [false]
	# He comes on with his point low and lunges for the champion's belly (user: not the two of them
	# striking at each other's heads); the axe comes down on his sword arm as it goes out.
	var lunge := [false]
	foe.drive = func(_e): return {} if cut_done[0] else {"mz": 1.0, "sprint": OS.get_environment("CUT_RUN") == "1", "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.35, "y": 0.05}, "thrust": 1.0 if lunge[0] else 0.0}
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
			# Raised high over his head, then straight down on the man's sword arm, his left of us.
			var y := 1.65 if k < 0.0 else lerpf(1.65, -0.7, k)
			var cx := float(OS.get_environment("CUT_X")) if OS.get_environment("CUT_X") != "" else -0.3
			return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": cx, "y": y}, "power": k >= 0.0 and k < 1.0, "twist": edge}
		var x := 0.85 if k < 0.0 else lerpf(0.85, -0.95, k)
		return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": x, "y": height}, "power": k >= 0.0 and k < 1.0, "twist": edge}
	await _steps(30)
	dur = 7.0
	key_tail = 2.6
	peek_on_key = true
	tick_fn = func(tt: float) -> void:
		var gap := Vector2(foe.f.torso.global_position.x - hero.torso.global_position.x, foe.f.torso.global_position.z - hero.torso.global_position.z).length() if is_instance_valid(foe.f) else 99.0
		if not lunge[0] and gap < reach + 0.5:
			lunge[0] = true
		if swing_t[0] < 0.0 and gap < reach:
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

## The spear: a man with a sword raised charges the champion across the sand; the champion
## draws his spear back and throws it at him (user: he throws it into the man's head). It takes
## him in the face: the head stops and is driven back while the legs run on under him, and he
## goes over backwards onto his back, dead. The throw is the game's own (wound up, let go, the
## javelin's flight), aimed where the man's head will be when it gets there; the fall is his own
## body's (_over_backwards). KEY at the blow. The camera low and square to the charge, wide
## enough for the throw and the fall.
func _spear() -> void:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": "spear", "off": "", "armor": CapsArt.GILT}})
	_emperor(true)   # (his box in the shot: the Emperor in it, user)
	var hero: Fighter = m.me.f
	hero.mods.strength = 2.0
	hero.mods.toughness = 6.0
	hero.teleport(Vector3(-3.5, 0, 0))
	hero.yaw = PI * 0.5
	var foe = m.spawn_fighter({"kind": "bot", "name": "Crixus", "loadout": {"main": "gladius", "off": "", "armor": []}, "team": Match.ENEMY_TEAM, "pos": Vector3(9.5, 0, float(OS.get_environment("SPEAR_Z")) if OS.get_environment("SPEAR_Z") != "" else 0.2), "yaw": -PI * 0.5})
	foe.erase("bot")
	foe.f.mods.toughness = 4.0
	var struck := [false]
	var phase := ["wait", 0.0]   # wait, wind (F held), thrown
	var throw_at := float(OS.get_environment("SPEAR_AT")) if OS.get_environment("SPEAR_AT") != "" else 7.5
	foe.drive = func(_e):
		if struck[0]:
			return {}
		return {"mz": 1.0, "sprint": true, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.4}}
	# Where his head will be when the spear gets there: the throw leaves the hand a moment after
	# F is let go and flies at about its own speed; led by his run.
	var lead := func() -> Vector3:
		var hp: Vector3 = foe.f.head.global_position
		var v: Vector3 = foe.f.torso.linear_velocity
		v.y = 0.0
		var tt := 0.1
		for k in 3:
			var at: Vector3 = hp + v * tt
			tt = 0.1 + hero.head.global_position.distance_to(at) / 26.0
		return hp + v * tt + Vector3(0, 0.02, 0)
	m.me.drive = func(_e):
		var to: Vector3 = foe.f.head.global_position - hero.head.global_position
		var look := {"yaw": atan2(to.x, to.z), "pitch": 0.0}
		match String(phase[0]):
			"wind":
				return {"look": look, "main": {"x": 0.2, "y": 0.6}, "charging": clampf(float(phase[1]) / 0.7, 0.0, 1.0)}
			"throw":
				phase[0] = "thrown"
				return {"look": look, "main": {"x": 0.2, "y": 0.6}, "throw": true, "throwPower": 1.0, "aimAt": lead.call()}
		return {"look": look, "main": {"x": 0.2, "y": 0.6}}
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
		# (A spear through the head: he is dead as he goes over; not spared, nor left dying.)
		foe.f.head.hp = minf(foe.f.head.hp, 5.0)
		get_tree().create_timer(0.35).timeout.connect(func():
			if is_instance_valid(foe.f) and foe.f.alive:
				foe.f.spared = true
				foe.f.die("spear"))
	m.combat.hit.connect(on_hit)
	tick_fn = func(tt: float) -> void:
		if not is_instance_valid(foe.f):
			return
		var gap := Vector2(foe.f.torso.global_position.x - hero.torso.global_position.x, foe.f.torso.global_position.z - hero.torso.global_position.z).length()
		if phase[0] == "wait" and gap < throw_at + 2.4:
			phase[0] = "wind"
			phase[1] = 0.0
		elif phase[0] == "wind":
			phase[1] = float(phase[1]) + 1.0 / 120.0
			if gap < throw_at and float(phase[1]) > 0.45:
				phase[0] = "throw"
		if OS.get_environment("STAGE_DEBUG") == "1" and int(tt * 120.0) % 6 == 0:
			print("DBG t=%.2f phase=%s gap=%.2f foe=%s" % [tt, phase[0], gap, foe.f.state])
	cam_fn = func(tt: float) -> Array:
		var pf: Vector3 = foe.f.torso.global_position if is_instance_valid(foe.f) else Vector3.ZERO
		var mid := hero.torso.global_position.lerp(pf, 0.5)
		var eye := Vector3(mid.x, 0.85, mid.z - 6.4)
		return [eye, mid + Vector3(0, 0.45, 0), 46.0, eye.distance_to(mid)]

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
