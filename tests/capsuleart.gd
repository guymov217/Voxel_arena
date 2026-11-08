extends Node
## The Steam capsule art (`-- --probe capsuleart`, needs a display): a scene of the game staged,
## played until its best moment (a hard blow, the pieces in the air), frozen there and drawn
## large from a cinema camera: the clear afternoon of the "late" look (LOOKS), a rim light behind
## the fighters, depth of field.
## CAPS_SCENE picks the scene (giant, lion, clash, dragon, squad); CAPS_VIEWS the frames (wide
## 2560x1440, tall 1440x2160, hero 3840x1240, main 2464x1412: the main capsule at twice its size);
## CAPS_FRAMING=side the main capsule's framings (_side_framings). PNGs:
## SHOT_DIR/cap_<scene>_<view>_<n>.png, put together into the capsules by tools/make_capsules.py.

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
const VIEWS := {"wide": Vector2i(2560, 1440), "tall": Vector2i(1440, 2160), "hero": Vector2i(3840, 1240), "preview": Vector2i(1280, 720),
	"main": Vector2i(2464, 1412), "mprev": Vector2i(1232, 706)}   # (the main capsule, twice its size; and as it is)

## The light of the art: the game's own afternoon, only clearer (user: the old frames were far
## too bright and warm, they glowed and the detail was lost in the glow). A white sun from the
## camera's side, high enough to model the faces; open, cool shade; next to no haze and no
## bloom; the exposure down. CAPS_LOOKS "a,b" shoots each framing in each look, to compare; the
## art is shot in "late" (the sun lower and a little warmer than "clear", the shadows long, the
## colour kept; "old" is the look the art had before).
const LOOKS := {
	"clear": {"sun": Color(1.0, 0.95, 0.88), "energy": 2.0, "elev": 34.0, "ambient": 0.45, "exposure": 0.74, "haze": 0.0015, "fog": 0.003, "scatter": 0.05, "glow": 0.3, "bloom": 0.0, "contrast": 1.1, "sat": 1.04, "rim": 0.6, "rim_col": Color(0.92, 0.95, 1.0)},
	"dim": {"sun": Color(1.0, 0.95, 0.88), "energy": 2.0, "elev": 34.0, "ambient": 0.38, "exposure": 0.64, "haze": 0.0015, "fog": 0.003, "scatter": 0.05, "glow": 0.3, "bloom": 0.0, "contrast": 1.12, "sat": 1.05, "rim": 0.6, "rim_col": Color(0.92, 0.95, 1.0)},
	"late": {"sun": Color(1.0, 0.89, 0.77), "energy": 2.2, "elev": 26.0, "ambient": 0.4, "exposure": 0.68, "haze": 0.003, "fog": 0.003, "scatter": 0.1, "glow": 0.35, "bloom": 0.0, "contrast": 1.12, "sat": 1.05, "rim": 0.8, "rim_col": Color(1.0, 0.9, 0.8)},
	"old": {"sun": Color(1.0, 0.75, 0.5), "energy": 2.3, "elev": 22.8, "ambient": 0.6, "exposure": 0.95, "haze": 0.011, "fog": 0.005, "scatter": 0.25, "glow": 1.05, "bloom": 0.12, "contrast": 1.14, "sat": 1.14, "rim": 1.7, "rim_col": Color(1.0, 0.62, 0.34)},
}
var look := "late"

## The giant's guard for the art (CAPS_POSE): `main` and `off` the hands as a fighter's input
## gives them, `crouch` his knees bent, `twist` the haft turned. CAPS_TRY_POSES "a,b" holds him
## in each in turn and shoots a preview of each.
const POSES := {
	"high": {"main": {"x": 0.6, "y": 0.6}},
	"cocked": {"main": {"x": 0.55, "y": 0.35}, "crouch": true},
	"low": {"main": {"x": 0.45, "y": -0.15}, "crouch": true},
	"across": {"main": {"x": -0.1, "y": 0.25}, "crouch": true},
	"wide": {"main": {"x": 0.75, "y": 0.2}, "crouch": true},
	"chest": {"main": {"x": 0.3, "y": 0.15}},
}

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
	var tries: Array = Array(OS.get_environment("CAPS_TRY_POSES").split(",", false))
	if scene == "giant" and not tries.is_empty():
		await _try_poses(tries)
		get_tree().quit()
		return
	# CAPS_MAX: only the first framings of each view (a frame of the full picture takes a minute).
	var most := int(OS.get_environment("CAPS_MAX")) if OS.get_environment("CAPS_MAX") != "" else 99
	var looks: Array = Array(OS.get_environment("CAPS_LOOKS").split(",", false))
	if looks.is_empty():
		looks = [look]
	for v in views:
		var list = shots.call(String(v))
		if list is Dictionary:
			list = [list]
		# CAPS_PICK: only these framings, by number ("4,5").
		var pick: Array = Array(OS.get_environment("CAPS_PICK").split(",", false)).map(func(x): return int(x))
		for k in mini((list as Array).size(), most if pick.is_empty() else 99):
			if not pick.is_empty() and not pick.has(k):
				continue
			var sh: Dictionary = list[k]
			for lk in looks:
				look = String(lk)
				await _shoot("%s_%s_%d%s" % [scene, v, k, "" if looks.size() == 1 else "_" + look], sh.eye, sh.at, float(sh.fov), VIEWS[String(v)], String(v) == "tall")
	get_tree().quit()

