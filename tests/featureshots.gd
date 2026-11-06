extends Node
## The feature trailer's scenes (`-- --probe featureshots`, needs a display; run through
## tools/make_feature_trailer.py, which records each with the movie maker at 120 frames a
## second). Each scene shows one thing the game does, and nothing in it is left to chance: the
## men stand where they are put, every blow is scripted mark by mark the way a player's mouse
## drives it, and lands where the plan says (user: the old trailer was bots fighting it out,
## hugging, blows into the air, a lion scene where nothing happened). No mind of its own anywhere:
## no man is a bot, a beast runs where the scene sends it and bites when the scene lets it.
##
## A scripted blow is the game's own: the champion's hand marks drawn back and thrown across as a
## player throws them, the blade swung by his arm, the blow worked out by Combat from the blade's
## own speed where it meets the part. Where the blade passes within a couple of centimetres of
## the part without touching it, the contact is put there (the cut then runs where the blade
## went, as seen).
##
## SCENE picks the scene:
## - gate: the champion in the dark of the gate, walking out into the light and the roar;
## - crowd: the stands on their feet, the Emperor in his box raising his hand;
## - swing: EVERY SWING IS YOURS: four swings at a man with a shield, each where the mouse goes
##   (MARK tags: the mouse's path, drawn over the scene by the editor);
## - cut: STEEL CUTS WHERE IT LANDS: an axe through a raised arm, in the slowest motion;
## - armour: a hammer on a steel cuirass, plates knocked off blow by blow, the last one through;
## - bones: a mace on one shin, then the other: he is down, and fights on from the sand;
## - lion: a lion takes a man down;
## - troll: three men charge a troll, one sweep of its plank throws them all;
## - dragon: the dragon's fire across the sand, a man running from it;
## - pots: fire, poison and thunder pots among a band of men;
## - blade: a man with a blade for a forearm, the physician's, fighting with it;
## - friends: four friends, their names over their heads, their blows into the minotaur at once;
## - hydra: the hydra's last head coming down at the champion, onto his blade (the climax);
## - finale: the champion alone in the middle, his axe raised to the crowd (under the title).
##
## Tags (stdout, and TAG_LOG when set): REC_START <frame> as the scene starts, KEY <frame> at its
## moment, HIT <frame> <J>, MARK <frame> <x> <y> <power> (swing), REC_END <frame>. Nothing 3D is
## drawn before REC_START. SCENE_PEEK=n: no movie, n frames saved to SHOT_DIR (peek_<scene>_<k>.png)
## through the scene, or round its KEY for those that have one (a check of the framing).

const CapsArt := preload("res://tests/capsuleart.gd")
const BLADE_GAP := 0.035     # (m) a blade passing this close to the part it was swung at meets it
const BLADE_REACH := 0.12    # (m) ... and one that went by it no further off, where it came closest
# The champion's gilded kit: the capsules' (CapsArt.GILT) but for the manica (his sword arm, before
# the camera in every scene, was a grey drainpipe).
const GILT := ["goldHelmet", "goldLorica", "greaves", "cape"]

var menu
var m
var rec0 := 0
var rolling := false
var t := 0.0              # seconds since REC_START
var dur := 6.0
var cam_fn: Callable      # t -> [eye, at, fov, focus distance (0: none), roll (radians; optional)]
var tick_fn: Callable     # t -> void, every physics step while rolling
var attrs: CameraAttributesPractical
var keyed := false
var key_tail := -1.0      # > 0: the scene ends this long after its KEY
var key_by := -1.0        # > 0: its KEY at this time at the latest (its moment, however it went)
var peek_on_key := false
var peek_at := []
var scene := ""
var marks_on := false     # MARK tags of the champion's hand marks (swing)
# The player's own view (POV=1): the scene as it is played, through the game's own camera behind
# the champion with its HUD over it, not the film camera (user: parts that are really gameplay,
# from the player's eyes). The same scene, the same blows.
var pov := false
var pov_sub := ""         # the HUD's line under THE ARENA (the bout and the foe)
var hero_inp := {}        # the champion's input this step (scripted)

func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	scene = OS.get_environment("SCENE")
	pov = OS.get_environment("POV") == "1"
	if OS.get_environment("SCENE_PEEK") != "" or OS.get_environment("SCENE_PEEK_AT") != "":
		RenderingServer.render_loop_enabled = false
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	seed(int(OS.get_environment("SCENE_SEED")) if OS.get_environment("SCENE_SEED") != "" else 11)
	match scene:
		"gate":
			await _gate()
		"crowd":
			await _crowd()
		"swing":
			await _swing_scene()
		"cut":
			await _cut()
		"armour":
			await _armour()
		"bones":
			await _bones()
		"lion":
			await _lion()
		"troll":
			await _troll()
		"dragon":
			await _dragon()
		"pots":
			await _pots()
		"blade":
			await _blade()
		"friends":
			await _friends()
		"hydra":
			await _hydra()
		"finale":
			await _finale()
		_:
			print("SCENE: gate, crowd, swing, cut, armour, bones, lion, troll, dragon, pots, blade, friends, hydra, finale")
			get_tree().quit(1)
			return
	if OS.get_environment("SCENE_SECONDS") != "":
		dur = float(OS.get_environment("SCENE_SECONDS"))
	var peek := int(OS.get_environment("SCENE_PEEK")) if OS.get_environment("SCENE_PEEK") != "" else 0
	if OS.get_environment("SCENE_PEEK_AT") != "":
		peek_at = []
		for v in OS.get_environment("SCENE_PEEK_AT").split(",", false):
			peek_at.append(float(v))
		peek = peek_at.size()
		peek_on_key = false
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
		if key_by > 0.0 and t >= key_by and not keyed:
			_key()
		_pov_sync()
		if marks_on and hero_inp.has("main"):
			var mk: Dictionary = hero_inp.main
			_tag("MARK %d %.3f %.3f %d" % [_frame(), float(mk.get("x", 0.0)), float(mk.get("y", 0.0)), 1 if hero_inp.get("power", false) else 0])
			if pad:
				pad.push(Vector2(float(mk.get("x", 0.0)), float(mk.get("y", 0.0))), bool(hero_inp.get("power", false)), t)
		if peek > 0 and peeked < peek:
			# The frame is drawn for a few frames before the one saved (the light and the eye's
			# exposure take a while to come back after frames undrawn), the scene going on as it
			# does: held still for them, the game's clock (its physics frames) ran on while its
			# bodies stood, and the scene went another way than it does in the movie.
			var at_t: float = float(peek_at[peeked]) if peeked < peek_at.size() else (dur * (float(peeked) + 0.5) / float(maxi(1, peek)) if peek_at.is_empty() and not peek_on_key else INF)
			var warm := (int(OS.get_environment("SCENE_PEEK_WARM")) if OS.get_environment("SCENE_PEEK_WARM") != "" else 16) / 120.0
			if t >= at_t - warm and get_viewport().disable_3d:
				get_viewport().disable_3d = false
				RenderingServer.render_loop_enabled = true
			if t >= at_t:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("peek_%s_%d.png" % [scene, peeked]))
				peeked += 1
				var next_t: float = float(peek_at[peeked]) if peeked < peek_at.size() else INF
				if next_t - warm > t + 1.0 / 120.0:
					get_viewport().disable_3d = true
					RenderingServer.render_loop_enabled = false
	_tag("REC_END %d" % _frame())
	get_tree().quit()

## The match a scene is staged in: the game's own picture at its best, its music off (the trailer
## lays its own score over the game's sound), no HUD, the camera ours, no kill camera.
func _start(o: Dictionary) -> void:
	o.merge({"decrees": [], "hazards": [], "seed": 5}, false)
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = pov
	m.cam.set_process(false)
	if m.killcam:
		m.killcam.queue_free()
		m.killcam = null
	_best_picture()
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
		_pov_sync()

## The player's view: the game's camera turns with the champion's look, as the player's mouse turns
## it (from the setting up on, or it swung round to him as the scene began).
func _pov_sync() -> void:
	if pov and m and m.input and hero_inp.has("look"):
		var lk: Dictionary = hero_inp.look
		m.input.look_yaw = float(lk.get("yaw", 0.0))
		m.input.look_pitch = float(lk.get("pitch", 0.0))
		m.input.free_look = Vector2.ZERO
		m.last_local_inp = hero_inp

func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

func _key() -> void:
	if not keyed and rolling:
		keyed = true
		_tag("KEY %d" % _frame())
		if key_tail > 0.0:
			dur = minf(dur, t + key_tail)
		if peek_on_key:
			peek_at = [t + 0.02, t + 0.25, t + 0.6, t + 1.2]

