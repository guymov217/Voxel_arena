class_name Arena
extends Node3D
## The sand, the wall and the stands (arena.js): a 15 m ring with a wall that, for the physics,
## rises far above the stands so nothing flung sails out of the map.

const RADIUS := 15.0
const SEGMENTS := 36

var theme := "colosseum"

func build(theme_ := "colosseum", visuals := true) -> void:
	theme = theme_
	if visuals:
		Sfx.ambience(true)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = VoxelPart.LAYER_WORLD
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(60, 1, 60)
	gs.shape = gb
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	ground.physics_material_override = pm
	add_child(ground)
	var r := RADIUS + 0.4
	for i in SEGMENTS:
		var a := float(i) / SEGMENTS * TAU
		var wall := StaticBody3D.new()
		wall.collision_layer = VoxelPart.LAYER_WORLD
		wall.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(TAU * r / SEGMENTS + 0.2, 40, 0.8)
		cs.shape = bs
		wall.add_child(cs)
		wall.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * r, 19, cos(a) * r))
		add_child(wall)
	if visuals:
		_build_visuals()

var env: Environment
var sun: DirectionalLight3D
var torches: Array = []

## How the arena is lit and what its air holds, for a quality level (low, medium, high, ultra).
## Low is what the oldest machines can draw; ultra lets light bounce off the sand.
static func apply_quality(e: Environment, sun_: DirectionalLight3D, q: String) -> void:
	var lv: int = {"low": 0, "medium": 1, "high": 2, "ultra": 3}.get(q, 2)
	e.ssao_enabled = lv >= 1
	e.ssao_radius = 1.0
	e.ssao_intensity = 2.8
	e.ssao_power = 1.6
	e.ssao_light_affect = 0.15
	e.ssao_detail = 0.6
	e.ssil_enabled = lv >= 2
	e.ssil_intensity = 0.8
	e.sdfgi_enabled = lv >= 3
	e.sdfgi_use_occlusion = true
	e.sdfgi_energy = 0.8
	e.sdfgi_cascades = 4
	e.glow_enabled = lv >= 1
	e.glow_intensity = 0.85
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.volumetric_fog_enabled = lv >= 2
	e.volumetric_fog_density = 0.004
	e.volumetric_fog_albedo = Color(0.85, 0.76, 0.6)
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 48.0
	e.volumetric_fog_sky_affect = 0.15
	e.fog_enabled = lv < 2
	if sun_:
		sun_.shadow_enabled = true
		sun_.directional_shadow_max_distance = 40.0 if lv >= 2 else 25.0
		sun_.shadow_blur = 1.0
		sun_.light_volumetric_fog_energy = 1.4

