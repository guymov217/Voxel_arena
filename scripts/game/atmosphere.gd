class_name Atmosphere
extends Node3D
## What the arena's air holds, so it never looks still: motes of dust turning in the sun, a low
## haze of sand over the floor, wisps of sand the wind drags along it, birds wheeling high over
## the velarium, and rose petals the crowd throws down when the fight is worth it.

const WIND := Vector3(1.0, 0.0, 0.35)

var petals: GPUParticles3D
var birds: Array = []   # [{node, r, h, speed, phase}]
var arena: Node = null
var t := 0.0

func build(arena_: Node, day: bool, quality: String) -> void:
	arena = arena_
	var lv: int = {"low": 0, "medium": 1, "high": 2, "ultra": 3}.get(quality, 2)
	_motes(day, [60, 140, 240, 320][lv])
	_wisps(day, [10, 24, 40, 56][lv])
	if lv >= 2:
		_haze(day)
	if day:
		_birds(4 if lv == 0 else 7)
	_petals()

func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	return tex

func _quad(size: float, color: Color, emission := 0.0, tex: Texture2D = null) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = tex if tex else _soft_texture()
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emission
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	q.material = m
	return q

## Dust in the light: tiny specks that drift and turn slowly all over the arena.
func _motes(day: bool, amount: int) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = 14.0
	ps.preprocess = 14.0
	ps.randomness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(15, 3.5, 15)
	pm.direction = WIND.normalized()
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.15
	pm.gravity = Vector3(0, 0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	ps.process_material = pm
	var c := Color(1.0, 0.94, 0.82, 0.4) if day else Color(0.7, 0.75, 0.95, 0.25)
	ps.draw_pass_1 = _quad(0.03, c)
	ps.visibility_aabb = AABB(Vector3(-17, -1, -17), Vector3(34, 9, 34))
	ps.position = Vector3(0, 3.6, 0)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)

## Sand the wind drags along the floor in thin streams.
func _wisps(day: bool, amount: int) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = 4.5
	ps.preprocess = 4.5
	ps.randomness = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.05, 13)
	pm.direction = WIND.normalized()
	pm.spread = 12.0
	pm.flatness = 0.9
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	ps.process_material = pm
	ps.draw_pass_1 = _quad(0.9, Color(0.86, 0.76, 0.58, 0.16) if day else Color(0.5, 0.48, 0.45, 0.1))
	ps.visibility_aabb = AABB(Vector3(-17, -1, -17), Vector3(34, 3, 34))
	ps.position = Vector3(0, 0.12, 0)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)

## A haze of fine sand hanging low over the floor, thickest at the sand and gone by head height:
## the sun's shafts show in it (needs the volumetric fog of the high settings).
func _haze(day: bool) -> void:
	var fv := FogVolume.new()
	fv.size = Vector3(32, 2.4, 32)
	fv.position = Vector3(0, 0.6, 0)
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := FogMaterial.new()
	fm.density = 0.06 if day else 0.012
	fm.albedo = Color(0.9, 0.8, 0.62) if day else Color(0.45, 0.48, 0.6)
	fm.height_falloff = 1.6
	fm.edge_fade = 0.6
	var dn := FastNoiseLite.new()
	dn.frequency = 0.06
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 16
	tex.depth = 64
	tex.seamless = true
	tex.noise = dn
	fm.density_texture = tex
	fv.material = fm
	add_child(fv)

## Birds wheeling high over the velarium: each a V of two wings that beat, then glide.
func _birds(n: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body along +z, a wing either side; UV.x is how far out along the wing (for the beat).
	for side in [-1.0, 1.0]:
		var pts := [Vector3(0, 0, 0.18), Vector3(side * 0.55, 0.02, 0.0), Vector3(0, 0, -0.12), Vector3(side * 0.55, 0.02, 0.0), Vector3(side * 0.35, 0.0, -0.1), Vector3(0, 0, -0.12)]
		for p in pts:
			st.set_uv(Vector2(absf(p.x) / 0.55, 0))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bird.gdshader")
	mesh.surface_set_material(0, mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in n:
		var b := MeshInstance3D.new()
		b.mesh = mesh
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.scale = Vector3.ONE * rng.randf_range(1.3, 1.9)
		b.set_instance_shader_parameter("phase", rng.randf() * TAU)
		add_child(b)
		birds.append({"node": b, "r": rng.randf_range(12.0, 30.0), "h": rng.randf_range(16.0, 26.0), "speed": rng.randf_range(0.08, 0.16) * (1.0 if i % 3 else -1.0), "phase": rng.randf() * TAU, "cx": rng.randf_range(-8, 8), "cz": rng.randf_range(-8, 8)})

## Rose petals from the stands, thrown when the crowd is roaring.
func _petals() -> void:
	petals = GPUParticles3D.new()
	petals.amount = 90
	petals.lifetime = 6.0
	petals.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = Arena.RADIUS + 3.0
	pm.emission_ring_inner_radius = Arena.RADIUS + 1.0
	pm.emission_ring_height = 0.5
	pm.direction = Vector3(0, 0.6, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.radial_velocity_min = -2.6
	pm.radial_velocity_max = -1.2
	pm.gravity = Vector3(0, -0.9, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.9
	pm.collision_bounce = 0.0
	var hues := Gradient.new()
	hues.set_color(0, Color(0.85, 0.08, 0.15))
	hues.set_color(1, Color(0.98, 0.65, 0.7))
	var ht := GradientTexture1D.new()
	ht.gradient = hues
	pm.color_initial_ramp = ht
	petals.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.05)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.roughness = 0.7
	q.material = m
	petals.draw_pass_1 = q
	petals.visibility_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 12, 40))
	petals.position = Vector3(0, 4.0, 0)
	add_child(petals)

func _process(dt: float) -> void:
	t += dt
	for b in birds:
		var a: float = b.phase + t * b.speed
		var p := Vector3(b.cx + sin(a) * b.r, b.h + sin(t * 0.3 + b.phase) * 1.5, b.cz + cos(a) * b.r)
		var ahead := Vector3(b.cx + sin(a + 0.05 * signf(b.speed)) * b.r, p.y, b.cz + cos(a + 0.05 * signf(b.speed)) * b.r)
		var n: MeshInstance3D = b.node
		n.position = p
		if ahead.distance_squared_to(p) > 1e-6:
			n.look_at(ahead, Vector3.UP, true)
			n.rotate_object_local(Vector3(0, 0, 1), -signf(b.speed) * 0.35)
	if petals and arena:
		petals.emitting = float(arena.excitement) > 0.62
		petals.amount_ratio = clampf((float(arena.excitement) - 0.55) * 2.5, 0.1, 1.0)