func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if OS.get_environment("SCENE_DEBUG") == "1" and J >= 10.0:
		print("HITDBG t=%.2f J=%.0f %s by %s" % [t, J, String(h.part.name) if h.get("part") is Node else "-", String(h.attacker.name) if h.get("attacker") is Node else "-"])
	if rolling and J >= 20.0:
		# HIT <frame> <J> <the part struck> <limbs it took off> <the blow's kind> <by the champion: 1>
		# <plates it knocked off>
		var res: Dictionary = h.get("res", {}) if h.get("res") is Dictionary else {}
		var pt = h.get("part")
		_tag("HIT %d %d %s %d %s %d %d" % [_frame(), int(J), String(pt.name) if pt is Node else "-", (res.get("severed", []) as Array).size(), str(h.get("type", "-")), 1 if m and m.me and h.get("attacker") == m.me.f else 0, int(res.get("armor_hit", 0))])

## A camera's aim that follows `p` smoothly (a moving part jolted the picture about): `s` holds
## it from frame to frame (an array of the camera's own), `k` how much of the way it closes in a
## frame.
static func _follow(s: Array, p: Vector3, k := 0.08) -> Vector3:
	if s.is_empty():
		s.append(p)
	else:
		s[0] = (s[0] as Vector3).lerp(p, k)
	return s[0]

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _process(_dt: float) -> void:
	if pov and m != null and menu.hud:
		# A bout in the arena, not the training ground the scene is staged in.
		menu.hud.place_label.text = "THE ARENA"
		menu.hud.place_sub.text = pov_sub
		return
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
	if c.size() > 4 and absf(float(c[4])) > 1e-4:
		cam.rotate_object_local(Vector3(0, 0, 1), float(c[4]))   # (a Dutch angle)
	cam.reset_physics_interpolation()
	var focus := float(c[3]) if c.size() > 3 else 0.0
	if attrs and focus > 0.0:
		# A long lens: what is far beyond the subject melts away.
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus + 2.0
		attrs.dof_blur_far_transition = 6.0
		attrs.dof_blur_near_enabled = false
		attrs.dof_blur_amount = 0.06
		cam.attributes = attrs
	else:
		cam.attributes = null

# ---------- the mouse, drawn over the swing ----------

## The mouse's path, in the corner of the picture (the swing scene): a dark pad with a gold rim,
## the mark where the mouse is and its trail behind it, bright while the button is down (a blow
## being thrown), dim while it is only moved; a mouse under it with its button lit with it. Drawn
## by the game into the movie, frame by frame with the swing it drives.
class MousePad extends Control:
	var trail: Array = []      # [Vector2 mark, bool power, float t]
	var now_t := 0.0
	func push(mk: Vector2, power: bool, tt: float) -> void:
		now_t = tt
		trail.append([mk, power, tt])
		while trail.size() > 0 and tt - float(trail[0][2]) > 0.55:
			trail.pop_front()
		queue_redraw()
	func _pad_point(mk: Vector2, c: Vector2, r: float) -> Vector2:
		return c + Vector2(clampf(mk.x / 1.2, -1.0, 1.0), -clampf((mk.y - 0.1) / 1.6, -1.0, 1.0)) * r
	func _draw() -> void:
		var vs: Vector2 = get_viewport_rect().size
		var k: float = vs.y / 1080.0
		var side := 250.0 * k
		var org := Vector2(vs.x - side - 70.0 * k, vs.y - side - 150.0 * k)
		var gold := Color(0.93, 0.76, 0.38)
		draw_rect(Rect2(org, Vector2(side, side)), Color(0.05, 0.035, 0.02, 0.62), true)
		draw_rect(Rect2(org, Vector2(side, side)), Color(gold.r, gold.g, gold.b, 0.85), false, 2.0 * k)
		var c := org + Vector2(side, side) * 0.5
		var r := side * 0.4
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.12), 1.0 * k)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.12), 1.0 * k)
		for i in range(1, trail.size()):
			var a: Array = trail[i - 1]
			var b: Array = trail[i]
			var age := clampf((now_t - float(b[2])) / 0.55, 0.0, 1.0)
			var col := Color(1.0, 0.85, 0.45, (1.0 - age) * 0.95) if bool(b[1]) else Color(0.85, 0.8, 0.7, (1.0 - age) * 0.45)
			draw_line(_pad_point(a[0], c, r), _pad_point(b[0], c, r), col, (6.0 if bool(b[1]) else 3.0) * k * (1.0 - 0.6 * age), true)
		var down := false
		if trail.size() > 0:
			var last: Array = trail.back()
			down = bool(last[1])
			var pnt := _pad_point(last[0], c, r)
			draw_circle(pnt, 9.0 * k, Color(1.0, 0.92, 0.7, 1.0) if down else Color(0.9, 0.86, 0.8, 0.85))
			draw_arc(pnt, 13.0 * k, 0.0, TAU, 24, Color(gold.r, gold.g, gold.b, 0.9), 2.0 * k, true)
		# The mouse under the pad, its button lit while a blow is thrown.
		var mo := org + Vector2(side * 0.5 - 26.0 * k, side + 26.0 * k)
		draw_rect(Rect2(mo, Vector2(52.0 * k, 78.0 * k)), Color(0.05, 0.035, 0.02, 0.62), true)
		draw_rect(Rect2(mo, Vector2(52.0 * k, 78.0 * k)), Color(gold.r, gold.g, gold.b, 0.85), false, 2.0 * k)
		draw_rect(Rect2(mo + Vector2(3.0 * k, 3.0 * k), Vector2(22.0 * k, 30.0 * k)), Color(1.0, 0.8, 0.35, 0.95) if down else Color(1, 1, 1, 0.08), true)
		draw_line(mo + Vector2(26.0 * k, 0), mo + Vector2(26.0 * k, 34.0 * k), Color(gold.r, gold.g, gold.b, 0.7), 1.5 * k)

var pad: MousePad = null

# ---------- the cast ----------

## A man of the foe's (or `team`'s) at `pos`, facing `yaw`, doing only what `drive` says (no mind
## of his own): an entity.
func _man(name_: String, loadout: Dictionary, pos: Vector3, yaw: float, team := Match.ENEMY_TEAM):
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": loadout, "team": team, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e

## The champion: gilded, `main` in his hand, strong and hard to bring down (it is his trailer).
func _champion(main, pos: Vector3, yaw: float, off := "") -> Fighter:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": main, "off": off, "armor": GILT}})
	var hero: Fighter = m.me.f
	hero.mods.strength = 2.2
	hero.mods.toughness = 6.0
	hero.teleport(pos)
	hero.yaw = yaw
	hero_inp = {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.2, "y": 0.3}}
	m.me.drive = func(_e): return hero_inp
	return hero

## The Emperor in his box over the north stands, in his laurel and gilded cuirass, his right hand
## raised when `raise`: on a floor of his own (the box's is drawn, not solid) and held there.
func _emperor(raise := false) -> Fighter:
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
	var up := [raise]
	e.drive = func(_e): return {"look": {"yaw": PI, "pitch": -0.3}, "main": {"x": 0.25, "y": 1.45 if up[0] else 0.15}, "off": {"x": -0.3, "y": 0.0}}
	var f: Fighter = e.f
	await _steps(45)
	for p in f.parts:
		p.freeze = true
	for w in f.weapons.values():
		if w:
			w.freeze = true
	return f

# ---------- the scripted blow ----------

## The blade of `w` at its nearest to `p`'s box: [gap (m), the point on the blade, the shape of
## the weapon that point is in]. Only the part of it that does the work: its edge or its point if
## it has one (else the axe met him with its haft, and a chop through an arm was a bruise), its
## head if it is a club or a hammer, never its grip.
func _blade_near(w: Weapon, p: VoxelPart, thrust := false) -> Array:
	var inv: Transform3D = p.global_transform.affine_inverse()
	var he: Vector3 = p.half_ext
	# [gap, point, shape] of the working part (the edge for a cut, the point for a thrust) and of
	# any part but the grip (a club's head, a mace's studs: the fallback when it has no edge).
	var want := [INF, Vector3.ZERO, -1]
	var any := [INF, Vector3.ZERO, -1]
	var idx := 0
	# (By the body's own shape index, owner by owner: the one Combat reads the box's edge from.)
	for oid in w.get_shape_owners():
		var node = w.shape_owner_get_owner(oid)
		for j in w.shape_owner_get_shape_count(oid):
			if node is CollisionShape3D and not node.disabled:
				var box: Dictionary = node.get_meta("box", {})
				var typ := String(box.get("type", "blunt"))
				if typ != "grip":
					var sh := node as CollisionShape3D
					var c: Vector3 = sh.global_position
					var bs: Vector3 = (sh.shape as BoxShape3D).size * 0.5 if sh.shape is BoxShape3D else Vector3.ONE * w.vs * 0.5
					var lp: Vector3 = inv * c
					var gap := Vector3(maxf(absf(lp.x) - he.x, 0.0), maxf(absf(lp.y) - he.y, 0.0), maxf(absf(lp.z) - he.z, 0.0)).length() - bs.length() * 0.6
					if gap < float(any[0]):
						any = [gap, c, idx]
					# (A cut lands with the edge, a thrust with the point: the leg sweep landed point
					# first, and the axe's chop with its haft.)
					if typ == ("point" if thrust else "edge") and gap < float(want[0]):
						want = [gap, c, idx]
			idx += 1
	var r: Array = want if int(want[2]) >= 0 else any
	return [maxf(0.0, float(r[0])), r[1], r[2]]