## Each guard of POSES in turn on the giant squared up to the hero, held a few seconds, then a
## preview of it from the low three-quarter framing and the one at a man's height.
func _try_poses(names: Array) -> void:
	var g = m.enemies()[0]
	var gf: Fighter = g.f
	var hero: Fighter = m.me.f
	var gap := float(OS.get_environment("CAPS_GAP")) if OS.get_environment("CAPS_GAP") != "" else 4.0
	for nm in names:
		if not POSES.has(nm):
			print("no pose ", nm)
			continue
		get_tree().paused = false
		g.drive = pose_drive(gf, hero, POSES[nm], 0.0, gap)
		for i in 360:
			await get_tree().physics_frame
		get_tree().paused = true
		print("pose %s: %s" % [nm, str(squared_up(gf, hero, 1.5))])
		var list := _facing_framings("preview", hero.torso.global_position, gf.torso.global_position, float(gf.S))
		for k in [0, 1]:
			await _shoot("giantpose_%s_%d" % [nm, k], list[k].eye, list[k].at, float(list[k].fov), VIEWS.preview, false)

## Framings of two fighters (`a` the hero, `b` his foe of size `s`): from either side and from
## over the hero's shoulder, low (the heroic angle) or at eye height, far enough for both whole.
func _framings(view: String, a: Vector3, b: Vector3, s := 1.0) -> Array:
	if OS.get_environment("CAPS_FRAMING") == "side":
		return _side_framings(a, b, s)
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