func _build_visuals() -> void:
	var day := theme != "night"
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_material(day)
	sky.radiance_size = Sky.RADIANCE_SIZE_256   # the size a realtime sky is drawn at anyway
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.55
	e.ambient_light_color = Color(0.85, 0.72, 0.55)
	# Clear and easy on the eye: the sun a little lower and softer, the exposure down a touch so
	# the sand no longer glares white, the colours kept bright (the "clear" look, E, of the
	# lighting trials: tests/lightshots.gd).
	e.ambient_light_energy = 0.65 if day else 0.27
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.8 if day else 0.88
	e.tonemap_white = 6.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05 if day else 1.08
	e.adjustment_contrast = 1.1 if day else 1.12
	e.fog_density = 0.0015 if day else 0.008
	e.fog_light_color = Color(0.82, 0.74, 0.6)
	we.environment = e
	add_child(we)
	env = e
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.5 if day else 0.25
	sun.light_color = Color(1.0, 0.9, 0.78) if day else Color(0.5, 0.56, 0.75)
	sun.rotation = Vector3(deg_to_rad(-38 if day else -48), deg_to_rad(35), 0)
	add_child(sun)
	apply_quality(e, sun, str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high")
	# Particles land on the sand instead of falling through it.
	var pc := GPUParticlesCollisionBox3D.new()
	pc.size = Vector3(RADIUS * 2.0 + 4.0, 1.0, RADIUS * 2.0 + 4.0)
	pc.position = Vector3(0, -0.5, 0)
	add_child(pc)
	# Sand: raked grain and the odd pebble, from noise.
	var sand := MeshInstance3D.new()
	var plane := CylinderMesh.new()
	plane.top_radius = RADIUS
	plane.bottom_radius = RADIUS
	plane.height = 0.02
	plane.radial_segments = 96
	plane.material = sand_material()
	sand.mesh = plane
	sand.position = Vector3(0, -0.01, 0)
	add_child(sand)
	_build_walls()
	_build_torches(day)
	var atm := Atmosphere.new()
	add_child(atm)
	atm.build(self, day, str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high")

## The sand as 10 cm voxels seen from above (art/textures/sand_voxel.png, 32 m across, one
## texel a voxel): laid on in world space, unfiltered so every voxel stays crisp. Falls back to
## the old raked sand when the voxel texture is missing.
static func sand_material() -> StandardMaterial3D:
	var tex := load_texture("res://art/textures/sand_voxel.png")
	if tex == null:
		var old := surface_material("sand", 0.45, 1.0)
		old.albedo_color = Color(1.0, 0.97, 0.93)
		old.normal_scale = 0.9
		return old
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 32.0
	m.uv1_offset = Vector3(0.5, 0.5, 0.5)
	m.albedo_color = Color(0.74, 0.74, 0.74)   # a shade down: bright sand under a high sun glared
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.97
	m.metallic_specular = 0.25   # (Godot 4's name: "specular" was the 3.x one and did nothing)
	return m

## The sky: a shader with drifting clouds and the sun's glare; at night a photographed starfield.
static func sky_material(day: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sky.gdshader")
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.012
	n.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = n
	m.set_shader_parameter("clouds_noise", nt)
	if day:
		m.set_shader_parameter("night", 0.0)
		m.set_shader_parameter("top_color", Color(0.28, 0.47, 0.78))
		m.set_shader_parameter("horizon_color", Color(0.88, 0.8, 0.68))
	else:
		m.set_shader_parameter("night", 1.0)
		m.set_shader_parameter("top_color", Color(0.01, 0.015, 0.04))
		m.set_shader_parameter("horizon_color", Color(0.06, 0.07, 0.13))
		m.set_shader_parameter("ground_color", Color(0.03, 0.03, 0.04))
		m.set_shader_parameter("cover", 0.3)
		m.set_shader_parameter("stars", load_texture("res://art/sky/night_stars.jpg"))
	return m

## A texture from art/: the imported resource, or (in a checkout that was never opened in the
## editor) the image file itself.
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static var _surfaces := {}
## A tiling surface from art/textures (sand, stone), laid on in world space so it never
## stretches: `per_m` repeats a metre.
static func surface_material(name_: String, per_m: float, rough: float) -> StandardMaterial3D:
	var key := "%s:%.3f" % [name_, per_m]
	if _surfaces.has(key):
		return _surfaces[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load_texture("res://art/textures/%s_albedo.png" % name_)
	var nt := load_texture("res://art/textures/%s_normal.png" % name_)
	if nt:
		m.normal_enabled = true
		m.normal_texture = nt
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_m
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_surfaces[key] = m
	return m

## A tiling noise texture: colour between `a` and `b`, or a normal map.
static func _noise_texture(freq: float, a: Color, b: Color, seed_: int, normal := false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = 4.0
	else:
		var g := Gradient.new()
		g.set_color(0, b)
		g.set_color(1, a)
		t.color_ramp = g
	return t

## Braziers on the podium all round: a fire, a warm light that flickers.
func _build_torches(day: bool) -> void:
	var bowl_mat := StandardMaterial3D.new()
	bowl_mat.albedo_color = Color(0.25, 0.2, 0.16)
	bowl_mat.metallic = 0.7
	bowl_mat.roughness = 0.4
	for i in 8:
		var a := (i + 0.5) / 8.0 * TAU
		var p := Vector3(sin(a) * (RADIUS - 0.6), 0.0, cos(a) * (RADIUS - 0.6))
		if VoxelArt.place(self, "brazier", p, a + PI) == null:
			var stand := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.28
			cm.bottom_radius = 0.06
			cm.height = 1.5
			cm.material = bowl_mat
			stand.mesh = cm
			add_child(stand)
			stand.position = p + Vector3(0, 0.75, 0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 1.2 if day else 3.0
		l.omni_range = 5.0 if day else 8.0
		l.shadow_enabled = not day
		l.light_volumetric_fog_energy = 2.0
		add_child(l)
		l.position = p + Vector3(0, 1.85, 0)
		torches.append(l)
		var holder := Node3D.new()
		add_child(holder)
		holder.position = p + Vector3(0, 1.55, 0)
		if Fx.current:
			var f := Fx.current.emitter("brazier", holder, 60, 0.18)
			if f:
				f.emitting = true
			var sm := Fx.current.emitter("smoke", holder, 8, 0.1)
			if sm:
				sm.emitting = true

func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in torches.size():
		var l: OmniLight3D = torches[i]
		l.light_energy = l.light_energy * 0.8 + 0.2 * ((1.2 if theme != "night" else 3.0) * (0.85 + 0.15 * sin(t * 11.0 + i * 1.7) + 0.08 * sin(t * 23.0 + i)))

## The wall: a painted podium ring with banners, then tiers of stands and an arcade.
## True once the voxel bowl (art/voxel/arena.glb) is in: the wall, the stands with their aisles,
## the gatehouses, the Emperor's box and the arcade, all one model.
var voxel := false

func _build_walls() -> void:
	var bowl := VoxelArt.make("arena")
	if bowl:
		bowl.name = "Bowl"
		add_child(bowl)
		voxel = true
		_build_props()
		_build_debris()
		_build_crowd()
		return
	# Without it, the old wall: a painted podium ring with banners, then tiers of stands and an arcade.
	var wall_mat := surface_material("stone", 0.24, 0.9)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.55, 0.12, 0.1)
	var stand_mat: StandardMaterial3D = surface_material("stone", 0.6, 0.92).duplicate()
	stand_mat.albedo_color = Color(0.88, 0.84, 0.76)
	for i in 72:
		var a := float(i) / 72.0 * TAU
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TAU * (RADIUS + 0.4) / 72.0 + 0.05, 2.0, 0.8)
		bm.material = wall_mat
		seg.mesh = bm
		seg.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * (RADIUS + 0.4), 1.0, cos(a) * (RADIUS + 0.4)))
		add_child(seg)
		if i % 6 == 0:
			var ban := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.9, 1.2, 0.05)
			bb.material = band_mat
			ban.mesh = bb
			ban.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * (RADIUS - 0.02), 1.1, cos(a) * (RADIUS - 0.02)))
			add_child(ban)
		for t in 6:
			var tier := MeshInstance3D.new()
			var tb := BoxMesh.new()
			var rr := RADIUS + 1.4 + t * 1.3
			tb.size = Vector3(TAU * rr / 72.0 + 0.05, 0.7, 1.3)
			tb.material = stand_mat
			tier.mesh = tb
			tier.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * rr, 2.2 + t * 0.7, cos(a) * rr))
			add_child(tier)
	_build_crowd()