## `w` passes through `f` for the rest of the scene but where a scripted blow lands (_blow_at):
## drawn back through him for the next chop, the axe's haft knocked his arm about.
func _ghost(w: Weapon, f) -> void:
	for q in f.parts:
		if is_instance_valid(q):
			w.add_collision_exception_with(q)
	# (And through what he holds: the axe coming down on his raised arm met his sword first and
	# knocked it out of his hand, the arm came down, and the next chop went by it.)
	if f is Fighter:
		for side in ["L", "R"]:
			var o = f.weapons[side]
			if o and is_instance_valid(o) and o != w:
				w.add_collision_exception_with(o)

## `a` and `b` pass through each other, body and body (not their weapons): only the blows the
## scene scripts land between them (an empty hand thrown out for balance, an elbow in a wind-up,
## knocked his arm unplanned).
func _apart(a: Fighter, b: Fighter) -> void:
	for p in a.parts:
		for q in b.parts:
			if is_instance_valid(p) and is_instance_valid(q):
				p.add_collision_exception_with(q)

## Watches `w` swung at `p` until `until` (scene seconds) and lands the blow where it goes by:
## where the working part of the blade comes within BLADE_GAP of the part, the contact is made
## there (once), and Combat works out the blow from the blade's own speed. `clear`: the blade
## passes through the rest of the man for the length of the stroke (his hand, his forearm, a
## shoulder in the way of the blow at his knee or his chest: met first, they took it). Calls
## `done` with the hit when it lands. `min_speed` (m/s): not before the blade is going this fast
## (a backhand starting close to the man met him as it set off, and the blow was a touch).
func _blow_at(w: Weapon, p: VoxelPart, until: float, done := Callable(), clear := true, thrust := false, min_speed := 3.0) -> void:
	var landed := [false]
	var fo = p.fighter
	var on_hit := func(h: Dictionary) -> void:
		# (The blade's own: his forearm knocking the head as it came down at him was taken for it.)
		if landed[0] or h.get("char") != fo or h.get("attacker") != w.holder or h.get("weapon") != w:
			return
		landed[0] = true
		if done.is_valid():
			done.call(h)
	m.combat.hit.connect(on_hit)
	var passed := []
	if clear and fo:
		for q in fo.parts:
			if is_instance_valid(q) and not w.get_collision_exceptions().has(q):
				w.add_collision_exception_with(q)
				passed.append(q)
	var made := false
	# The closest the blade has come so far, going fast enough: [gap, near]. A man a few
	# centimetres from where he stood in the plan (a run drawn frame by frame does not go quite
	# as one not drawn) is still met: once the blade has come within BLADE_REACH of the part and
	# is drawing away from it again, the blow is made where it came closest.
	var best := [INF, []]
	while t < until and not landed[0]:
		await get_tree().physics_frame
		if not is_instance_valid(w) or not is_instance_valid(p) or p.severed:
			break
		var near: Array = _blade_near(w, p, thrust)
		if int(near[2]) < 0:
			break
		var speed: float = w.linear_velocity.length() + w.angular_velocity.length() * 0.5
		if OS.get_environment("SCENE_DEBUG") == "1":
			var hero: Fighter = w.holder if w.holder else null
			print("BLOW t=%.2f %s gap %.3f speed %.1f; part at %s, hand at %s" % [t, p.part_name, float(near[0]), speed, str(p.global_position.snapped(Vector3.ONE * 0.01)), str(hero.hand_world("R").snapped(Vector3.ONE * 0.01)) if hero else "-"])
		if made:
			continue
		var at: Array = []
		if float(near[0]) <= BLADE_GAP and speed > min_speed:
			at = near
		elif speed > min_speed and float(near[0]) < float(best[0]):
			best = [float(near[0]), near]
		elif float(best[0]) <= BLADE_REACH and float(near[0]) > float(best[0]) + 0.01:
			at = best[1]
		if not at.is_empty():
			made = true
			if OS.get_environment("SCENE_DEBUG") == "1":
				print("INJECT t=%.2f on %s (gap %.3f, speed %.1f)" % [t, p.part_name, float(at[0]), speed])
			m.combat.pending.append({"a": w, "b": p, "sa": int(at[2]), "sb": 0, "p": at[1], "J": 0.0})
	await get_tree().physics_frame
	if m.combat.hit.is_connected(on_hit):
		m.combat.hit.disconnect(on_hit)
	# The man is solid to the blade again a moment after (not while it is still in him).
	await get_tree().create_timer(0.25, false).timeout
	for q in passed:
		if is_instance_valid(q) and is_instance_valid(w):
			w.remove_collision_exception_with(q)

# ---------- the scenes ----------

## The gate: the champion in the dark of the west gate, walking out of it onto the sand into the
## light and the noise, at us; the camera before him, low, backing away as he comes and rising
## with him, the dark of the gate behind him (from behind him in the gate, the camera was in the
## wall: three seconds of dark red).
func _gate() -> void:
	var hero := _champion(CapsArt.AXE, Vector3(-14.2, 0, 0.0), PI * 0.5)
	hero_inp = {"mz": 0.0, "look": {"yaw": PI * 0.5, "pitch": 0.1}, "main": {"x": 0.3, "y": 0.45}}
	_emperor(true)
	await _steps(60)
	dur = 6.5
	tick_fn = func(tt: float) -> void:
		hero_inp["mz"] = 0.0 if tt < 0.6 else 0.75
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = _follow(fol, hero.torso.global_position, 0.1)
		var u := _ease(tt / dur)
		var eye := Vector3(h.x + lerpf(4.6, 3.6, u), lerpf(0.45, 1.2, u), h.z + lerpf(1.3, 0.9, u))
		var at := h + Vector3(0, lerpf(0.05, 0.25, u), 0)
		return [eye, at, lerpf(42.0, 48.0, u), eye.distance_to(h)]

## The crowd: low on the sand under the Emperor's box, a slow crane up the wall to him as he rises
## and raises his hand, the stands on their feet round him.
func _crowd() -> void:
	_champion(CapsArt.AXE, Vector3(0, 0, -6.0), 0.0)
	await _emperor(true)
	await _steps(30)
	dur = 5.0
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var eye := Vector3(lerpf(-2.6, 1.8, u), lerpf(0.5, 2.6, u), lerpf(9.4, 11.6, u))
		var at := Vector3(lerpf(-0.6, 0.0, u), lerpf(3.0, 4.6, u), 17.0)
		return [eye, at, lerpf(44.0, 34.0, u), eye.distance_to(at)]

## EVERY SWING IS YOURS: the champion and a man with a big shield, face to face. Four swings,
## each where the mouse goes: a cut down from his right onto the shield, a sweep low from his
## left at the legs (the shield drops to it), the sword up over his head and down on the shield's
## rim, which splits, then the point driven in under it. The mouse's path is tagged (MARK) for the
## editor to draw over the scene. The camera side on, a little behind the champion, going round.
func _swing_scene() -> void:
	var hero := _champion("longsword", Vector3(-1.05, 0, 0.0), PI * 0.5)
	marks_on = true
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	pad = MousePad.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pad)
	var foe = _man("Gannicus", {"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]}, Vector3(0.95, 0, 0.0), -PI * 0.5)
	var ff: Fighter = foe.f
	ff.mods.toughness = 3.0
	# His shield where the blow comes: his off hand's mark (in his own frame, his left -x).
	var guard := [{"x": -0.2, "y": 0.35}]
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.95, "y": 0.45}, "off": guard[0]}
	await _steps(90)
	dur = 6.2
	pov_sub = "BOUT 2 · GANNICUS"
	key_by = 4.90   # (its moment at the latest)
	peek_on_key = false
	var w: Weapon = hero.weapons.R
	# The plan: [start, secs, from, to, thrust, the part struck at, where his shield goes].
	var strokes := [
		[0.55, 0.30, Vector2(0.95, 1.05), Vector2(-0.85, -0.35), 0.0, "torso", {"x": -0.05, "y": 0.6}],
		[1.85, 0.30, Vector2(-0.95, 0.05), Vector2(0.9, -0.75), 0.0, "thighL", {"x": 0.2, "y": -0.45}],
		[3.15, 0.34, Vector2(-0.15, 1.55), Vector2(-0.2, -0.7), 0.0, "head", {"x": 0.0, "y": 0.9}],
		[4.55, 0.24, Vector2(0.15, 0.25), Vector2(0.05, 0.1), 1.0, "torso", {"x": -0.05, "y": 0.95}],
	]
	tick_fn = func(tt: float) -> void:
		var look_yaw := PI * 0.5
		var mk := Vector2(0.2, 0.3)
		var power := false
		var thrust := 0.0
		for k in strokes.size():
			var s: Array = strokes[k]
			var st := float(s[0])
			var nxt: float = float(strokes[k + 1][0]) if k + 1 < strokes.size() else 99.0
			if tt >= st - 0.45 and tt < nxt - 0.45:
				# Drawn back to the start of the stroke, then thrown across.
				if tt < st:
					mk = (s[2] as Vector2)
				else:
					var u := clampf((tt - st) / float(s[1]), 0.0, 1.0)
					u = u * u * (3.0 - 2.0 * u)
					mk = (s[2] as Vector2).lerp(s[3] as Vector2, u)
					power = tt < st + float(s[1]) + 0.1
					thrust = float(s[4]) if tt < st + float(s[1]) + 0.25 else 0.0
				# His shield goes where this blow is coming, a moment before it does.
				if tt >= st - 0.3:
					guard[0] = s[6]
		hero_inp = {"look": {"yaw": look_yaw, "pitch": 0.0}, "main": {"x": mk.x, "y": mk.y}, "power": power, "thrust": thrust}
		if thrust > 0.0:
			hero_inp["aimAt"] = ff.torso.global_position + Vector3(0, -0.05, 0)
	# Each stroke watched for its blow (the last one, the thrust, is the scene's moment).
	for k in strokes.size():
		var s: Array = strokes[k]
		var part_name: String = s[5]
		_watch_stroke(w, ff, part_name, float(s[0]), float(s[0]) + float(s[1]) + 0.2, k == strokes.size() - 1)
	cam_fn = func(tt: float) -> Array:
		var a := lerpf(-0.55, -0.15, _ease(tt / dur))
		var mid := Vector3(-0.05, 1.05, 0.0)
		var r := 3.3
		var eye := mid + Vector3(sin(a) * r - 0.4, 0.15, -cos(a) * r)
		return [eye, mid + Vector3(0, -0.1, 0), 42.0, eye.distance_to(mid)]