## How squarely the giant `g` stands up to the hero `me`: `ok` when he is on his feet, turned to
## the hero and looking at him, his feet set as a fighter sets them (both down, neither wide nor
## long), his trunk up and his weapon up, and the hero turned to him too (the art's moment, user:
## the giant looks at his foe in a fighting stance, ready to fight). `k` loosens every bound.
static func squared_up(g: Fighter, me: Fighter, k := 1.0) -> Dictionary:
	var r := {"ok": false}
	if g.state != "stand" or me.state != "stand" or not g.alive or not me.alive or g.head.severed:
		return r
	var gp: Vector3 = g.torso.global_position
	var to_me := Vector3(me.torso.global_position.x - gp.x, 0, me.torso.global_position.z - gp.z)
	r.gap = to_me.length()
	var fwd := Vector3(sin(g.yaw), 0, cos(g.yaw))
	r.face = rad_to_deg(fwd.angle_to(to_me))
	var hf: Vector3 = g.head.global_transform.basis.z.normalized()
	var to_head: Vector3 = me.head.global_position - g.head.global_position
	r.look = rad_to_deg(Vector3(hf.x, 0, hf.z).angle_to(Vector3(to_head.x, 0, to_head.z)))
	r.over = rad_to_deg(asin(clampf(hf.y, -1.0, 1.0)) - atan2(to_head.y, Vector2(to_head.x, to_head.z).length()))
	var a: Vector3 = g.by_name["shinL"].global_transform * Vector3(0, -4 * Fighter.V * g.S, 0)
	var b: Vector3 = g.by_name["shinR"].global_transform * Vector3(0, -4 * Fighter.V * g.S, 0)
	var d := b - a
	r.across = absf(d.dot(fwd.cross(Vector3.UP))) / g.S
	r.along = absf(d.dot(fwd)) / g.S
	var planted: bool = g.feet.L != null and g.feet.R != null and not g.feet.L.swing and not g.feet.R.swing
	r.bow = rad_to_deg(g.torso.global_transform.basis.y.normalized().angle_to(Vector3.UP))
	var w = g.weapons.get("R")
	r.up = -9.0
	if w:
		r.up = ((w.global_position + PD.quat_of(w) * Vector3(0, w.reach * 0.85, 0)).y - gp.y) / g.S
	r.hero = rad_to_deg(Vector3(sin(me.yaw), 0, cos(me.yaw)).angle_to(-to_me))
	# His face clear: neither hand nor his weapon on the line from his eye to the hero's face
	# (the hammer held up over his head hid it).
	var eye: Vector3 = g.head.global_position + hf * 0.15 * g.S
	var ray: Vector3 = (me.head.global_position - eye).normalized()
	var pts: Array = [g.hand_world("L"), g.hand_world("R")]
	if w:
		for j in 5:
			pts.append(w.global_position + PD.quat_of(w) * Vector3(0, w.reach * (0.2 * j), 0))
	r.clear = 9.0
	for q in pts:
		var rel: Vector3 = (q as Vector3) - eye
		var along_ray := rel.dot(ray)
		if along_ray > 0.0 and along_ray < 2.5 * g.S:
			r.clear = minf(r.clear, (rel - ray * along_ray).length() / g.S)
	r.v = maxf(Vector2(g.v_smooth.x, g.v_smooth.z).length(), Vector2(me.v_smooth.x, me.v_smooth.z).length())
	r.ok = planted and r.gap > 1.8 and r.gap < 6.5 * k and r.face < 12.0 * k and r.look < 15.0 * k and absf(r.over) < 20.0 * k \
		and r.across > 0.12 and r.across < 0.45 * k and r.along < 0.48 * k and r.bow < 14.0 * k and r.up > 0.1 - 0.2 * (k - 1.0) \
		and r.hero < 25.0 * k and r.v < 0.9 * k and r.clear > 0.15 / k
	return r

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

## The arena drawn at its best (every light and shadow of ultra), the crowd on its feet.
func _light() -> void:
	var a: Arena = m.arena
	if a == null:
		return
	Arena.apply_quality(a.env, a.sun, "ultra")
	var e := a.env
	e.sdfgi_enabled = false   # (it settles over many frames; one is drawn)
	e.volumetric_fog_temporal_reprojection_enabled = false
	a.set_excitement(1.0)

## The look (LOOKS) laid on for a shot from `eye` at `at`: the sun from the camera's side so the
## faces turned to it are lit, a light from behind the fighters on their edges.
func _aim_lights(eye: Vector3, at: Vector3) -> void:
	var lk: Dictionary = LOOKS.get(look, LOOKS.clear)
	var fwd := at - eye
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	if m.arena and m.arena.env:
		var e: Environment = m.arena.env
		e.tonemap_exposure = float(lk.exposure)
		e.ambient_light_energy = float(lk.ambient)
		e.volumetric_fog_enabled = float(lk.haze) > 0.0
		e.volumetric_fog_density = float(lk.haze)
		e.fog_density = float(lk.fog)
		e.fog_sun_scatter = float(lk.scatter)
		e.glow_intensity = float(lk.glow)
		e.glow_bloom = float(lk.bloom)
		e.glow_hdr_threshold = 1.3
		e.adjustment_contrast = float(lk.contrast)
		e.adjustment_saturation = float(lk.sat)
	if m.arena and m.arena.sun:
		var sun: DirectionalLight3D = m.arena.sun
		sun.light_color = lk.sun
		sun.light_energy = float(lk.energy)
		var d := (fwd * 0.75 + side * 0.65).normalized() * cos(deg_to_rad(float(lk.elev))) + Vector3(0, -sin(deg_to_rad(float(lk.elev))), 0)
		sun.look_at_from_position(Vector3.ZERO, d.normalized(), Vector3.UP)
	if rim == null:
		rim = DirectionalLight3D.new()
		rim.shadow_enabled = false
		add_child(rim)
	rim.light_color = lk.rim_col
	rim.light_energy = float(lk.rim)
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