## A crowd of little voxel people in the stands (one MultiMesh, animated by a shader): heads,
## tunics, arms that go up when the fight is worth watching.
var crowd_mat: ShaderMaterial
var excitement := 0.2

static func _spectator_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := func(c: Vector3, h: Vector3, tag: float, shade: float) -> void:
		var faces := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
			[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]]
		for f in faces:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var o := c + n * h
			var du := u * h
			var dv := v * h
			var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
			# A baked shade (UV2.y): lit from above, shadowed below, darker toward the box's foot.
			var face := 1.0 if n.y > 0.5 else (0.6 if n.y < -0.5 else 0.86)
			# Wound clockwise, Godot's front face (the other way round every box was inside out:
			# its near faces culled, the crowd looked see-through).
			for idx in [0, 2, 1, 0, 3, 2]:
				var low: float = 0.82 if (q[idx] as Vector3).y < c.y else 1.0
				st.set_normal(n)
				st.set_color(Color(1, 1, 1))
				st.set_uv2(Vector2(tag, face * low * shade))
				st.add_vertex(q[idx])
	box.call(Vector3(0, 0.3, 0), Vector3(0.14, 0.17, 0.09), 0.0, 1.0)            # tunic
	box.call(Vector3(0, 0.6, 0), Vector3(0.09, 0.1, 0.09), 1.0, 1.0)             # head
	# Arms sunk a little into the tunic at the shoulder (a centimetre off it, they hung in the air;
	# flush, they would flicker against it).
	box.call(Vector3(-0.175, 0.31, 0), Vector3(0.04, 0.15, 0.05), 2.0, 1.0)      # arms
	box.call(Vector3(0.175, 0.31, 0), Vector3(0.04, 0.15, 0.05), 3.0, 1.0)
	box.call(Vector3(0, 0.07, 0.04), Vector3(0.12, 0.07, 0.1), 4.0, 1.0)         # legs
	# Every box laid over another stands clear of it by a centimetre or more: faces in the same
	# plane (the hair's front on the face, a belt flush with the tunic) fought over which was
	# in front, and the crowd flickered.
	box.call(Vector3(0, 0.69, 0.0), Vector3(0.105, 0.03, 0.105), 5.0, 1.0)       # hair
	box.call(Vector3(0, 0.6, -0.085), Vector3(0.105, 0.055, 0.03), 5.0, 1.0)     # (below the top's, not into it)
	box.call(Vector3(0, 0.74, 0), Vector3(0.14, 0.012, 0.14), 6.0, 1.0)          # hat
	box.call(Vector3(0, 0.775, 0), Vector3(0.08, 0.03, 0.08), 6.0, 1.0)
	box.call(Vector3(0, 0.17, 0), Vector3(0.155, 0.02, 0.105), 7.0, 1.0)         # belt
	box.call(Vector3(-0.035, 0.615, 0.096), Vector3(0.016, 0.012, 0.004), 8.0, 1.0)   # eyes
	box.call(Vector3(0.035, 0.615, 0.096), Vector3(0.016, 0.012, 0.004), 8.0, 1.0)
	box.call(Vector3(0.06, 0.34, 0.097), Vector3(0.05, 0.15, 0.005), 9.0, 1.0)   # sash
	return st.commit()