## A stroke of the swing scene watched from its start: the blade's blow on the man, wherever on
## him it meets (his shield takes most), and the last one the scene's moment.
func _watch_stroke(w: Weapon, ff: Fighter, part_name: String, from_t: float, to_t: float, last: bool) -> void:
	while t < from_t:
		await get_tree().physics_frame
	var p: VoxelPart = ff.by_name.get(part_name, ff.torso)
	await _blow_at(w, p, to_t, func(_h): if last: _key(), true, last)

## STEEL CUTS WHERE IT LANDS: a swordsman comes in with his sword raised over his head to strike;
## the champion, the executioner's axe drawn up high, brings it down across the man's upper arm as
## it comes forward: the arm is cut through where the edge goes, and falls. The camera low and
## close beside them; the editor plays it in the slowest motion.
func _cut() -> void:
	var hero := _champion("executionerAxe", Vector3(-0.95, 0, 0.0), PI * 0.5)
	hero.mods.strength = 3.0
	var foe = _man("Verus", {"main": "gladius", "off": "", "armor": ["helmet"]}, Vector3(0.75, 0, 0.1), -PI * 0.5)
	var ff: Fighter = foe.f
	# (As hard as any man: made three times as hard to keep him standing, the edge went a third
	# of the way into his arm and stopped.)
	ff.mods.toughness = 0.8
	var raise := [0.0]
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": lerpf(0.4, 0.25, raise[0]), "y": lerpf(0.2, 1.35, raise[0])}, "mz": 0.0}
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.05, "y": 0.4}}
	var w: Weapon = hero.weapons.R
	# (From the start: settling into their places, the axe knocked his arm about before the scene.)
	_ghost(w, ff)
	await _steps(90)
	dur = 5.0
	pov_sub = "BOUT 3 · VERUS"
	key_by = 3.80   # (its moment at the latest)
	key_tail = 2.4
	peek_on_key = true
	# Chop after chop into the same wound: one blow goes only a share of the way through a limb (a
	# third, a half), the next carries on in the slot it left, and the forearm comes off. The
	# scene's moment is the one that takes it off.
	var chops := [1.5, 2.45, 3.4]
	var off := [false]
	var arm: VoxelPart = ff.by_name.forearmR
	tick_fn = func(tt: float) -> void:
		# The moment is the arm coming off, whichever blow does it (a forearm cut most of the way
		# through can tear away under its own weight before the next chop).
		if not off[0] and is_instance_valid(arm) and arm.severed:
			off[0] = true
			_key()
		# He raises his sword to strike; the axe goes up over the champion's head as he does.
		raise[0] = _ease((tt - 0.4) / 0.9)
		var mk := Vector2(lerpf(0.05, -0.1, _ease((tt - 0.5) / 0.8)), lerpf(0.4, 1.6, _ease((tt - 0.5) / 0.8)))
		var power := false
		for c in chops:
			var ct: float = c
			if off[0] and tt > ct:
				continue
			if tt >= ct - 0.55 and tt < ct:
				# Back up over his head for the next.
				mk = Vector2(-0.35, -0.7).lerp(Vector2(-0.1, 1.6), _ease((tt - (ct - 0.55)) / 0.4)) if ct > chops[0] else Vector2(-0.1, 1.6)
			elif tt >= ct and tt < ct + 0.4:
				mk = Vector2(-0.1, 1.6).lerp(Vector2(-0.35, -0.7), _ease((tt - ct) / 0.22))
				power = tt < ct + 0.35
		if off[0] and tt > 0.0:
			power = false
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": mk.x, "y": mk.y}, "power": power}
	for c in chops:
		var ct: float = c
		var f := func():
			while t < ct:
				await get_tree().physics_frame
			if off[0]:
				return
			await _blow_at(w, arm, ct + 0.4, func(h):
				var res: Dictionary = h.get("res", {}) if h.get("res") is Dictionary else {}
				if not (res.get("severed", []) as Array).is_empty():
					off[0] = true
					_key()
				elif ct == float(chops.back()):
					_key())
		f.call()
	# Low, three-quarters from behind his sword arm, tilted: the axe comes down at us onto the arm,
	# both men whole in the frame (user: every man in every scene seen whole).
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
		var u := _ease(tt / dur)
		var eye := mid + Vector3(lerpf(1.5, 1.3, u), lerpf(-0.5, -0.4, u), lerpf(-2.9, -2.6, u))
		return [eye, mid + Vector3(-0.1, 0.1, 0), 46.0, eye.distance_to(mid), 0.07]

## ARMOUR: a man in a steel cuirass and helmet stands his ground, his sword drawn back; the
## champion's warhammer comes down on his chest, again and again: each blow knocks plates off it,
## flying, the cuirass opened up, until the last goes through. The camera before him, a little to
## his left, on his chest (from behind him, it was his back and his sword arm that we saw).
func _armour() -> void:
	var hero := _champion("warhammer", Vector3(-1.0, 0, 0.0), PI * 0.5)
	hero.mods.strength = 2.0
	var foe = _man("Tetraites", {"main": "gladius", "off": "", "armor": ["helmet", "steelLorica"]}, Vector3(0.35, 0, 0.0), -PI * 0.5)
	var ff: Fighter = foe.f
	ff.mods.toughness = 1.5
	# He stands his ground under it (thrown back by the first blow, the rest fell on the air).
	ff.mods.unstoppable = true
	ff.mods.footing = 4.0
	# (His sword drawn back high to strike, his other hand low and wide: the chest open to the
	# hammer. With his hands before him, it was his arms the hammer met.)
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.95, "y": 1.2}, "off": {"x": -0.95, "y": -0.6}}
	var w: Weapon = hero.weapons.R
	_ghost(w, ff)
	await _steps(90)
	dur = 6.0
	pov_sub = "BOUT 4 · TETRAITES"
	key_by = 4.40   # (its moment at the latest)
	var blows := [0.6, 1.7, 2.8, 3.9]
	tick_fn = func(tt: float) -> void:
		var mk := Vector2(0.75, 1.0)
		var power := false
		for k in blows.size():
			var st: float = blows[k]
			if tt >= st - 0.5 and tt < st + 0.6:
				if tt < st:
					mk = Vector2(0.8, 1.15) if k % 2 == 0 else Vector2(-0.8, 1.1)
				else:
					var u := _ease((tt - st) / 0.26)
					mk = (Vector2(0.8, 1.15) if k % 2 == 0 else Vector2(-0.8, 1.1)).lerp(Vector2(-0.6, -0.2) if k % 2 == 0 else Vector2(0.6, -0.25), u)
					power = tt < st + 0.36
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": mk.x, "y": mk.y}, "power": power}
	for k in blows.size():
		var st: float = blows[k]
		var last: bool = k == blows.size() - 1
		var f := func():
			while t < st:
				await get_tree().physics_frame
			await _blow_at(w, ff.torso, st + 0.4, func(_h): if last: _key())
		f.call()
	# Round him as the blows come, from his side to his front, rising.
	cam_fn = func(tt: float) -> Array:
		var c: Vector3 = ff.torso.global_position
		var u := _ease(tt / dur)
		var th := lerpf(1.4, 0.9, u)
		var r := lerpf(3.1, 2.7, u)
		var eye := c + Vector3(-cos(th) * r, lerpf(-0.25, 0.1, u), sin(th) * r)
		return [eye, c + Vector3(-0.45, -0.1, 0), 44.0, eye.distance_to(c)]