## The champion and the Cyclops squared up before the clash: the giant's one eye on the hero,
## his hammer up, the hero's gilded axe raised at him, the stands behind (CAPS_GUARD "x:y" the
## giant's guard, CAPS_GAP the stand-off in metres).
func _giant() -> Callable:
	_arena({"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": true, "respawn": false, "difficulty": 0.7}, "autopilot": true,
		"loadout": {"main": AXE, "off": "", "armor": GILT}})
	for i in 120:
		await get_tree().physics_frame
	var g = m.enemies()[0]
	var gf: Fighter = g.f
	var hero: Fighter = m.me.f
	# The giant comes on at the hero; before the first blow the two square up: each turned to
	# the other and looking him in the face, the giant's hammer up, the hero's axe up, the feet
	# set (user: the giant looks at his foe in a fighting stance, ready to fight). Held as a
	# fighter holds a guard, at the stand-off before the clash.
	var gap := float(OS.get_environment("CAPS_GAP")) if OS.get_environment("CAPS_GAP") != "" else 4.0
	var gxy: Array = Array((OS.get_environment("CAPS_GUARD") if OS.get_environment("CAPS_GUARD") != "" else "0.6:0.6").split(":"))
	for i in 120 * 20:
		await get_tree().physics_frame
		var d0: Vector3 = gf.torso.global_position - hero.torso.global_position
		if Vector2(d0.x, d0.z).length() < gap + 3.0:
			break
	var hxy: Array = Array((OS.get_environment("CAPS_HERO") if OS.get_environment("CAPS_HERO") != "" else "0.45:0.85").split(":"))
	# His guard: CAPS_POSE by name (POSES), else CAPS_GUARD by hand, else "across": the haft held
	# across him, his face and eye clear of his hands (raised high, his arm hid his face).
	var guard: Dictionary = POSES.across
	if OS.get_environment("CAPS_GUARD") != "":
		guard = {"main": {"x": float(gxy[0]), "y": float(gxy[1])}}
	if POSES.has(OS.get_environment("CAPS_POSE")):
		guard = POSES[OS.get_environment("CAPS_POSE")]
	g.drive = pose_drive(gf, hero, guard, 0.0, gap)
	m.me.drive = pose_drive(hero, gf, {"x": float(hxy[0]), "y": float(hxy[1])}, 2.6, 99.0)
	# The hero's axe has already bitten into him: a few chunks out of the giant's thigh, arm and
	# side, on the side the camera sees (CAPS_SCARS 0: none).
	if OS.get_environment("CAPS_SCARS") != "0":
		for pn in ["thighL", "upperArmL", "torso", "thighR"]:
			var part: VoxelPart = gf.by_name[pn]
			var dir: Vector3 = part.global_position - hero.torso.global_position
			dir.y = 0.0
			dir = dir.normalized()
			var side := dir.cross(Vector3.UP)
			var pt: Vector3 = part.global_position - dir * part.half_ext.z * 1.1 + Vector3(0, part.half_ext.y * 0.2, 0)
			gf.apply_hit(part, {"impulse": 24.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": pt, "dir": dir, "axis": side, "edge": dir, "heavy": 0.3, "weapon": true, "mass": 1.5})
			for j in 12:
				await get_tree().physics_frame
	for i in 120:
		await get_tree().physics_frame
	# Into a fighting stance, each his left foot forward (both right-handed).
	set_stance(gf, "L", 0.22, 0.12, 0.08)
	set_stance(hero, "L", 0.22, 0.12, 0.08)
	for i in 60:
		await get_tree().physics_frame
	step_rear(gf, "L")
	step_rear(hero, "L")
	var k := 1.0
	var held := 0
	for i in 120 * 12:
		await get_tree().physics_frame
		if i % 240 == 239:
			k *= 1.2
		held = held + 1 if i > 90 and squared_up(gf, hero, k).ok else 0
		if held >= 6:
			break
	print("squared up: %s" % str(squared_up(gf, hero, k)))
	var h: Vector3 = hero.torso.global_position
	var gp: Vector3 = gf.torso.global_position
	var S := float(gf.S)
	return func(view: String) -> Array:
		return _facing_framings(view, h, gp, S)

## Sets a fighter's feet as in a guard, the lead foot forward and the rear one back and out
## (Fighter.stance), and has him step into it, the lead foot first.
static func set_stance(f: Fighter, lead: String, fwd: float, back: float, out: float) -> void:
	var rear := "R" if lead == "L" else "L"
	f.stance[lead] = Vector2(fwd, out * 0.5)
	f.stance[rear] = Vector2(-back, out)
	var ft = f.feet[lead]
	if ft != null and not ft.swing:
		ft.swing = true
		ft.from = ft.anchor
		ft.s = 0.0

## Steps the rear foot into the guard once the lead one is down.
static func step_rear(f: Fighter, lead: String) -> void:
	var ft = f.feet["R" if lead == "L" else "L"]
	if ft != null and not ft.swing:
		ft.swing = true
		ft.from = ft.anchor
		ft.s = 0.0

## A fighter held in a guard by hand: turned to his foe and looking him in the face, the main
## hand where `hand` puts it, a step in while farther off than `near`, a step back while closer
## than `room`, else standing his ground.
static func pose_drive(f: Fighter, foe: Fighter, hand: Dictionary, room: float, near: float) -> Callable:
	# `hand` the main hand's {x, y}, or a whole guard of POSES (its hands, knees, haft).
	var pose: Dictionary = hand if hand.has("main") else {"main": hand}
	return func(_e) -> Dictionary:
		var d: Vector3 = foe.torso.global_position - f.torso.global_position
		var dh: Vector3 = foe.head.global_position - f.head.global_position
		f.gaze = foe.head.global_position
		var gap := Vector2(d.x, d.z).length()
		var step := -0.7 if gap < room else (0.5 if gap > near else 0.0)
		var inp := {"mx": 0.0, "mz": step, "main": pose.main, "look": {"yaw": atan2(d.x, d.z), "pitch": atan2(dh.y, Vector2(dh.x, dh.z).length())}}
		for k in ["off", "crouch", "twist"]:
			if pose.has(k):
				inp[k] = pose[k]
		return inp

## Framings of a hero squared up to a giant (`a` the hero, `b` the giant of size `s`): from behind
## the hero's shoulder, a third and a half of the way round, so the giant's face is seen turned
## on the hero; low, looking up at the giant, or at a man's height.
func _facing_framings(view: String, a: Vector3, b: Vector3, s: float) -> Array:
	if OS.get_environment("CAPS_FRAMING") == "side":
		return _side_framings(a, b, s)
	var d := _ground(b - a)
	var gap := d.length()
	d = d.normalized() if gap > 0.05 else Vector3(0, 0, 1)
	var side := d.cross(Vector3.UP)
	var mid := _ground(a.lerp(b, 0.55))
	var tall := 1.0 + 0.9 * (s - 1.0)
	var dist := (2.6 + gap * 0.9) * (1.0 + 0.75 * (s - 1.0)) * float(OS.get_environment("CAPS_NEAR") if OS.get_environment("CAPS_NEAR") != "" else "0.66")
	var fov := 44.0
	match view:
		"tall":
			dist *= 0.8
			fov = 50.0
		"hero":
			dist *= 1.35
			fov = 34.0
	var out := []
	for ang in [30.0, -30.0, 45.0, -45.0]:
		var dir := (-d).rotated(Vector3.UP, deg_to_rad(ang))
		for hgt in [0.45, 1.35]:
			out.append({"eye": mid + dir * dist + Vector3(0, hgt, 0), "at": mid + Vector3(0, tall * 0.95, 0), "fov": fov})
	return out

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

## The main capsule's framings (CAPS_FRAMING=side): to one side of the line from the hero `a` to
## his foe `b` (of size `s`), standing between them along it, near the hero: each of the two is
## seen three-quarters from the front, the hero big and near, the foe beyond him; low (a giant
## towering) or at the chest. Both sides, two places along the line, two heights.
func _side_framings(a: Vector3, b: Vector3, s: float) -> Array:
	var d := _ground(b - a)
	var gap := d.length()
	d = d.normalized() if gap > 0.05 else Vector3(0, 0, 1)
	var side := d.cross(Vector3.UP)
	var tall := 1.0 + 0.9 * (s - 1.0)
	var outm := float(OS.get_environment("CAPS_OUT")) if OS.get_environment("CAPS_OUT") != "" else 1.8 + 0.9 * (s - 1.0)
	var fov := float(OS.get_environment("CAPS_FOVA")) if OS.get_environment("CAPS_FOVA") != "" else 50.0 + 6.0 * (s - 1.0)
	var out := []
	for sg in [1.0, -1.0]:
		for al in [0.15, 0.35]:
			for hgt in [0.35, 0.95]:
				var eye := _ground(a + d * gap * al + side * sg * outm) + Vector3(0, hgt, 0)
				var at := _ground(a.lerp(b, 0.5)) + Vector3(0, tall * 0.85, 0)
				out.append({"eye": eye, "at": at, "fov": fov})
	return out