func set_excitement(x: float) -> void:
	excitement = clampf(x, 0.0, 1.0)

## Whether a spectator can sit at angle a on the tier at radius rr of the voxel bowl: not on the
## aisles' stairs, the gatehouses or the Emperor's box.
static func _seat_free(a: float, rr: float) -> bool:
	var step := deg_to_rad(30.0)
	if absf(fposmod(a - deg_to_rad(15.0) + step / 2.0, step) - step / 2.0) * rr < 0.55:
		return false
	var p := Vector2(sin(a) * rr, cos(a) * rr)
	if absf(p.x) > 13.0 and absf(p.y) < 2.7 and rr < 19.0:
		return false
	if absf(p.x) < 2.9 and p.y > 15.0 and rr < 19.5:
		return false
	return true

func _build_crowd() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var mesh := _spectator_mesh()
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	crowd_mat.set_shader_parameter("excitement", 0.2)
	mesh.surface_set_material(0, crowd_mat)
	mm.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var skins := [Color(0.88, 0.71, 0.55), Color(0.78, 0.56, 0.37), Color(0.6, 0.39, 0.25), Color(0.43, 0.27, 0.16), Color(0.95, 0.79, 0.65)]
	var tunics := [Color(0.85, 0.82, 0.74), Color(0.62, 0.15, 0.12), Color(0.2, 0.3, 0.55), Color(0.75, 0.6, 0.3), Color(0.35, 0.45, 0.25), Color(0.5, 0.3, 0.55), Color(0.9, 0.9, 0.86)]
	var list := []
	for t in 6:
		var rr := RADIUS + 1.4 + t * 1.3
		# A seat each wide enough for a man and his arms (packed closer, the arms of
		# neighbours went through each other).
		var n := int(TAU * rr / 0.62)
		for i in n:
			if rng.randf() < 0.18:
				continue
			var a := float(i) / n * TAU + rng.randf() * 0.012
			var sc := 1.1 + rng.randf() * 0.15
			if voxel and not _seat_free(a, rr):
				continue
			# Facing the sand (the mesh looks along +z).
			var basis := Basis(Vector3.UP, a + PI).scaled(Vector3.ONE * sc)
			var tun: Color = tunics[rng.randi_range(0, tunics.size() - 1)]
			tun = tun.lerp(Color.from_hsv(rng.randf(), 0.5, 0.6), 0.25)
			var sk: Color = skins[rng.randi_range(0, skins.size() - 1)]
			var seat_y := (2.6 if voxel else 2.55) + t * 0.7
			list.append([Transform3D(basis, Vector3(sin(a) * (rr - 0.1), seat_y, cos(a) * (rr - 0.1))), tun, Color(sk.r, sk.g, sk.b, rng.randf())])
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
		mm.set_instance_custom_data(i, list[i][2])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)
	_build_upper()

