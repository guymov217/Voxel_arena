extends Node
## The Steam capsule art (`-- --probe capsuleart`, needs a display): a scene of the game staged,
## played until its best moment (a hard blow, the pieces in the air), frozen there and drawn
## large from a cinema camera: a low sun, a rim light behind the fighters, haze, depth of field.
## CAPS_SCENE picks the scene (giant, lion, clash, dragon, squad); CAPS_VIEWS the frames (wide
## 2560x1440, tall 1440x2160, hero 3840x1240). PNGs: SHOT_DIR/cap_<scene>_<view>.png, put
## together into the capsules by tools/make_capsules.py.

## The hero's own weapon: a forged war axe, gold and steel, a ruby set in it.
const AXE := {"name": "Wrecker", "kind": "weapon", "twoHanded": false, "sharpness": 0.9, "voxels": [
	[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "grip"], [0, 2, 0, "wood", "grip"], [0, 3, 0, "wood", "grip"],
	[0, 4, 0, "wood", "blunt"], [0, 5, 0, "wood", "blunt"], [0, 6, 0, "wood", "blunt"], [0, 7, 0, "wood", "blunt"],
	[0, 8, 0, "wood", "blunt"], [0, 9, 0, "gold", "blunt"], [0, 10, 0, "gold", "blunt"], [0, 11, 0, "gold", "blunt"],
	[1, 9, 0, "steel", "blunt"], [1, 10, 0, "ruby", "blunt"], [1, 11, 0, "steel", "blunt"],
	[2, 8, 0, "steel", "blunt"], [2, 9, 0, "steel", "blunt"], [2, 10, 0, "steel", "blunt"], [2, 11, 0, "steel", "blunt"], [2, 12, 0, "steel", "blunt"],
	[3, 7, 0, "steel", "edge"], [3, 8, 0, "steel", "blunt"], [3, 9, 0, "steel", "blunt"], [3, 10, 0, "steel", "blunt"], [3, 11, 0, "steel", "blunt"], [3, 12, 0, "steel", "blunt"], [3, 13, 0, "steel", "edge"],
	[4, 6, 0, "steel", "edge"], [4, 7, 0, "steel", "edge"], [4, 8, 0, "steel", "edge"], [4, 9, 0, "steel", "edge"], [4, 10, 0, "steel", "edge"], [4, 11, 0, "steel", "edge"], [4, 12, 0, "steel", "edge"], [4, 13, 0, "steel", "edge"], [4, 14, 0, "steel", "edge"],
	[-1, 10, 0, "steel", "point"], [-2, 10, 0, "steel", "point"], [0, 12, 0, "steel", "point"], [0, 13, 0, "steel", "point"]]}
const GILT := ["goldHelmet", "goldLorica", "manica", "greaves", "cape"]
const VIEWS := {"wide": Vector2i(2560, 1440), "tall": Vector2i(1440, 2160), "hero": Vector2i(3840, 1240)}

var m: Match
var out := ""
var big := {}
var wanted := 20.0
var want_attacker = null
var want_victim = null
var deep := 0
var rim: DirectionalLight3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out = OS.get_environment("SHOT_DIR")
	var scene := OS.get_environment("CAPS_SCENE")
	var views: Array = (OS.get_environment("CAPS_VIEWS") if OS.get_environment("CAPS_VIEWS") != "" else "wide,tall").split(",")
	seed(int(OS.get_environment("CAPS_SEED")) if OS.get_environment("CAPS_SEED") != "" else 7)
	# The fight plays out unseen (a frame of the full picture is slow to draw without a GPU);
	# only the frames saved are drawn.
	RenderingServer.render_loop_enabled = false
	Engine.max_physics_steps_per_frame = 64
	var shots: Callable
	match scene:
		"giant":
			shots = await _giant()
		"lion":
			shots = await _beast("lion", "gladius", "roundShield", true)
		"gorilla":
			shots = await _beast("gorilla", "spear", "scutum")
		"clash":
			shots = await _clash()
		"dragon":
			shots = await _dragon()
		"squad":
			shots = await _squad()
		_:
			print("CAPS_SCENE: giant, lion, gorilla, clash, dragon, squad")
			get_tree().quit(1)
			return
	# Frozen at the moment: the pieces and the blood hang in the air for every frame drawn.
	get_tree().paused = true
	get_viewport().disable_3d = true
	# CAPS_MAX: only the first framings of each view (a frame of the full picture takes a minute).
	var most := int(OS.get_environment("CAPS_MAX")) if OS.get_environment("CAPS_MAX") != "" else 99
	for v in views:
		var list = shots.call(String(v))
		if list is Dictionary:
			list = [list]
		for k in mini((list as Array).size(), most):
			var sh: Dictionary = list[k]
			await _shoot("%s_%s_%d" % [scene, v, k], sh.eye, sh.at, float(sh.fov), VIEWS[String(v)], String(v) == "tall")
	get_tree().quit()

