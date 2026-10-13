class_name Fx
extends Node3D
## What the fight looks like besides the bodies: GPU particle bursts (a spray of blood, sparks
## off a clang, dust, smoke, flames, confetti) and marks left on the sand (blood that pools and
## dries, scorch and acid stains). Drawing only: the host and every guest make their own.

const MAX_MARKS := 180

static var current: Fx = null
static var _process_mats := {}
static var _draw_meshes := {}
static var _textures := {}

var headless := false
var marks: Array = []
var quality := "high"

func _init(headless_ := false) -> void:
	headless = headless_
	name = "Fx"
	if not headless and Save:
		quality = str(Save.get_value("settings", {}).get("quality", "high"))

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

# ---------- Textures, made once ----------

## A soft round spot (puffs, flames), or an irregular splat (blood, stains), as a texture.
static func texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = hash(kind)
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var dx := (x - n / 2.0 + 0.5) / (n / 2.0)
			var dy := (y - n / 2.0 + 0.5) / (n / 2.0)
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.0
			match kind:
				"soft":
					a = clampf(1.0 - r, 0.0, 1.0)
					a = a * a
				"splat":
					var edge := 0.62 + 0.3 * noise.get_noise_2d(x * 1.0, y * 1.0)
					a = clampf((edge - r) * 6.0, 0.0, 1.0)
					# A few droplets thrown out round the pool.
					if a <= 0.0 and noise.get_noise_2d(x * 3.1 + 40.0, y * 3.1) > 0.45 and r < 0.95:
						a = 0.9
				"ring":
					a = clampf(1.0 - r, 0.0, 1.0) * (0.6 + 0.4 * noise.get_noise_2d(x * 2.0, y * 2.0))
				"spark":
					a = clampf(1.0 - r * 1.6, 0.0, 1.0)
				"flame":
					# A tongue of flame: narrow and ragged at the top, full at the root.
					var ny := (dy + 1.0) * 0.5
					var w := 0.18 + 0.62 * pow(ny, 0.7) + 0.12 * noise.get_noise_2d(x * 1.5, y * 0.8)
					a = clampf(1.0 - absf(dx) / maxf(0.05, w), 0.0, 1.0) * clampf(ny * 1.4, 0.0, 1.0) * clampf((1.0 - ny) * 5.0, 0.0, 1.0)
					a = sqrt(a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_textures[kind] = t
	return t

# ---------- Particles ----------

const KINDS := {
	"blood": {"color": Color(0.5, 0.02, 0.02), "life": 0.9, "speed": [1.8, 4.8], "spread": 42.0, "gravity": -9.8, "size": [0.028, 0.07], "tex": "spark", "drag": 0.3, "shade": true},
	"drip": {"color": Color(0.45, 0.01, 0.01), "life": 1.1, "speed": [0.05, 0.35], "spread": 25.0, "gravity": -9.8, "size": [0.022, 0.045], "tex": "spark", "emit": 1.0, "shade": true},
	"bloodmist": {"color": Color(0.5, 0.03, 0.03, 0.55), "life": 0.5, "speed": [0.5, 1.6], "spread": 60.0, "gravity": -2.0, "size": [0.08, 0.2], "tex": "soft", "drag": 2.0, "grow": 1.6, "shade": true},
	"sparks": {"color": Color(1.0, 0.75, 0.35), "life": 0.35, "speed": [3.0, 8.0], "spread": 70.0, "gravity": -6.0, "size": [0.012, 0.025], "tex": "spark", "emit": 6.0, "add": true},
	"dust": {"color": Color(0.78, 0.68, 0.5, 0.55), "life": 1.6, "speed": [0.4, 1.8], "spread": 80.0, "gravity": 0.3, "size": [0.25, 0.6], "tex": "soft", "drag": 1.5, "grow": 2.2},
	"smoke": {"color": Color(0.22, 0.2, 0.19, 0.5), "life": 2.4, "speed": [0.2, 0.8], "spread": 30.0, "gravity": 0.9, "size": [0.2, 0.45], "tex": "soft", "drag": 0.8, "grow": 2.5},
	"fire": {"color": Color(1.0, 0.55, 0.15), "life": 0.6, "speed": [0.3, 1.2], "spread": 25.0, "gravity": 2.2, "size": [0.08, 0.18], "tex": "soft", "emit": 4.0, "add": true, "shrink": true},
	"brazier": {"color": Color(1.0, 0.55, 0.15), "life": 0.9, "speed": [0.6, 1.6], "spread": 18.0, "gravity": 2.5, "size": [0.18, 0.36], "tex": "soft", "emit": 5.0, "add": true, "shrink": true},
	"confetti": {"color": Color(1, 1, 1), "life": 2.0, "speed": [2.0, 5.0], "spread": 60.0, "gravity": -3.0, "size": [0.03, 0.05], "tex": "", "drag": 1.2, "confetti": true},
	"acid": {"color": Color(0.56, 0.83, 0.23, 0.8), "life": 0.9, "speed": [1.0, 3.0], "spread": 60.0, "gravity": -9.8, "size": [0.02, 0.04], "tex": "spark", "emit": 1.5},
	"blastfire": {"color": Color(1.0, 0.62, 0.22), "life": 0.7, "speed": [2.5, 6.5], "spread": 180.0, "gravity": 1.5, "size": [0.35, 0.8], "tex": "soft", "drag": 3.0},
	"pool_fire": {"color": Color(1.0, 0.5, 0.12), "life": 0.7, "speed": [0.3, 0.9], "spread": 12.0, "gravity": 3.0, "size": [0.26, 0.55], "tex": "flame", "emit": 3.0, "shrink": true},
	"pool_smoke": {"color": Color(0.12, 0.1, 0.09, 0.55), "life": 3.0, "speed": [0.6, 1.4], "spread": 20.0, "gravity": 0.6, "size": [0.35, 0.8], "tex": "soft", "drag": 0.4},
	"blade_fire": {"color": Color(1.0, 0.45, 0.08), "life": 0.42, "speed": [0.25, 0.8], "spread": 30.0, "gravity": 2.8, "size": [0.06, 0.13], "tex": "soft", "emit": 9.0, "add": true, "shrink": true},
	"venom": {"color": Color(0.45, 0.85, 0.2), "life": 0.9, "speed": [0.02, 0.2], "spread": 25.0, "gravity": -7.0, "size": [0.014, 0.03], "tex": "spark", "emit": 1.6},
	"frost": {"color": Color(0.72, 0.9, 1.0, 0.9), "life": 0.9, "speed": [0.05, 0.35], "spread": 180.0, "gravity": -0.4, "size": [0.01, 0.024], "tex": "spark", "emit": 2.5, "add": true, "drag": 0.5},
	"embers": {"color": Color(1.0, 0.6, 0.25), "life": 4.0, "speed": [0.15, 0.5], "spread": 180.0, "gravity": 0.22, "size": [0.008, 0.018], "tex": "spark", "emit": 5.0, "add": true, "drag": 0.3},
	"petals": {"color": Color(0.62, 0.05, 0.06), "life": 6.0, "speed": [0.2, 0.6], "spread": 180.0, "gravity": -0.35, "size": [0.025, 0.045], "tex": "", "drag": 1.6},
	"debris": {"color": Color(0.6, 0.5, 0.4), "life": 1.2, "speed": [1.0, 4.0], "spread": 80.0, "gravity": -9.8, "size": [0.025, 0.05], "tex": "", "shade": true},
}

static func _process_mat(kind: String) -> ParticleProcessMaterial:
	if _process_mats.has(kind):
		return _process_mats[kind]
	var k: Dictionary = KINDS[kind]
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = k.spread
	pm.initial_velocity_min = k.speed[0]
	pm.initial_velocity_max = k.speed[1]
	pm.gravity = Vector3(0, k.gravity, 0)
	pm.damping_min = k.get("drag", 0.0)
	pm.damping_max = k.get("drag", 0.0) * 1.5
	pm.scale_min = 1.0
	pm.scale_max = k.size[1] / k.size[0]
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT if kind == "blood" or kind == "acid" or kind == "drip" else ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.2
	if k.get("grow", 0.0) > 0.0:
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5))
		c.add_point(Vector2(1, k.grow))
		c.max_value = k.grow
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
	if k.get("shrink", false):
		var c2 := Curve.new()
		c2.add_point(Vector2(0, 1))
		c2.add_point(Vector2(1, 0))
		var ct2 := CurveTexture.new()
		ct2.curve = c2
		pm.scale_curve = ct2
	var g := Gradient.new()
	var col: Color = k.color
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0) if kind != "blood" else Color(col.r * 0.6, 0, 0, 0.8))
	if kind == "blastfire":
		g.set_color(0, Color(1.0, 0.97, 0.75))
		g.add_point(0.18, Color(1.0, 0.62, 0.15, 1.0))
		g.add_point(0.5, Color(0.55, 0.16, 0.05, 0.85))
		g.set_color(g.get_point_count() - 1, Color(0.12, 0.09, 0.08, 0.0))
	if kind == "pool_fire":
		g.set_color(0, Color(1.0, 0.95, 0.65, 1.0))
		g.add_point(0.3, Color(1.0, 0.55, 0.12, 0.95))
		g.add_point(0.7, Color(0.75, 0.18, 0.04, 0.7))
		g.set_color(g.get_point_count() - 1, Color(0.2, 0.06, 0.03, 0.0))
	if kind == "fire" or kind == "brazier":
		g.set_color(0, Color(1.0, 0.9, 0.5))
		g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
		g.set_color(g.get_point_count() - 1, Color(0.3, 0.1, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	if k.get("confetti", false):
		pm.angular_velocity_min = -720.0
		pm.angular_velocity_max = 720.0
		var hues := Gradient.new()
		hues.set_color(0, Color(1, 0.25, 0.38))
		hues.add_point(0.33, Color(0.25, 0.75, 1))
		hues.add_point(0.66, Color(1, 0.82, 0.25))
		hues.set_color(hues.get_point_count() - 1, Color(0.38, 1, 0.5))
		var ht := GradientTexture1D.new()
		ht.gradient = hues
		pm.color_initial_ramp = ht
		pm.color_ramp = null
	_process_mats[kind] = pm
	return pm

static func _draw_mesh(kind: String) -> Mesh:
	if _draw_meshes.has(kind):
		return _draw_meshes[kind]
	var k: Dictionary = KINDS[kind]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var mesh: PrimitiveMesh
	if k.tex == "":
		mesh = BoxMesh.new()
		(mesh as BoxMesh).size = Vector3.ONE * k.size[0]
		mat.roughness = 0.6
	else:
		mesh = QuadMesh.new()
		(mesh as QuadMesh).size = Vector2.ONE * k.size[0] * 2.0
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = texture(k.tex)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if k.get("shade", false) else BaseMaterial3D.SHADING_MODE_UNSHADED
		if k.get("add", false):
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		if k.has("emit"):
			mat.emission_enabled = true
			mat.emission = k.color
			mat.emission_energy_multiplier = k.emit
	mesh.material = mat
	_draw_meshes[kind] = mesh
	return mesh

## A one-shot burst of `n` particles of `kind` at `p`, flung along `dir` (up if none), in
## `tint` instead of the kind's own colour when one is given (alpha above zero).
func burst(kind: String, p: Vector3, n: int, dir := Vector3.UP, speed_mul := 1.0, tint := Color(0, 0, 0, 0)) -> void:
	if headless or n <= 0 or not KINDS.has(kind):
		return
	if quality == "low":
		n = maxi(1, n / 3)
	var ps := GPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.amount = mini(n, 400)
	ps.lifetime = KINDS[kind].life
	ps.process_material = _process_mat(kind)
	if tint.a > 0.0:
		var pm: ParticleProcessMaterial = _process_mat(kind).duplicate()
		var g := Gradient.new()
		g.set_color(0, tint)
		g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		ps.process_material = pm
	ps.draw_pass_1 = _draw_mesh(kind)
	ps.speed_scale = 1.0
	ps.fixed_fps = 0
	ps.interpolate = true
	ps.amount_ratio = 1.0
	ps.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(ps)
	ps.global_position = p
	if dir.length_squared() > 1e-4 and not dir.normalized().is_equal_approx(Vector3.UP):
		var d := dir.normalized()
		var axis := Vector3.UP.cross(d)
		if axis.length_squared() > 1e-6:
			ps.global_basis = Basis(axis.normalized(), Vector3.UP.angle_to(d))
	if speed_mul != 1.0:
		ps.speed_scale = clampf(speed_mul, 0.3, 3.0)
	ps.emitting = true
	get_tree().create_timer(KINDS[kind].life / ps.speed_scale + 0.5, false).timeout.connect(ps.queue_free)

## A steady emitter (flames on a burning limb, a brazier, a smoke cloud) parented to `parent`.
func emitter(kind: String, parent: Node3D, amount := 24, radius := 0.06) -> GPUParticles3D:
	if headless:
		return null
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = KINDS[kind].life
	var pm: ParticleProcessMaterial = _process_mat(kind).duplicate()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	ps.process_material = pm
	ps.draw_pass_1 = _draw_mesh(kind)
	ps.local_coords = false
	ps.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	parent.add_child(ps)
	return ps

## A flash of light (a blast, Greek fire catching) that fades out.
func flash(p: Vector3, color: Color, energy := 8.0, r := 6.0) -> void:
	if headless:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = r
	l.shadow_enabled = false
	add_child(l)
	l.global_position = p + Vector3(0, 0.4, 0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

# ---------- Marks on the sand ----------

## A mark projected down onto the sand at `p` (x, z): blood, a scorch, an acid stain. Old marks
## go when there are too many; blood darkens as it dries.
func mark(kind: String, p: Vector3, size: float, angle := -1.0) -> Decal:
	if headless or quality == "low":
		return null
	var d := Decal.new()
	match kind:
		"blood":
			d.texture_albedo = texture("splat")
			d.modulate = Color(0.45, 0.02, 0.02, 0.92)
		"scorch":
			d.texture_albedo = texture("ring")
			d.modulate = Color(0.06, 0.05, 0.04, 0.85)
		"acid":
			d.texture_albedo = texture("splat")
			d.modulate = Color(0.35, 0.55, 0.12, 0.8)
		_:
			d.texture_albedo = texture("soft")
			d.modulate = Color(0.3, 0.25, 0.2, 0.5)
	d.size = Vector3(size, 0.6, size)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	add_child(d)
	d.global_position = Vector3(p.x, 0.05, p.z)
	d.rotation.y = angle if angle >= 0.0 else randf() * TAU
	marks.append({"d": d, "kind": kind, "t": 0.0})
	if marks.size() > MAX_MARKS:
		var old = marks.pop_front()
		if is_instance_valid(old.d):
			old.d.queue_free()
	return d

## A pool that spreads under a body (a dying man): the mark grows to `size` over `seconds`.
func pool(p: Vector3, size: float, seconds := 6.0) -> void:
	var d := mark("blood", p, size * 0.3)
	if d == null:
		return
	var tw := create_tween()
	tw.tween_property(d, "size", Vector3(size, 0.6, size), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func _process(dt: float) -> void:
	# Blood dries: from red to the brown of old blood over a minute and a half.
	for mk in marks:
		if mk.kind != "blood" or mk.t > 90.0:
			continue
		mk.t += dt
		var d: Decal = mk.d
		if is_instance_valid(d):
			var k := clampf(mk.t / 90.0, 0.0, 1.0)
			d.modulate = Color(0.45, 0.02, 0.02, 0.92).lerp(Color(0.24, 0.06, 0.03, 0.85), k)

func clear() -> void:
	for mk in marks:
		if is_instance_valid(mk.d):
			mk.d.queue_free()
	marks.clear()