## Above and round the stands: an arcade of columns, the striped awning (velarium), flags on
## poles, the Emperor's box under a purple canopy, and the two great gates.
func _build_upper() -> void:
	var stone: StandardMaterial3D = surface_material("stone", 0.5, 0.9)
	var top_r := RADIUS + 1.4 + 5 * 1.3 + 1.2
	var cols := 48
	var cm := BoxMesh.new()
	cm.size = Vector3(0.45, 3.2, 0.45)
	cm.material = stone
	var bm := BoxMesh.new()
	bm.size = Vector3(TAU * top_r / cols + 0.05, 0.5, 0.6)
	bm.material = stone
	for i in (0 if voxel else cols):
		var a := float(i) / cols * TAU
		var col := MeshInstance3D.new()
		col.mesh = cm
		add_child(col)
		col.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * top_r, 7.4, cos(a) * top_r))
		var beam := MeshInstance3D.new()
		beam.mesh = bm
		add_child(beam)
		var ab := a + PI / cols
		beam.transform = Transform3D(Basis(Vector3.UP, ab), Vector3(sin(ab) * top_r, 9.2, cos(ab) * top_r))
	# The velarium: striped cloth slanting in from the top of the arcade, rippling.
	var flag_shader: Shader = load("res://shaders/flag.gdshader")
	var aw := ShaderMaterial.new()
	aw.shader = flag_shader
	aw.set_shader_parameter("color_a", Color(0.86, 0.8, 0.66))
	aw.set_shader_parameter("color_b", Color(0.62, 0.14, 0.1))
	aw.set_shader_parameter("stripes", 6.0)
	aw.set_shader_parameter("wave", 0.12)
	if voxel:
		aw.set_shader_parameter("cells", Vector2(45, 60))
	for i in 24:
		if i % 4 == 3:
			continue
		var a := (i + 0.5) / 24.0 * TAU
		var pm := PlaneMesh.new()
		pm.size = Vector2(4.5, TAU * top_r / 24.0 * 0.95)
		pm.subdivide_width = 8
		pm.material = aw
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var mid := top_r - 2.0
		mi.transform = Transform3D(Basis(Vector3.UP, a + PI / 2.0) * Basis(Vector3(0, 0, 1), deg_to_rad(-14)), Vector3(sin(a) * mid, 9.9, cos(a) * mid))
	# Flags on poles along the top.
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var base := Vector3(sin(a) * (top_r + 0.3), 10.7, cos(a) * (top_r + 0.3))
		if not voxel:
			var pole := MeshInstance3D.new()
			var pmesh := CylinderMesh.new()
			pmesh.top_radius = 0.04
			pmesh.bottom_radius = 0.05
			pmesh.height = 2.6
			pole.mesh = pmesh
			add_child(pole)
			pole.position = base
		var fm := ShaderMaterial.new()
		fm.shader = flag_shader
		fm.set_shader_parameter("color_a", [Color(0.62, 0.12, 0.1), Color(0.45, 0.2, 0.5), Color(0.8, 0.62, 0.2)][i % 3])
		fm.set_shader_parameter("color_b", Color(0.95, 0.8, 0.35))
		fm.set_shader_parameter("wave", 0.15)
		if voxel:
			fm.set_shader_parameter("cells", Vector2(12, 7))
		var fl := MeshInstance3D.new()
		var fq := PlaneMesh.new()
		fq.size = Vector2(1.2, 0.7)
		fq.subdivide_width = 6
		fq.orientation = PlaneMesh.FACE_Z
		fq.material = fm
		fl.mesh = fq
		add_child(fl)
		fl.position = base + Vector3(0.6 * cos(a), 0.9, -0.6 * sin(a))
		fl.rotation.y = a + PI / 2.0
	# The Emperor's box: a raised platform with a purple canopy, on the north side.
	var purple := StandardMaterial3D.new()
	purple.albedo_color = Color(0.42, 0.12, 0.4)
	purple.roughness = 0.8
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.72, 0.3)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var box_p := Vector3(0, 3.4, RADIUS + 2.2)
	if not voxel:
		var plat := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(4.5, 0.4, 2.6)
		pbm.material = stone
		plat.mesh = pbm
		add_child(plat)
		plat.position = box_p
		var can := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(4.8, 0.15, 2.9)
		cbm.material = purple
		can.mesh = cbm
		add_child(can)
		can.position = box_p + Vector3(0, 2.6, 0)
		for sx in [-2.2, 2.2]:
			for sz in [-1.2, 1.2]:
				var post := MeshInstance3D.new()
				var pc := BoxMesh.new()
				pc.size = Vector3(0.18, 2.6, 0.18)
				pc.material = gold
				post.mesh = pc
				add_child(post)
				post.position = box_p + Vector3(sx, 1.3, sz)
	var drape := ShaderMaterial.new()
	drape.shader = flag_shader
	drape.set_shader_parameter("color_a", Color(0.42, 0.12, 0.4))
	drape.set_shader_parameter("color_b", Color(0.9, 0.72, 0.3))
	drape.set_shader_parameter("stripes", 1.2)
	drape.set_shader_parameter("wave", 0.03)
	if voxel:
		drape.set_shader_parameter("cells", Vector2(46, 14))
	var dm := MeshInstance3D.new()
	var dq := PlaneMesh.new()
	dq.size = Vector2(4.6, 1.4)
	dq.orientation = PlaneMesh.FACE_Z
	dq.material = drape
	dm.mesh = dq
	add_child(dm)
	dm.position = box_p + Vector3(0, -0.7, -1.32)
	# Two great gates in the wall, east and west.
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = _noise_texture(0.2, Color(0.62, 0.42, 0.25), Color(0.4, 0.26, 0.15), 31)
	wood.roughness = 0.85
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.22, 0.21, 0.2)
	iron.metallic = 0.8
	iron.roughness = 0.45
	for gx in [-1.0, 1.0]:
		# Each gate is a door on a hinge at its north post (it swings open when a wave comes in).
		var door := Node3D.new()
		add_child(door)
		door.position = Vector3(gx * (RADIUS - 0.05), 0, -1.3)
		gates[int(gx)] = door
		if voxel and VoxelArt.place(door, "gate_door", Vector3.ZERO) != null:
			continue
		# Planks of slightly different shades, two iron bands with studs.
		for k in 6:
			var plank := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.24, 2.4 - (k % 2) * 0.06, 0.42)
			var pmat: StandardMaterial3D = wood.duplicate()
			pmat.albedo_color = Color(1, 1, 1).darkened(0.08 * ((k * 7) % 3))
			pm.material = pmat
			plank.mesh = pm
			door.add_child(plank)
			plank.position = Vector3(0, 1.2, 0.22 + k * 0.435)
		for by in [0.55, 1.85]:
			var band := MeshInstance3D.new()
			var bdm := BoxMesh.new()
			bdm.size = Vector3(0.28, 0.12, 2.62)
			bdm.material = iron
			band.mesh = bdm
			door.add_child(band)
			band.position = Vector3(-gx * 0.02, by, 1.3)
			for k in 6:
				var stud := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.035
				sm.height = 0.07
				sm.material = iron
				stud.mesh = sm
				door.add_child(stud)
				stud.position = Vector3(-gx * 0.17, by, 0.22 + k * 0.435)
		var arch := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.6, 0.5, 3.4)
		am.material = stone
		arch.mesh = am
		add_child(arch)
		arch.position = Vector3(gx * (RADIUS + 0.1), 2.55, 0)