## BONES BREAK. MEN FIGHT ON.: a man comes on, his sword drawn back; the champion's mace takes
## him low on the right shin, then back across on the left: both bones go, his legs fold under
## him and he is down on the sand. And from there he fights on, his sword swung up at the
## champion over him: the game's own (a man whose legs are broken fights from where he lies; with
## one good leg he hops, and stood up again). Low and side on, then in on him on the sand. KEY as
## the second shin goes.
func _bones() -> void:
	var hero := _champion("mace", Vector3(-1.0, 0, 0.0), PI * 0.5)
	hero.mods.strength = 2.6
	var foe = _man("Priscus", {"main": "gladius", "off": "", "armor": ["helmet"]}, Vector3(0.15, 0, 0.0), -PI * 0.5)
	var ff: Fighter = foe.f
	ff.mods.toughness = 1.5
	var since := [-1.0]   # (scene seconds) since when he fights from the sand
	foe.drive = func(_e):
		if since[0] < 0.0:
			# His sword up over his head to strike, the other hand low (drawn back to his right,
			# the champion's arm met it in his wind-up).
			return {"look": {"yaw": -PI * 0.5, "pitch": 0.1}, "main": {"x": 0.25, "y": 1.5}, "off": {"x": -0.45, "y": 0.0}}
		# From the sand: up at the champion over him, again and again.
		var s := 0.5 + 0.5 * sin((t - since[0]) * 4.2 - PI * 0.5)
		return {"look": {"yaw": -PI * 0.5, "pitch": 0.6}, "main": {"x": lerpf(0.75, -0.55, s), "y": lerpf(1.3, 0.55, s)}, "off": {"x": -0.4, "y": -0.2}, "power": s > 0.05 and s < 0.95}
	var w: Weapon = hero.weapons.R
	_ghost(w, ff)
	_apart(hero, ff)
	await _steps(90)
	dur = 6.2
	pov_sub = "BOUT 5 · PRISCUS"
	key_by = 2.50   # (its moment at the latest)
	# [start, from, to, the shin]: a sweep low from his right onto the man's right shin, then
	# back across from his left onto the other.
	var blows := [[0.8, Vector2(0.9, 0.15), Vector2(-0.8, -1.3), "shinR"], [2.0, Vector2(-0.9, 0.1), Vector2(0.85, -1.3), "shinL"]]
	tick_fn = func(tt: float) -> void:
		var mk := Vector2(0.6, 0.5)
		var power := false
		var crouch := false
		for b in blows:
			var st: float = b[0]
			if tt >= st - 0.45 and tt < st:
				mk = b[1]
				crouch = true
			elif tt >= st and tt < st + 0.6:
				mk = (b[1] as Vector2).lerp(b[2] as Vector2, _ease((tt - st) / 0.26))
				power = tt < st + 0.36
				crouch = true
		# (A step back as he goes down: over him, out of the reach of his sword from the sand.)
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": -0.2}, "main": {"x": mk.x, "y": mk.y}, "off": {"x": -0.55, "y": -0.25}, "power": power, "crouch": crouch, "mz": -0.6 if tt > 2.5 and tt < 2.95 else 0.0}
		if since[0] < 0.0 and ff.fights_down():
			since[0] = tt
	for k in blows.size():
		var b: Array = blows[k]
		var last: bool = k == blows.size() - 1
		var f := func():
			while t < float(b[0]):
				await get_tree().physics_frame
			var shin: VoxelPart = ff.by_name[String(b[3])]
			await _blow_at(w, shin, float(b[0]) + 0.45, func(_h):
				if OS.get_environment("SCENE_DEBUG") == "1":
					print("BONES %s: fractured %s, legs %.2f %.2f, can stand %s" % [shin.part_name, str(shin.fractured), ff.leg_func("L"), ff.leg_func("R"), str(ff.can_stand())])
				if last:
					_key())
		f.call()
	# Low at the height of the sand, looking up at the two of them whole: the mace comes in at the
	# shins and the legs fold; then, tilting as he goes down, on him on the sand with the champion
	# over him (both whole in the frame: closer, he was a heap in its corner).
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var fp: Vector3 = _follow(fol, ff.torso.global_position, 0.1)
		var hp: Vector3 = hero.torso.global_position
		var eye := Vector3(fp.x - 1.1, 0.25, fp.z - 2.9)
		var at := Vector3(fp.x - 0.55, 0.85, fp.z)
		var roll := 0.0
		if tt > 2.2:
			var v := _ease((tt - 2.2) / 1.2)
			eye = eye.lerp(Vector3(fp.x - 0.9, 0.35, fp.z - 2.7), v)
			at = at.lerp(Vector3(lerpf(fp.x, hp.x, 0.45), 0.75, fp.z), v)
			roll = 0.08 * v
		return [eye, at, 50.0, eye.distance_to(at), roll]

## BEASTS: a man with a spear and a shield backs away across the sand from a lion coming on low;
## it runs at him and, four strides off, leaps: it takes him in the chest in the air and bears
## him down on his back under its weight, its jaws at him there. Its run is the game's own,
## to where the scene sends it (no mind of its own: it went for him as it chose, and the leap
## came when it would); the leap the game's lunge, thrown harder; his fall his own body's. Low on
## the sand and square to the run, the lion crossing the frame; KEY as it strikes him.
func _lion() -> void:
	_champion(CapsArt.AXE, Vector3(0, 0, -13.0), 0.0)
	var man = _man("Spiculus", {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, Vector3(2.6, 0, 0.3), -PI * 0.5, 2)
	var down := [false]
	man.drive = func(_e): return {} if down[0] else {"mz": -0.45, "look": {"yaw": -PI * 0.5, "pitch": 0.05}, "main": {"x": 0.25, "y": 0.35}, "off": {"x": -0.45, "y": 0.7}}
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(-5.2, 0.1, 0.0), "yaw": PI * 0.5})
	var lf = lion.f
	lf.sp = lf.sp.duplicate()
	lf.target = man.f
	# Run on at a mark beyond him (the game's walk to a goal: "wanderer", the goal ours and held),
	# its bite held back until the leap.
	var goal := func() -> void:
		lf.ai.goal = man.f.torso.global_position + Vector3(3.0, 0, 0)
		lf.ai.t = 99.0
		lf.ai.bite_cool = 9.0
	lf.sp.ai = "wanderer"
	goal.call()
	await _steps(30)
	dur = 5.2
	key_by = 2.40   # (its moment at the latest)
	key_tail = 2.4
	var leapt := [false]
	var bites := [0, 0.0]
	tick_fn = func(tt: float) -> void:
		if not is_instance_valid(lf) or not is_instance_valid(man.f):
			return
		var to: Vector3 = man.f.torso.global_position - lf.torso.global_position
		to.y = 0.0
		var dist := to.length()
		if not leapt[0]:
			goal.call()
			if dist < 4.4:
				# The leap: as fast along as lands it on his chest in the time it is in the air, and
				# as fast up as keeps it there that long (the game's lunge, thrown harder).
				leapt[0] = true
				lf.ai.bite_cool = 0.0
				var air := 0.55
				var lv: Vector3 = lf.torso.linear_velocity
				var along: float = Vector2(lv.x, lv.z).dot(Vector2(to.x, to.z).normalized())
				lf.sp.lunge = maxf(0.5, (dist - 0.6) / air - along)
				var mass := 0.0
				for p in lf.parts:
					mass += p.mass
				lf._lunge(to.normalized(), mass, false)
				lf.torso.apply_central_impulse(Vector3(0, mass * maxf(0.0, 9.8 * air * 0.5 - 1.2), 0))
		if down[0]:
			# Over him: its chest over his, its forepaws either side of him.
			var over: Vector3 = man.f.torso.global_position - lf.torso.global_position
			over.y = 0.0
			var fwd: Vector3 = lf.torso.global_transform.basis.z
			fwd.y = 0.0
			var want: Vector3 = over - fwd.normalized() * 0.55 * lf.S
			if want.length() > 0.15:
				var v: Vector3 = want.limit_length(1.6)
				lf.torso.linear_velocity = Vector3(v.x, lf.torso.linear_velocity.y, v.z)
			if int(bites[0]) < 4 and tt - float(bites[1]) > 0.42:
				bites[0] = int(bites[0]) + 1
				bites[1] = tt
				var aim: Vector3 = (man.f.torso.global_position + Vector3(0, 0.15, 0)) - lf.head.global_position
				lf._strike(lf.head, 0.3, 0.0, [lf.head, aim.normalized() * 30.0 * lf.head.mass], 0.0)
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
		lf.sp.ai = "statue"
		lf.sp.speed = 0.0
		for a in lf.parts:
			if a != lf.head:
				for b in man.f.parts:
					a.add_collision_exception_with(b)
	m.combat.hit.connect(on_hit)
	# Three-quarters before the man, low: the lion comes on at him from across the sand and leaps,
	# the two of them whole in the frame (side on, it crossed the frame as the troll's men did).
	var aiml := []
	cam_fn = func(tt: float) -> Array:
		var pm: Vector3 = man.f.torso.global_position if is_instance_valid(man.f) else Vector3(2.6, 0.8, 0)
		var pl: Vector3 = lf.torso.global_position if is_instance_valid(lf) else Vector3(-2, 0.8, 0)
		var at: Vector3 = _follow(aiml, pm.lerp(pl, 0.5) + Vector3(0, 0.5, 0), 0.08)
		var u := _ease(tt / dur)
		var eye := Vector3(3.6 + lerpf(0.0, 0.6, u), lerpf(0.55, 0.8, u), lerpf(5.4, 4.6, u))
		return [eye, at, 46.0, eye.distance_to(at)]