## Framings of two fighters (`a` the hero, `b` his foe of size `s`): from either side and from
## over the hero's shoulder, low (the heroic angle) or at eye height, far enough for both whole.
func _framings(view: String, a: Vector3, b: Vector3, s := 1.0) -> Array:
	var d := _ground(b - a)
	var gap := d.length()
	d = d.normalized() if gap > 0.05 else Vector3(0, 0, 1)
	var side := d.cross(Vector3.UP)
	var mid := _ground(a.lerp(b, 0.5 if s < 1.5 else 0.42))
	var tall := 1.0 + 0.9 * (s - 1.0)          # half the height of what is in frame
	var dist := (2.6 + gap * 0.9) * (1.0 + 0.75 * (s - 1.0))
	var fov := 44.0
	match view:
		"tall":
			dist *= 0.8
			fov = 50.0
		"hero":
			dist *= 1.35
			fov = 34.0
	var out := []
	for dir in [side, -side, (side - d * 0.75).normalized(), (-side - d * 0.75).normalized()]:
		for hgt in [0.45, 1.35]:
			if out.size() >= (8 if view == "wide" else 4):
				break
			out.append({"eye": mid + dir * dist + Vector3(0, hgt, 0), "at": mid + Vector3(0, tall * 0.95, 0), "fov": fov})
	return out

# ---------- Staging ----------

func _arena(opts: Dictionary) -> void:
	m = Match.new()
	m.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(m)
	opts.merge({"decrees": [], "hazards": [], "seed": 3}, false)
	m.setup(opts)
	if m.killcam:
		m.killcam.queue_free()
		m.killcam = null
	_light()
	m.combat.hit.connect(_on_hit)

func _on_hit(h: Dictionary) -> void:
	if not big.is_empty() or float(h.get("J", 0.0)) < wanted or not (h.get("p") is Vector3):
		return
	if want_attacker != null and h.get("attacker") != want_attacker:
		return
	if want_victim != null and h.get("char") != want_victim:
		return
	var res = h.get("res", {})
	if deep > 0 and (not (res is Dictionary) or (res.get("removed", []) as Array).size() < deep):
		return
	big = h

## Plays on until the blow wanted lands (the bar lowered every ten seconds it does not), then a
## few hundredths more for the pieces to fly clear.
func _until_blow(max_s := 45.0, after := 6) -> void:
	var waited := 0
	while big.is_empty() and waited < int(120 * max_s):
		await get_tree().physics_frame
		waited += 1
		if m.arena:
			m.arena.set_excitement(1.0)
		if waited % 1200 == 0:
			wanted *= 0.75
			deep = deep / 2
	for i in after:
		await get_tree().physics_frame
	print("blow J=%.0f after %.1f s" % [float(big.get("J", 0.0)), waited / 120.0])

## Low golden sun, haze for the light to show in, the crowd on its feet.
func _light() -> void:
	var a: Arena = m.arena
	if a == null:
		return
	Arena.apply_quality(a.env, a.sun, "ultra")
	var e := a.env
	e.sdfgi_enabled = false   # (it settles over many frames; one is drawn)
	e.volumetric_fog_temporal_reprojection_enabled = false
	e.volumetric_fog_density = 0.011
	e.glow_intensity = 1.05
	e.glow_bloom = 0.12
	e.adjustment_saturation = 1.14
	e.adjustment_contrast = 1.14
	e.tonemap_exposure = 0.95
	a.sun.light_color = Color(1.0, 0.75, 0.5)
	a.sun.light_energy = 2.3
	a.set_excitement(1.0)

## The sun from the camera's side, low, so the faces turned to it are lit and the shadows long;
## a warm light from behind the fighters on their edges.
func _aim_lights(eye: Vector3, at: Vector3) -> void:
	var fwd := at - eye
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	if m.arena and m.arena.sun:
		var d := (fwd * 0.75 + side * 0.65).normalized() + Vector3(0, -0.42, 0)
		m.arena.sun.look_at_from_position(Vector3.ZERO, d.normalized(), Vector3.UP)
	if rim == null:
		rim = DirectionalLight3D.new()
		rim.shadow_enabled = false
		rim.light_color = Color(1.0, 0.62, 0.34)
		rim.light_energy = 1.7
		add_child(rim)
	var r := (-fwd * 0.9 - side * 0.3).normalized() + Vector3(0, -0.35, 0)
	rim.look_at_from_position(Vector3.ZERO, r.normalized(), Vector3.UP)