## The voxel bowl's furnishings, all out of reach of the fight: statues on the arcade and on the
## gatehouses, the Emperor's throne, and in each gate tunnel a rack of spears, jars and crates
## with a torch burning deep inside.
func _build_props() -> void:
	for i in 8:
		var a := deg_to_rad(15.0 + 45.0 * i)
		var p := Vector3(sin(a) * 24.1, 10.0, cos(a) * 24.1)
		VoxelArt.place(self, "statue", p, VoxelArt.facing_centre(p))
	for gx in [-1.0, 1.0]:
		for gz in [-1.9, 1.9]:
			VoxelArt.place(self, "statue", Vector3(gx * 15.6, 4.0, gz), -gx * PI / 2.0)
		VoxelArt.solid(VoxelArt.place(self, "weapon_rack", Vector3(gx * 16.9, 0, -1.12), 0.0))
		VoxelArt.solid(VoxelArt.place(self, "amphora", Vector3(gx * 16.4, 0, 1.08), 0.3), 0.05)
		VoxelArt.solid(VoxelArt.place(self, "amphora_wide", Vector3(gx * 16.9, 0, 1.05), 1.1), 0.05)
		VoxelArt.solid(VoxelArt.place(self, "crate", Vector3(gx * 17.7, 0, 0.98), 0.2), 0.03)
		VoxelArt.place(self, "crate", Vector3(gx * 17.75, 0.6, 1.0), 0.9)
		var tl := OmniLight3D.new()
		tl.light_color = Color(1.0, 0.55, 0.25)
		tl.light_energy = 1.6
		tl.omni_range = 3.6
		tl.omni_attenuation = 1.4
		add_child(tl)
		tl.position = Vector3(gx * 18.0, 1.9, 0.0)
	for sx in [-2.9, 2.9]:
		VoxelArt.place(self, "statue", Vector3(sx, 2.6, 16.4), PI)
	VoxelArt.place(self, "throne", Vector3(0, 3.6, 17.9), PI)
	VoxelArt.place(self, "amphora", Vector3(-1.9, 3.6, 18.2), 0.0)
	VoxelArt.place(self, "amphora_wide", Vector3(1.9, 3.6, 18.2), 0.5)