## GIANTS: three men abreast charge a troll, which waits with its plank drawn back and, as they come
## into its reach, sweeps it across in one blow that throws all three. Low behind the line as it
## runs, the troll over them; KEY at the sweep's blow.
func _troll() -> void:
	_champion(CapsArt.AXE, Vector3(0, 0, -13.0), 0.0)
	var kit := [{"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]}, {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, {"main": "longsword", "off": "", "armor": ["helmet"]}]
	var xs := [-1.2, 0.2, 1.6]
	var men := []
	for i in 3:
		var e = _man("Runner %d" % i, kit[i], Vector3(xs[i], 0, -4.8), 0.0, 2)
		e.drive = func(_e): return {"mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.2}}
		men.append(e.f)
	var spec: Dictionary = m.enemy_spec({"e": "troll", "boss": true}, 0, 1)
	spec.pos = Vector3(0.2, 0.1, 5.5)
	spec.yaw = PI
	spec.name = "Old Mossback"
	spec.loadout = {"main": "plank", "off": "", "armor": []}
	var troll = m.spawn_fighter(spec)
	troll.erase("bot")
	var tf: Fighter = troll.f
	var sweep := [-1.0]
	troll.drive = func(_e):
		var k := -1.0 if sweep[0] < 0.0 else clampf((t - sweep[0]) / 0.32, 0.0, 1.0)
		var x := 1.7 if k < 0.0 else lerpf(1.7, -1.9, k)
		return {"look": {"yaw": PI, "pitch": 0.0}, "main": {"x": x, "y": -0.55 if k >= 0.0 else 0.4}, "power": k >= 0.0}
	await _steps(20)
	dur = 6.0
	key_by = 2.60   # (its moment at the latest)
	key_tail = 3.2
	var flung := {}
	tick_fn = func(_tt: float) -> void:
		if sweep[0] < 0.0:
			var near := 99.0
			for f in men:
				if is_instance_valid(f):
					near = minf(near, Vector2(f.torso.global_position.x - tf.torso.global_position.x, f.torso.global_position.z - tf.torso.global_position.z).length())
			if near < 3.3:
				sweep[0] = t
	var on_hit := func(h: Dictionary) -> void:
		if not rolling or h.get("attacker") != tf or not men.has(h.get("char")) or flung.has(h.get("char")):
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
	# Low behind the line, looking up at the troll over them (from higher and further back it was a
	# man's size in the frame); held where it is from the sweep on (it followed the men still on
	# their feet, and jumped as each was thrown).
	var cam_c := [Vector3.ZERO]
	cam_fn = func(tt: float) -> Array:
		if flung.is_empty():
			var c := Vector3.ZERO
			for f in men:
				c += f.torso.global_position
			cam_c[0] = c / float(men.size())
		var c: Vector3 = cam_c[0]
		var bp: Vector3 = tf.torso.global_position if is_instance_valid(tf) else Vector3(0, 2.5, 5.5)
		var u := _ease(tt / 2.2)
		var eye := Vector3(c.x * 0.4, lerpf(0.45, 0.65, u), c.z - lerpf(3.4, 4.1, u))
		var at := Vector3(bp.x * 0.5, bp.y + lerpf(0.6, 0.15, u), bp.z - 1.0)
		return [eye, at, 54.0, eye.distance_to(Vector3(c.x, 1.0, c.z))]

## MONSTERS OF LEGEND: the dragon pours its fire across the sand at a man running from it, and the
## champion charges it through the smoke, his axe up: low behind him as he runs at it, the dragon
## over him and the fire across the frame. KEY when the fire comes.
func _dragon() -> void:
	var hero := _champion(CapsArt.AXE, Vector3(0.6, 0, 8.5), PI)
	var run := [false]
	hero_inp = {"mz": 0.0, "look": {"yaw": PI, "pitch": 0.15}, "main": {"x": 0.15, "y": 1.6}, "off": {"x": -0.9, "y": 0.6}, "twist": 1.3}
	var dragon = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(1.2, 0.1, -6.5), "yaw": -0.3, "harmless": true})
	dragon.f.sp = dragon.f.sp.duplicate()
	dragon.f.sp.speed = 0.0
	dragon.f.sp.lunge = 0.0
	dragon.f.sp.ai = "statue"
	# (Across before its head, off only as the scene starts: running from the first, and closer
	# in, he ran into the dragon's head.)
	var runner = _man("Runner", {"main": "spear", "off": "roundShield"}, Vector3(5.2, 0, 0.6), -PI * 0.5, 2)
	runner.drive = func(_e): return {"mz": 1.0 if rolling else 0.0, "sprint": rolling, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": -0.3, "y": 1.2}}
	await _steps(90)
	dragon.f.target = runner.f
	var reach := float(dragon.f.sp.get("breathRange", 6.0))
	m._breath(dragon.f, "fire", reach)
	dur = 5.0
	key_by = 0.50   # (its moment at the latest)
	var aimed := [false]
	tick_fn = func(tt: float) -> void:
		if tt > 0.4:
			run[0] = true
		hero_inp["mz"] = 1.0 if run[0] else 0.0
		hero_inp["sprint"] = run[0]
		var pouring: bool = m.streams.any(func(st): return st.b == dragon.f and float(st.t) < 0.75)
		if pouring and not aimed[0]:
			aimed[0] = true
			_key()
			m.breath_at(dragon.f, "fire", dragon.f.mouth_dir(), reach, 1.6)
	# High and wide from the side: the dragon whole on one side, its fire pouring across the sand
	# after the man running from it, the champion charging in from the other (from behind him as
	# he ran, it looked up the dragon's neck into the sky). Drifting in as he comes.
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		# (Its head kept in the frame as it rears at the end.)
		var eye := Vector3(lerpf(11.0, 10.2, u), lerpf(3.6, 3.4, u), lerpf(1.5, 0.5, u))
		var at := Vector3(lerpf(0.8, 0.6, u), lerpf(1.6, 2.3, u), lerpf(-0.5, -1.8, u))
		return [eye, at, 50.0, eye.distance_to(at)]

## FIRE. POISON. THUNDER.: four men stand together across the sand; a pot of Greek fire bursts
## among them and they are alight, a pot of vitriol after it, its green cloud over them, and
## then a thunder pot in the middle that throws them off their feet. Low and wide on the band,
## pushing in, the pots flying in past the camera from the champion behind it; the band facing
## him, and the sun (seen from his far side, they were black against it). KEY at the thunder.
func _pots() -> void:
	var hero := _champion(CapsArt.AXE, Vector3(-1.4, 0, 9.6), PI)
	var men := []
	var at := [Vector3(-1.1, 0, 2.6), Vector3(0.3, 0, 3.1), Vector3(1.4, 0, 2.4), Vector3(-0.2, 0, 1.8)]
	var kit := [{"main": "gladius", "off": "roundShield", "armor": ["helmet"]}, {"main": "axe", "off": "", "armor": ["helmet"]}, {"main": "spear", "off": "", "armor": ["helmet"]}, {"main": "mace", "off": "scutum", "armor": ["greaves"]}]
	for i in 4:
		var e = _man("Bandit %d" % i, kit[i], at[i], 0.0, 2)
		e.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.4, "y": 0.5}}
		men.append(e.f)
	await _steps(60)
	dur = 5.5
	key_by = 3.40   # (its moment at the latest)
	key_tail = 2.4
	var thrown := [false, false, false]
	tick_fn = func(tt: float) -> void:
		var from: Vector3 = hero.torso.global_position + Vector3(0, 0.6, -0.5)
		if not thrown[0] and tt > 0.3:
			thrown[0] = true
			m.items.throw_at("pot_fire", from, men[0].torso.global_position + Vector3(0.5, -0.8, 0.2), hero, 12.0)
		if not thrown[1] and tt > 1.3:
			thrown[1] = true
			m.items.throw_at("pot_acid", from, men[2].torso.global_position + Vector3(-0.3, -0.8, 0.0), hero, 12.0)
		if not thrown[2] and tt > 2.4:
			thrown[2] = true
			m.items.throw_at("pot_thunder", from, Vector3(0.1, 0.0, 2.5), hero, 12.0)
		if thrown[2] and not keyed and tt > 2.4 + 0.5:
			for f in men:
				if is_instance_valid(f) and f.state != "stand":
					_key()
					break
	# From high over them, turning slowly: the pots come in from the foot of the frame and burst
	# among them, the fire, the green cloud, then the thunder throwing them out every way (from
	# the sand they were a wall, the bursts behind them, and one thrown came up against the lens).
	cam_fn = func(tt: float) -> Array:
		var u := _ease(tt / dur)
		var c := Vector3(0.1, 0.3, 2.5)
		var off := Vector3(1.4, lerpf(5.6, 4.7, u), 3.1).rotated(Vector3.UP, lerpf(0.0, 0.45, u))
		var eye := c + off
		return [eye, c, 46.0, eye.distance_to(c)]