func _shoot(nm: String, eye: Vector3, at: Vector3, fov: float, size: Vector2i, tall: bool) -> void:
	var sv := SubViewport.new()
	sv.size = size
	sv.world_3d = get_viewport().find_world_3d()
	sv.msaa_3d = Viewport.MSAA_4X
	sv.use_debanding = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var c := Camera3D.new()
	c.fov = fov
	c.keep_aspect = Camera3D.KEEP_WIDTH if tall else Camera3D.KEEP_HEIGHT
	c.near = 0.05
	c.far = 500.0
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = eye.distance_to(at) + 5.0
	ca.dof_blur_far_transition = 14.0
	ca.dof_blur_amount = 0.05
	c.attributes = ca
	sv.add_child(c)
	add_child(sv)
	c.look_at_from_position(eye, at, Vector3.UP)
	c.current = true
	_aim_lights(eye, at)
	var t0 := Time.get_ticks_msec()
	RenderingServer.render_loop_enabled = true
	for k in 3:
		await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(out.path_join("cap_%s.png" % nm))
	RenderingServer.render_loop_enabled = false
	sv.queue_free()
	print("saved cap_%s (%d ms)" % [nm, Time.get_ticks_msec() - t0])

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

# ---------- The scenes ----------

## The champion and the Cyclops: a hard blow of his axe biting into the giant, the chunks in the
## air; the giant's one eye over the hero, the stands behind.
func _giant() -> Callable:
	_arena({"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": true, "respawn": false, "difficulty": 0.7}, "autopilot": true,
		"loadout": {"main": AXE, "off": "", "armor": GILT}})
	for i in 120:
		await get_tree().physics_frame
	var g = m.enemies()[0]
	want_attacker = m.me.f
	want_victim = g.f
	wanted = 14.0
	deep = 2
	await _until_blow(50.0, 5)
	var h: Vector3 = m.me.f.torso.global_position
	var gp: Vector3 = g.f.torso.global_position
	var S := float(g.f.S)
	return func(view: String) -> Array:
		return _framings(view, h, gp, S)

## A man and a beast at each other: the hero's blow (or the beast's) at its height.
func _beast(kind: String, weapon: String, shield: String, it_strikes := false) -> Callable:
	_arena({"mode": "training", "training": {"enemy": kind, "immortal": true, "respawn": false, "difficulty": 0.8}, "autopilot": true,
		"loadout": {"main": weapon, "off": shield, "armor": ["helmet", "manica", "greaves"]}})
	for i in 120:
		await get_tree().physics_frame
	var b = m.enemies()[0]
	if it_strikes:
		# The beast's own moment: the spring, the jaws on him (held after a blow of his, it lay
		# on the sand in every frame).
		wanted = 8.0
		deep = 0
		want_attacker = b.f
		want_victim = m.me.f
		await _until_blow(50.0, 2)
	else:
		wanted = 16.0
		deep = 3
		want_victim = b.f
		await _until_blow(50.0, 5)
	var h: Vector3 = m.me.f.torso.global_position
	var bp: Vector3 = b.f.torso.global_position
	var S := float(b.f.S)
	return func(view: String) -> Array:
		return _framings(view, h, bp, maxf(1.0, S))

## Two gladiators, a cut that takes a limb.
func _clash() -> Callable:
	_arena({"mode": "duel", "autopilot": true})
	for i in 120 * 3:
		await get_tree().physics_frame
	wanted = 30.0
	deep = 12
	await _until_blow(60.0, 4)
	var a = big.get("attacker")
	var v = big.get("char")
	var pa: Vector3 = a.torso.global_position if a is Fighter and is_instance_valid(a) else Vector3.ZERO
	var pv: Vector3 = v.torso.global_position if v is Fighter and is_instance_valid(v) else Vector3(1, 1, 0)
	return func(view: String) -> Array:
		return _framings(view, pa, pv, 1.0)