## What earlier fights left at the foot of the wall, for the eye only (nothing here collides, and
## it all stands in the last half metre of sand, out of the way of the fight): spears stuck in the
## sand at a lean, broken shields propped against the wall, a helmet on its side. Clear of the
## two gates and of the Emperor's box.
const DEBRIS := [
	["spear", 25.0, 0.22], ["shield", 38.0, 0.0], ["spear", 52.0, -0.3], ["helmet", 70.0, 0.0],
	["shield", 128.0, 0.0], ["spear", 141.0, 0.25], ["spear", 150.0, -0.18], ["helmet", 166.0, 0.0],
	["spear", 205.0, 0.3], ["shield", 222.0, 0.0], ["helmet", 238.0, 0.0], ["spear", 300.0, -0.25],
	["shield", 316.0, 0.0], ["spear", 330.0, 0.2],
]

func _build_debris() -> void:
	var wood := _flat_material(Color(0.42, 0.29, 0.17))
	var iron := _flat_material(Color(0.5, 0.5, 0.52), 0.6)
	var bronze := _flat_material(Color(0.62, 0.42, 0.2), 0.7)
	var red := _flat_material(Color(0.55, 0.12, 0.09))
	for d in DEBRIS:
		var a := deg_to_rad(float(d[1]))
		var out := Vector3(sin(a), 0, cos(a))
		var side := Vector3(out.z, 0, -out.x)
		var n := Node3D.new()
		add_child(n)
		n.position = out * (RADIUS - 0.35)
		n.basis = Basis.looking_at(-out, Vector3.UP)
		match String(d[0]):
			"spear":
				# Driven into the sand at a lean, the head up.
				n.rotate(side, float(d[2]))
				_box(n, wood, Vector3(0.05, 1.7, 0.05), Vector3(0, 0.7, 0))
				_box(n, iron, Vector3(0.09, 0.24, 0.025), Vector3(0, 1.64, 0))
			"shield":
				# A round shield propped on its rim against the wall, a wedge of it split off.
				var sh := Node3D.new()
				n.add_child(sh)
				sh.position = Vector3(0, 0.4, 0.22)
				sh.rotation = Vector3(deg_to_rad(-72.0), 0, 0)
				# (The sectors overlap: the bronze ones a hair thicker, so no two faces share a
				# plane and the red and the bronze do not flicker through each other.)
				for k in 7:
					var ang := k * TAU / 8.0
					_box(sh, red if k % 2 == 0 else bronze, Vector3(0.26, 0.05 if k % 2 == 0 else 0.058, 0.26), Vector3(cos(ang) * 0.2, 0, sin(ang) * 0.2))
				_box(sh, bronze, Vector3(0.14, 0.08, 0.14), Vector3.ZERO)
			"helmet":
				# On its side in the sand, the crest to the wall.
				var hm := Node3D.new()
				n.add_child(hm)
				hm.position = Vector3(0, 0.13, -0.2)
				hm.rotation = Vector3(0, 0, deg_to_rad(80.0))
				_box(hm, bronze, Vector3(0.26, 0.2, 0.28), Vector3.ZERO)
				_box(hm, bronze, Vector3(0.3, 0.04, 0.32), Vector3(0, -0.1, 0))
				_box(hm, red, Vector3(0.05, 0.12, 0.26), Vector3(0, 0.15, 0))

func _flat_material(c: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.6 if metal > 0.0 else 0.9
	return m

func _box(parent: Node3D, mat: Material, size: Vector3, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = at
	parent.add_child(mi)

## Swings the east (1) or west (-1) gate open inward for `hold` seconds, then shut again.
var gates := {}
func open_gate(side: int, hold := 3.5) -> void:
	var door: Node3D = gates.get(side)
	if door == null or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(door, "rotation:y", -float(side) * 1.45, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(door, "rotation:y", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _exit_tree() -> void:
	if crowd_mat:
		Sfx.ambience(false)

func _physics_process(_dt: float) -> void:
	if crowd_mat:
		Sfx.crowd(excitement)
		var cur: float = crowd_mat.get_shader_parameter("excitement")
		crowd_mat.set_shader_parameter("excitement", lerpf(cur, excitement, 0.02))
		excitement = maxf(0.15, excitement - _dt * 0.03)