## LOSE A HAND. GAIN A BLADE.: the champion with the physician's blade riveted to the stump of
## his right forearm, a man with a sword coming at him; the blade arm's cut across his chest
## and back again, then through his sword arm. KEY at the last.
func _blade() -> void:
	var hero := _champion("gladius", Vector3(-0.9, 0, 0.0), PI * 0.5)
	hero.apply_body({"prosthetics": {"forearmR": "blade"}})
	var old: Weapon = hero.release("R")
	if old:
		old.queue_free()
	hero.equip("R", Fighter.blade_arm(2))
	# (The blade arm is shorter than a sword: a step closer than the swordsmen stand.)
	var foe = _man("Crixus", {"main": "gladius", "off": "", "armor": ["helmet"]}, Vector3(0.3, 0, 0.0), -PI * 0.5)
	var ff: Fighter = foe.f
	ff.mods.toughness = 0.8
	# His sword out before him at the champion, the other hand low: the last cut comes down on
	# his sword arm.
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.05, "y": 0.85}, "off": {"x": -0.8, "y": -0.5}}
	var w: Weapon = hero.weapons.R
	if w:
		_ghost(w, ff)
	_apart(hero, ff)
	if ff.weapons.R:
		_ghost(ff.weapons.R, hero)
	await _steps(90)
	dur = 5.0
	pov_sub = "BOUT 7 · CRIXUS"
	key_by = 2.85   # (its moment at the latest)
	key_tail = 2.0
	# [start, secs, from, to, the part]
	# (The backhand drawn up high and wide first: from beside his chest, it met him as it set off
	# and the blow was a touch.)
	var cuts := [[0.6, 0.26, Vector2(0.9, 0.9), Vector2(-0.85, -0.3), "torso"], [1.5, 0.26, Vector2(-1.0, 1.15), Vector2(0.9, -0.15), "torso"], [2.4, 0.24, Vector2(-0.1, 1.5), Vector2(-0.4, -0.6), "forearmR"]]
	tick_fn = func(tt: float) -> void:
		var mk := Vector2(0.3, 0.6)
		var power := false
		for c in cuts:
			var st := float(c[0])
			if tt >= st - 0.4 and tt < st:
				mk = c[2]
			elif tt >= st and tt < st + 0.45:
				mk = (c[2] as Vector2).lerp(c[3] as Vector2, _ease((tt - st) / float(c[1])))
				power = tt < st + float(c[1]) + 0.1
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": mk.x, "y": mk.y}, "power": power}
	for k in cuts.size():
		var c: Array = cuts[k]
		var last: bool = k == cuts.size() - 1
		var f := func():
			while t < float(c[0]):
				await get_tree().physics_frame
			if w and is_instance_valid(w):
				await _blow_at(w, ff.by_name.get(String(c[4]), ff.torso), float(c[0]) + 0.45, func(_h): if last: _key(), true, false, 10.0)
		f.call()
	# On his right, the blade's side (from his left, the blade was behind him), a little behind
	# him, pushing in: the iron on the stump before us, the two of them whole.
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
		var u := _ease(tt / dur)
		var eye := mid + Vector3(lerpf(-1.1, -0.7, u), lerpf(0.0, 0.1, u), lerpf(3.0, 2.6, u))
		return [eye, mid + Vector3(0.05, 0.05, 0), 44.0, eye.distance_to(mid)]