## The dragon pours fire across the sand at a man running from it; the champion in gilded
## armour in front, his axe raised.
func _dragon() -> Callable:
	_arena({"mode": "training", "training": {"enemy": "none", "respawn": false}, "seed": 11,
		"loadout": {"main": AXE, "off": "", "armor": GILT}})
	var hero: Fighter = m.me.f
	hero.teleport(Vector3(0, 0, 1.0))
	var pose := {"look": {"yaw": 0.0, "pitch": 0.35}, "main": {"x": 0.15, "y": 1.6}, "off": {"x": -0.9, "y": 0.6}, "twist": 1.3}
	m.me.drive = func(_e): return pose
	hero.yaw = 0.0
	var dragon = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(1.2, 0.1, -6.5), "yaw": -0.5, "harmless": true})
	dragon.f.sp = dragon.f.sp.duplicate()
	dragon.f.sp.speed = 0.0
	dragon.f.sp.lunge = 0.0
	dragon.f.sp.ai = "statue"
	var runner = m.spawn_fighter({"kind": "bot", "name": "Runner", "loadout": {"main": "spear", "off": "roundShield"}, "team": 2, "pos": Vector3(-1.5, 0, -3.5), "yaw": -PI * 0.5})
	runner.erase("bot")
	runner.drive = func(_e): return {"mz": 1.0, "sprint": false, "look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": -0.3, "y": 1.2}}
	for i in 120 * 2:
		await get_tree().physics_frame
		if m.arena:
			m.arena.set_excitement(1.0)
	dragon.f.target = runner.f
	var reach := float(dragon.f.sp.get("breathRange", 6.0))
	m._breath(dragon.f, "fire", reach)
	# The jaws turn onto the runner first and only then pour: the moment is a third of a second
	# into the pouring, the jet lit again the way the head points by then (the first burst went
	# where the head was when it drew breath).
	var lit := -1
	for i in int(120 * 3.0):
		await get_tree().physics_frame
		var pouring: bool = m.streams.any(func(st): return st.b == dragon.f and float(st.t) < 0.75)
		if pouring and lit < 0:
			lit = i
			m.breath_at(dragon.f, "fire", dragon.f.mouth_dir(), reach, 0.9)
			break
	# The fire is GPU particles: they only move while frames are drawn (the staging runs with
	# the drawing off), so the last moments before the picture are drawn.
	RenderingServer.render_loop_enabled = true
	for i in 14:
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = false
	print("dragon fire: ", "poured" if lit >= 0 else "never poured")
	var c: Vector3 = hero.torso.global_position
	return func(view: String) -> Dictionary:
		match view:
			"tall":
				return {"eye": c + Vector3(1.0, -0.45, 4.9), "at": c + Vector3(0.3, 1.45, -2.0), "fov": 56.0}
			"hero":
				return {"eye": c + Vector3(2.2, 0.1, 6.5), "at": c + Vector3(-0.4, 1.3, -3.0), "fov": 36.0}
			_:
				return {"eye": c + Vector3(1.6, -0.3, 4.0), "at": c + Vector3(-0.3, 0.8, -2.5), "fov": 46.0}

## Three friends against a minotaur and his wolves (online, up to eight).
func _squad() -> Callable:
	_arena({"mode": "training", "training": {"enemy": "none", "respawn": false}, "autopilot": true,
		"loadout": {"main": AXE, "off": "", "armor": GILT}})
	m.me.f.teleport(Vector3(0, 0, 0))
	var allies := [
		m.spawn_fighter({"kind": "bot", "name": "Marcus", "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "manica"]}, "team": 0, "pos": Vector3(-1.6, 0, -0.6), "yaw": 0.0, "diff": 0.9}),
		m.spawn_fighter({"kind": "bot", "name": "Livia", "loadout": {"main": "spear", "off": "roundShield", "armor": ["helmet", "greaves"]}, "team": 0, "pos": Vector3(1.6, 0, -0.6), "yaw": 0.0, "diff": 0.9}),
	]
	var spec := m.enemy_spec({"e": "minotaur", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 6.0)
	spec.yaw = PI
	var boss = m.spawn_fighter(spec)
	for i in 2:
		m.spawn_beast({"beast": "wolf", "team": Match.ENEMY_TEAM, "pos": Vector3(-3.0 + 6.0 * i, 0.1, 5.0), "yaw": PI})
	for i in 120 * 3:
		await get_tree().physics_frame
	wanted = 22.0
	deep = 3
	await _until_blow(40.0, 5)
	var pts := [m.me.f.torso.global_position]
	for al in allies:
		if is_instance_valid(al.f):
			pts.append(al.f.torso.global_position)
	var bp: Vector3 = boss.f.torso.global_position if is_instance_valid(boss.f) else Vector3(0, 1, 5)
	var squad := Vector3.ZERO
	for p in pts:
		squad += p
	squad /= pts.size()
	var S := float(boss.f.S) if is_instance_valid(boss.f) else 2.0
	return func(view: String) -> Array:
		return _framings(view, squad, bp, S)