## BRING YOUR FRIENDS: the champion and three friends, their names over their heads as online,
## run abreast across the sand at the minotaur, its axe up over its horns; they reach it together
## and their four blows go into it at once (each where the scene sends it: a thigh, the chest, the
## axe arm), and it goes down on its knees among them. Every man's run and blow scripted, the
## giant's as well (it was bots, and the minotaur fought them as it chose). Low behind the line as
## it runs, rising as they reach it; KEY at the first blow.
func _friends() -> void:
	# (Gilded, he runs a little slower than his friends: a stride ahead of them at the start.)
	var hero := _champion(CapsArt.AXE, Vector3(-0.4, 0, -1.9), 0.0)
	var spec: Dictionary = m.enemy_spec({"e": "minotaur", "boss": true}, 0, 1)
	spec.pos = Vector3(0.0, 0.1, 4.0)
	spec.yaw = PI
	spec.name = "The Minotaur"
	spec.loadout = {"main": "executionerAxe", "off": "", "armor": []}
	var mino = m.spawn_fighter(spec)
	mino.erase("bot")
	var mf: Fighter = mino.f
	mino.drive = func(_e): return {"look": {"yaw": PI, "pitch": 0.0}, "main": {"x": 0.35, "y": 1.55}, "off": {"x": -0.6, "y": 0.4}}
	# [name, loadout, start x, spot before the giant, the part struck, start of the blow, thrust]
	# (Short names, as players' are: long ones lay on one another over the four of them.)
	var plan := [
		["Vex", {"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]}, -2.1, Vector3(-1.35, 0, 3.35), "thighL", 2.05, false],
		["", null, -0.4, Vector3(-0.5, 0, 2.95), "torso", 2.2, false],
		["Ajax", {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, 0.7, Vector3(0.5, 0, 2.95), "torso", 2.35, true],
		["Kato", {"main": "longsword", "off": "", "armor": ["helmet"]}, 2.1, Vector3(1.35, 0, 3.35), "thighR", 2.5, false],
	]
	var men := []
	for i in plan.size():
		var pl: Array = plan[i]
		if pl[1] == null:
			men.append(hero)
			continue
		var e = _man(String(pl[0]), pl[1], Vector3(float(pl[2]), 0, -2.6), 0.0, 0)
		m._name_tag(e.f, String(pl[0]))
		men.append(e.f)
	# Each man's input: run to his spot, square up to the giant, wind up and strike on his time.
	var inputs := []
	for i in plan.size():
		inputs.append({"look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.2}})
	for i in plan.size():
		if men[i] != hero:
			var k := i
			for e in m.entities:
				if e.get("f") == men[i]:
					e.drive = func(_e): return inputs[k]
	m.me.drive = func(_e): return inputs[1]
	# Every blade passes through the giant but where its blow lands, and through his friends and
	# theirs (shoulder to shoulder, the champion's axe drawn back took the man beside him on the
	# head, and a longsword was knocked out of a hand by the next man's).
	# (Shields too: a friend's scutum knocked the champion as they ran, and the game called it a
	# blow on his own teammate, the crowd laughing at him.)
	for i in plan.size():
		var f: Fighter = men[i]
		var w: Weapon = f.weapons.R
		if w:
			_ghost(w, mf)
		_apart(f, mf)
		for j in plan.size():
			if j != i:
				for side in ["L", "R"]:
					var wi = f.weapons[side]
					if wi and is_instance_valid(wi):
						_ghost(wi, men[j])
				if j > i:
					_apart(f, men[j])
	await _steps(20)
	dur = 6.0
	pov_sub = "CO-OP · BOUT 9 · THE MINOTAUR"
	key_by = 2.60   # (its moment at the latest)
	key_tail = 2.8
	var felled := [false]
	tick_fn = func(tt: float) -> void:
		for i in plan.size():
			var pl: Array = plan[i]
			var f: Fighter = men[i]
			var spot: Vector3 = pl[3]
			var to: Vector3 = spot - f.torso.global_position
			to.y = 0.0
			var st: float = pl[5]
			var inp := {"look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.35, "y": 1.25}}
			if tt > 0.1 and to.length() > 0.2:
				inp.look.yaw = atan2(to.x, to.z)
				inp["mz"] = clampf(to.length() / 0.8, 0.3, 1.0)
				inp["sprint"] = to.length() > 1.2
			else:
				var g: Vector3 = mf.torso.global_position - f.torso.global_position
				inp.look.yaw = atan2(g.x, g.z)
			# Wound up on the way in, the blow thrown on its time.
			var thrust: bool = pl[6]
			var from := Vector2(0.15, 0.3) if thrust else Vector2(0.9, 1.2)
			var to_mk := Vector2(0.05, 0.25) if thrust else Vector2(-0.7, -0.15)
			if tt >= st - 0.6 and tt < st:
				inp.main = {"x": from.x, "y": from.y}
			elif tt >= st and tt < st + 0.6:
				var u := _ease((tt - st) / 0.26)
				var mk := from.lerp(to_mk, u)
				inp.main = {"x": mk.x, "y": mk.y}
				inp["power"] = tt < st + 0.36
				if thrust and tt < st + 0.4:
					inp["thrust"] = 1.0
					inp["aimAt"] = mf.torso.global_position
			inputs[i] = inp
		if OS.get_environment("SCENE_DEBUG") == "1" and absf(tt - 1.9) < 0.005:
			for i in plan.size():
				print("FRIENDS %d at %s, spot %s; giant at %s" % [i, str(men[i].torso.global_position.snapped(Vector3.ONE * 0.01)), str(plan[i][3]), str(mf.torso.global_position.snapped(Vector3.ONE * 0.01))])
		# Four blows in him: he goes down on his knees among them.
		if not felled[0] and keyed and tt > float(plan.back()[5]) + 0.3:
			felled[0] = true
			mf.fall(3.0, true)
	for i in plan.size():
		var pl: Array = plan[i]
		var f: Fighter = men[i]
		var w: Weapon = f.weapons.R
		if w == null:
			continue
		var st: float = pl[5]
		var thrust: bool = pl[6]
		var part: VoxelPart = mf.by_name.get(String(pl[4]), mf.torso)
		var go := func():
			while t < st:
				await get_tree().physics_frame
			await _blow_at(w, part, st + 0.45, func(_h): _key(), true, thrust)
		go.call()
	# High behind the line, following the charge like a crane: the four abreast across the frame,
	# their names over them, the minotaur whole over them as they reach it (from the side they
	# stood one behind another and their names lay on one another; low behind them it was the
	# troll's shot).
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var c := Vector3.ZERO
		for f in men:
			c += f.torso.global_position
		c = _follow(fol, c / float(men.size()), 0.1)
		var u := _ease(tt / 2.6)
		var eye := Vector3(lerpf(-1.4, -0.9, u), lerpf(2.3, 2.9, u), c.z - lerpf(4.4, 5.3, u))
		var at := Vector3(lerpf(-0.2, 0.0, u), lerpf(1.3, 1.7, u), c.z + lerpf(2.6, 1.6, u))
		return [eye, at, 50.0, eye.distance_to(at)]

## The climax: the hydra, all but one of its necks gone, faces the champion with his zweihander;
## he cuts into its last neck, from the right, from the left, and backs out from under it as it
## rears; it brings its head down at him, jaws open, and he meets it with the blade swung up
## into it, the head coming down onto the edge. Its bite is the game's own (let go at him on its
## time); his blow comes as it does. The editor plays the blow in the slowest motion of all and
## cuts to black on it. KEY on the blow.
func _hydra() -> void:
	var hero := _champion("zweihander", Vector3(0.0, 0, 5.2), PI)
	hero.mods.strength = 4.5
	var hy = m.spawn_beast({"beast": "hydra", "team": Match.ENEMY_TEAM, "pos": Vector3(0.0, 0.1, 2.0), "yaw": 0.0})
	var hf = hy.f
	hf.sp = hf.sp.duplicate()
	hf.sp.speed = 0.0
	hf.sp.lunge = 0.0
	hf.sp.ai = "statue"
	for n in ["neck1", "neck2", "neck3", "neck4"]:
		if hf.by_name.has(n) and not hf.by_name[n].severed:
			hf.detach_limb(hf.by_name[n], {"removed": [], "severed": []})
	var neck: VoxelPart = hf.by_name.get("neck0", hf.head)
	var left: Array = hf.heads_left()
	var hd: VoxelPart = left[0] if not left.is_empty() else hf.head
	# Its head held back until the scene lets it go at him (it struck at him from where it
	# stood, and the second and third cuts met a head in the way instead of the neck).
	var bite_at := 3.35
	var calm := func() -> void:
		if t < bite_at or not rolling:
			hf.target = null
			for h in hf.heads:
				hf.strike_cool[h] = 99.0
		else:
			hf.target = hero
			if not hf.strikes.has(hd) and float(hf.strike_cool.get(hd, 0.0)) > 50.0:
				hf.strike_cool[hd] = 0.0
	calm.call()
	var w: Weapon = hero.weapons.R
	_ghost(w, hf)
	await _steps(60)
	dur = 6.4
	pov_sub = "BOUT 12 · THE HYDRA"
	key_by = 4.40   # (its moment at the latest)
	key_tail = 2.6
	# [start (the last: when its head comes at him), the part, from, to]: a cut into the neck from
	# his right, another from his left, then the blade swung up into the head coming down at him
	# (swung down across it, blade and head went the same way and the blow was a touch; up into
	# it, the two meet head on).
	var cuts := [[1.4, neck, Vector2(0.9, 1.15), Vector2(-0.85, 0.2)], [2.6, neck, Vector2(-0.9, 1.1), Vector2(0.85, 0.2)], [99.0, hd, Vector2(0.95, 0.0), Vector2(-0.7, 1.7)]]
	var done := [false]
	tick_fn = func(tt: float) -> void:
		calm.call()
		# His blow as its head comes down at him (reared back first, it comes down from on high).
		if float(cuts[2][0]) > 90.0 and hf.strikes.has(hd) and hd.global_position.y < 4.2 and hd.linear_velocity.y < -1.0:
			cuts[2][0] = tt
		# In to the neck before each cut, as far from it as at the first (struck, it drew back
		# out of his reach).
		var mz := 0.0
		var look := PI
		for c in cuts:
			var p: VoxelPart = c[1]
			if p == neck and is_instance_valid(p) and not p.severed and tt >= float(c[0]) - 1.0 and tt < float(c[0]) - 0.15:
				var d: Vector3 = p.global_position - hero.torso.global_position
				d.y = 0.0
				look = atan2(d.x, d.z)
				mz = clampf((d.length() - 1.45) * 2.5, 0.0, 1.0)
		# Back out from under its neck as it rears (it came down on him from over his head, behind
		# his blade): its head comes down at him from before him.
		if tt > float(cuts[1][0]) + 0.4 and float(cuts[2][0]) > 90.0:
			look = PI
			mz = -clampf((6.2 - hero.torso.global_position.z) * 2.5, 0.0, 1.0)
		var mk := Vector2(0.85, 1.1)
		var power := false
		for c in cuts:
			var st: float = c[0]
			if done[0] and tt > st:
				continue
			if tt >= st - 0.5 and tt < st:
				mk = c[2]
			elif tt >= st and tt < st + 0.45:
				mk = (c[2] as Vector2).lerp(c[3] as Vector2, _ease((tt - st) / 0.26))
				power = tt < st + 0.36
		hero_inp = {"look": {"yaw": look, "pitch": 0.15}, "main": {"x": mk.x, "y": mk.y}, "power": power, "mz": mz}
	for k in cuts.size():
		var c: Array = cuts[k]
		var last: bool = k == cuts.size() - 1
		var f := func():
			while t < float(c[0]):
				await get_tree().physics_frame
			var p: VoxelPart = c[1]
			if done[0] or not is_instance_valid(p) or p.severed:
				return
			# (The last once the blade is going: met as it set off, the blow was a touch.)
			await _blow_at(w, p, float(c[0]) + 0.45, func(h):
				if OS.get_environment("SCENE_DEBUG") == "1":
					print("HYDRA %s at %.2f: J %.0f, its head %.0f hp" % [p.part_name, t, float(h.get("J", 0.0)), hd.hp])
				if last:
					done[0] = true
					_key(), true, false, 6.0 if last else 3.0)
		f.call()
	# Low, three-quarters behind the champion and well back: him whole, the hydra over him, its
	# head reared high and coming down at him onto his blade (side on and close, the head came
	# down out of the top of the frame and he was a helmet in its corner).
	var aimh := []
	cam_fn = func(tt: float) -> Array:
		var hp: Vector3 = hero.torso.global_position
		var target: Vector3 = hd.global_position if is_instance_valid(hd) else neck.global_position
		var a: Vector3 = _follow(aimh, hp.lerp(target, 0.45) + Vector3(0, -0.3, 0), 0.08)
		var eye := hp + Vector3(2.3, 0.4, 3.8)
		return [eye, a, 56.0, eye.distance_to(hp)]

## Under the title: the champion alone in the middle, his back to us, his axe raised to the stands
## and the Emperor's box; low behind him, going in and up.
func _finale() -> void:
	var hero := _champion(CapsArt.AXE, Vector3(0, 0, 2.0), 0.0)
	hero_inp = {"look": {"yaw": 0.0, "pitch": 0.45}, "main": {"x": 0.1, "y": 1.7}, "off": {"x": -0.7, "y": 1.1}}
	await _emperor(true)
	await _steps(75)
	dur = 10.0
	# Low behind him, then up and back, high over the sand: the champion alone in the middle of it,
	# the box and the stands on their feet beyond (under the title).
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var lift := _ease((tt - 1.5) / (dur - 1.5))
		var eye := h + Vector3(lerpf(0.9, 0.0, lift), lerpf(-0.45, 6.5, lift), lerpf(-4.2, -12.0, lift))
		var at := Vector3(0, lerpf(2.4, 1.2, lift), lerpf(12.0, 7.0, lift))
		return [eye, at, lerpf(50.0, 46.0, lift), eye.distance_to(h)]

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
