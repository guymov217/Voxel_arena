class_name Arena
extends Node3D
## The sand, the wall and the stands (arena.js): a 15 m ring with a wall that, for the physics,
## rises far above the stands so nothing flung sails out of the map.

const RADIUS := 15.0
const SEGMENTS := 36

var theme := "colosseum"
## The time of day and the weather the bout is fought under (only how it looks): "noon", "golden"
## (late in the day, the sun low and gold), "overcast" or "evening" (dusk: the sun down behind the
## stands, the torches lit). The host picks it (pick_sky) and tells the guests.
var time_of_day := "noon"
const SKIES := ["noon", "golden", "overcast", "evening"]

func build(theme_ := "colosseum", visuals := true, sky_ := "noon") -> void:
	theme = theme_
	time_of_day = clean_sky(sky_)
	if visuals:
		Sfx.ambience(true)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = VoxelPart.LAYER_WORLD
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	# Deep: a body driven into it is pushed back out of the top, never out of the bottom (a giant
	# came down through a metre of it).
	gb.size = Vector3(60, 20, 60)
	gs.shape = gb
	gs.position = Vector3(0, -10.0, 0)
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
	# The gatehouses' fronts stand out of the round of the wall, flat across it (the voxel bowl's:
	# the door's pillars 0.3 m nearer the middle than the wall's own stone): a man or a beast
	# pressed against the wall by a gate stood half inside a pillar (user). A slab of its own
	# for each, its face where the stone is drawn, out to where the front meets the round wall.
	for gx in [-1.0, 1.0]:
		var gate := StaticBody3D.new()
		gate.collision_layer = VoxelPart.LAYER_WORLD
		gate.collision_mask = 0
		var gcs := CollisionShape3D.new()
		var gbs := BoxShape3D.new()
		gbs.size = Vector3(0.8, 40, 2.0 * sqrt(RADIUS * RADIUS - GATE_FRONT * GATE_FRONT))
		gcs.shape = gbs
		gate.add_child(gcs)
		gate.position = Vector3(gx * (GATE_FRONT + 0.4), 19, 0)
		add_child(gate)
	if visuals:
		_build_visuals()

## How far out the gatehouses' fronts stand from the middle (east and west, flat across).
const GATE_FRONT := 14.7

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
	# (Gentler than it was: the sun's glow and bloom spread over the picture and blurred it, user.)
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.volumetric_fog_enabled = lv >= 2
	e.volumetric_fog_density = 0.0035   # air enough for the sun to show in, shafts through the arcade (more washed the colours out, user)
	e.volumetric_fog_albedo = Color(0.85, 0.76, 0.6)
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 48.0
	e.volumetric_fog_sky_affect = 0.15
	# A haze of distance on every level (next to nothing to draw): the far side of the bowl and
	# its stands a little lost in the warm air, the fight in front sharp.
	e.fog_enabled = true
	if sun_:
		sun_.shadow_enabled = true
		sun_.directional_shadow_max_distance = 40.0 if lv >= 2 else 25.0
		sun_.shadow_blur = 1.0
		sun_.light_volumetric_fog_energy = 1.1
		# The sun a disc, not a point (ultra only: it is the one thing here that costs): shadows
		# sharp at the feet, softer the further they fall from what casts them.
		sun_.light_angular_distance = 0.5 if lv >= 3 else 0.0

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
	# Warm sun, cool shade: the shadows take the blue of the open sky (by night, the moon's).
	e.ambient_light_sky_contribution = 0.75 if day else 0.55
	e.ambient_light_color = Color(0.62, 0.72, 0.9) if day else Color(0.85, 0.72, 0.55)
	# Clear and easy on the eye: the sun a little lower and softer, the exposure down a touch so
	# the sand no longer glares white, the colours kept bright (the "clear" look, E, of the
	# lighting trials: tests/lightshots.gd).
	e.ambient_light_energy = 0.6 if day else 0.27
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.8 if day else 0.88
	e.tonemap_white = 6.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05 if day else 1.08
	e.adjustment_contrast = 1.1 if day else 1.12
	# A film's grade over it all (grade_lut): the shade a touch cooler, the sunlight a touch more
	# gold, the middle tones given a little more shape. A table looked up once a pixel: free.
	e.adjustment_color_correction = grade_lut(day)
	e.fog_density = 0.005 if day else 0.008
	e.fog_light_color = Color(0.82, 0.74, 0.6)
	e.fog_aerial_perspective = 0.7 if day else 0.5   # the haze takes the sky's own colour far off
	e.fog_sun_scatter = 0.1 if day else 0.0         # (a glare over all toward the sun at more)
	e.fog_sky_affect = 0.0                            # (the sky itself clear)
	we.environment = e
	add_child(we)
	env = e
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.75 if day else 0.25
	sun.light_color = Color(1.0, 0.86, 0.7) if day else Color(0.5, 0.56, 0.75)
	sun.rotation = Vector3(deg_to_rad(-38 if day else -48), deg_to_rad(35), 0)
	add_child(sun)
	var q := str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high"
	apply_quality(e, sun, q)
	# A film's look over the picture, under the HUD (medium and up): the corners a touch darker,
	# a fine grain that moves. One quad over the screen that reads nothing back.
	if q != "low":
		var layer := CanvasLayer.new()
		layer.name = "Film"
		layer.layer = -1
		var veil := ColorRect.new()
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		# High and up, the picture is sharpened first (film_sharp: it reads the picture back,
		# one pass, so not at medium): the voxels' edges crisp again after the anti-aliasing.
		sm.shader = load("res://shaders/film_sharp.gdshader" if q == "high" or q == "ultra" else "res://shaders/film.gdshader")
		veil.material = sm
		layer.add_child(veil)
		add_child(layer)
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
	sand.name = "Sand"
	sand.mesh = plane
	sand.position = Vector3(0, -0.01, 0)
	add_child(sand)
	_build_ground_details()
	_build_walls()
	_build_torches(day)
	_build_skyline(day)
	var atm := Atmosphere.new()
	add_child(atm)
	atm.build(self, day, str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high")
	if q != "low":
		_build_reflections()
	if day and q != "low" and (time_of_day == "noon" or time_of_day == "golden"):
		_build_cloud_shadows()
	_time_of_day(e, sky.sky_material as ShaderMaterial, q)

var skyline_mat: StandardMaterial3D = null
var torch_base := 1.5   # the torches' light by day, about which they flicker (a little stronger on the wall)

## The light of the bout's time of day, over what was set up for noon (only how it looks).
func _time_of_day(e: Environment, skym: ShaderMaterial, q: String) -> void:
	if theme == "night":
		return
	match time_of_day:
		"golden":
			# Late in the day: the sun low and gold, the shadows long, the sky warm at its foot.
			sun.rotation = Vector3(deg_to_rad(-25), deg_to_rad(35), 0)
			sun.light_color = Color(1.0, 0.74, 0.48)
			sun.light_energy = 1.65
			skym.set_shader_parameter("top_color", Color(0.25, 0.39, 0.68))
			skym.set_shader_parameter("horizon_color", Color(0.98, 0.72, 0.46))
			skym.set_shader_parameter("cloud_light", Color(1.0, 0.82, 0.6))
			skym.set_shader_parameter("cloud_shade", Color(0.64, 0.52, 0.54))
			e.ambient_light_color = Color(0.72, 0.68, 0.8)
			e.fog_light_color = Color(0.92, 0.7, 0.5)
			e.volumetric_fog_albedo = Color(0.95, 0.74, 0.52)
			e.tonemap_exposure = 0.84
		"overcast":
			# A grey day: the sun a pale glow behind the cloud, the shadows soft, the colours quiet.
			sun.light_color = Color(0.93, 0.95, 1.0)
			sun.light_energy = 0.8
			sun.shadow_blur = 3.0
			skym.set_shader_parameter("top_color", Color(0.5, 0.55, 0.62))
			skym.set_shader_parameter("horizon_color", Color(0.8, 0.79, 0.76))
			skym.set_shader_parameter("cloud_light", Color(0.88, 0.88, 0.88))
			skym.set_shader_parameter("cloud_shade", Color(0.54, 0.56, 0.6))
			skym.set_shader_parameter("cover", 0.84)
			skym.set_shader_parameter("wind", 0.02)
			skym.set_shader_parameter("sun_disc", 0.12)
			e.ambient_light_energy = 0.95
			e.ambient_light_color = Color(0.8, 0.82, 0.86)
			e.fog_density = 0.007
			e.fog_light_color = Color(0.76, 0.76, 0.76)
			e.adjustment_saturation = 0.98
		"evening":
			# Dusk: the sun gone down behind the stands (it lights only their tops), the sky still
			# glowing where it set, the torches lit and burning brighter.
			sun.rotation = Vector3(deg_to_rad(-6), deg_to_rad(35), 0)
			sun.light_color = Color(1.0, 0.52, 0.36)
			sun.light_energy = 0.9
			skym.set_shader_parameter("top_color", Color(0.1, 0.14, 0.3))
			skym.set_shader_parameter("horizon_color", Color(0.95, 0.52, 0.34))
			skym.set_shader_parameter("ground_color", Color(0.18, 0.13, 0.12))
			skym.set_shader_parameter("cloud_light", Color(0.98, 0.62, 0.52))
			skym.set_shader_parameter("cloud_shade", Color(0.3, 0.25, 0.38))
			skym.set_shader_parameter("cover", 0.4)
			e.ambient_light_energy = 0.75
			e.ambient_light_color = Color(0.64, 0.62, 0.82)
			e.tonemap_exposure = 1.0
			e.fog_light_color = Color(0.52, 0.42, 0.46)
			torch_base = 2.6
			for l in torches:
				l.light_energy = torch_base
				l.omni_range = 8.0
	if skyline_mat:
		skyline_mat.albedo_color = {"golden": Color(1.0, 0.88, 0.74), "overcast": Color(0.84, 0.86, 0.88), "evening": Color(0.42, 0.4, 0.54)}.get(time_of_day, Color.WHITE)
	if q != "low" and (time_of_day == "noon" or time_of_day == "golden"):
		_build_light_shafts(time_of_day == "golden")

## Shafts of sunlight through the gaps in the velarium, slits between its sails and the two
## furled ones, on the sun's side, falling in over the stands; dust turning in each. Drawing
## only: faint, gone before they reach anything.
func _build_light_shafts(golden: bool) -> void:
	var top_r := RADIUS + 1.4 + 5 * 1.3 + 1.2
	var rm := (top_r + 0.3 + RADIUS + 3.6) * 0.5
	var dir := -sun.basis.z.normalized()
	var hd := Vector2(dir.x, dir.z).normalized()
	var shader: Shader = load("res://shaders/light_shaft.gdshader")
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color", Color(1.0, 0.8, 0.55) if golden else Color(1.0, 0.93, 0.8))
	mat.set_shader_parameter("strength", 0.11 if golden else 0.08)
	var shafts := []   # [angle, width]
	for i in 20:
		shafts.append([float(i) / 20.0 * TAU, 0.4])
	for i in [4, 14]:
		for k in 3:
			shafts.append([(i + 0.25 + k * 0.25) / 20.0 * TAU, 1.3])
	var dust := []
	var drng := RandomNumberGenerator.new()
	drng.seed = 77
	for s in shafts:
		var a: float = s[0]
		var inward := -Vector2(sin(a), cos(a))
		if inward.dot(hd) < 0.55:
			continue
		var start := Vector3(sin(a) * rm, 11.4, cos(a) * rm)
		var length := minf(24.0, (start.y - 2.5) / maxf(0.2, -dir.y))
		var w: float = s[1]
		var x := dir.cross(Vector3.UP).normalized()
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = w + 1.0
		mi.transform = Transform3D(Basis(x * w, dir * length, x.cross(dir)), start)
		add_child(mi)
		# Dust turning in it.
		for k in (18 if w < 1.0 else 30):
			dust.append(start + dir * length * drng.randf_range(0.08, 0.75) + x * w * drng.randf_range(-0.4, 0.4) + x.cross(dir) * w * drng.randf_range(-0.4, 0.4))
	_specks("ShaftDust", dust, Color(1.0, 0.86, 0.62, 0.6) if golden else Color(1.0, 0.95, 0.85, 0.5), 0.0, 7.0, 0.09, 0.02, 77)

## Specks of light at `points` drawn by a shader (shaders/motes.gdshader): embers that `rise`
## and fade, or (rise 0) dust that drifts and glints. One MultiMesh, nothing simulated, and no
## particle system: one draws on the game's own dice when it is made (Godot seeds it so), and the
## fight's dice must stay the fight's.
func _specks(name_: String, points: Array, col: Color, rise: float, life: float, sway: float, size: float, seed_: int) -> void:
	if points.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 0.0))
	mm.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 40, 80))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/motes.gdshader")
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("rise", rise)
	mat.set_shader_parameter("life", life)
	mat.set_shader_parameter("sway", sway)
	mat.set_shader_parameter("size", size)
	var mi := MultiMeshInstance3D.new()
	mi.name = name_
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## A time of day for a bout, at random, noon the most often; noon always for the yard and the
## training ground. Its own dice: nothing the fight draws on is touched.
static func pick_sky(mode: String) -> String:
	if mode == "yard" or mode == "training":
		return "noon"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var r := rng.randf()
	return "noon" if r < 0.45 else ("golden" if r < 0.7 else ("overcast" if r < 0.85 else "evening"))

## A time of day as a guest was told it, made safe: one of SKIES, or noon.
static func clean_sky(v) -> String:
	var s := str(v) if v is String else "noon"
	return s if SKIES.has(s) else "noon"

## Rome round the arena, far off in the haze (drawing only): hills with cypresses and umbrella
## pines, the roofs of the city on them and between them, temples on the heights, an aqueduct
## striding across the plain. Boxes, one MultiMesh, no shadows: next to nothing to draw. From the
## sand it shows through the arches of the arcade; from the stands and above, over its top.
func _build_skyline(day: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var boxes := []   # [centre, size, yaw, colour]
	var green := [Color(0.42, 0.46, 0.26), Color(0.5, 0.49, 0.29), Color(0.37, 0.41, 0.24)]
	var walls := [Color(0.86, 0.76, 0.58), Color(0.8, 0.66, 0.47), Color(0.9, 0.85, 0.74), Color(0.74, 0.56, 0.4)]
	var roofs := [Color(0.62, 0.3, 0.18), Color(0.55, 0.26, 0.16), Color(0.68, 0.37, 0.22)]
	var cypress := Color(0.16, 0.24, 0.13)
	var marble := Color(0.92, 0.9, 0.84)
	# Seven hills, each a mound of stepped slabs, with the city's roofs and trees on its flanks.
	var hills := []
	for i in 7:
		var a := (i + rng.randf_range(-0.25, 0.25)) / 7.0 * TAU
		var d := rng.randf_range(200.0, 290.0)
		var r := rng.randf_range(45.0, 80.0)
		var h := rng.randf_range(24.0, 48.0)
		var c := Vector3(sin(a) * d, 0.0, cos(a) * d)
		hills.append([c, r, h])
		var g: Color = green[i % green.size()]
		for l in 6:
			var k := float(l) / 6.0
			var rl := r * pow(1.0 - k, 0.7)
			for j in 3:
				boxes.append([c + Vector3(0, k * h + h / 12.0, 0), Vector3(rl * 2.0, h / 6.0 + 0.5, rl * 1.25), a + j * PI / 3.0, g.darkened(0.04 * l)])
		# Trees and houses up its sides.
		for j in 26:
			var ta := rng.randf() * TAU
			var tr := sqrt(rng.randf()) * r * 0.75
			var lift := h * pow(1.0 - tr / r, 0.7)
			var p := c + Vector3(sin(ta) * tr, lift, cos(ta) * tr)
			if rng.randf() < 0.5:
				var th := rng.randf_range(7.0, 11.0)
				boxes.append([p + Vector3(0, th * 0.5, 0), Vector3(1.6, th, 1.6), 0.0, cypress])
			else:
				var w := rng.randf_range(6.0, 12.0)
				var bh := rng.randf_range(5.0, 10.0)
				var col: Color = walls[rng.randi_range(0, walls.size() - 1)]
				boxes.append([p + Vector3(0, bh * 0.5, 0), Vector3(w, bh, w * 0.7), ta, col])
				boxes.append([p + Vector3(0, bh + 0.6, 0), Vector3(w * 1.1, 1.2, w * 0.8), ta, roofs[rng.randi_range(0, roofs.size() - 1)]])
	# Temples on three of the heights: a podium, the columns, the roof with its pediment.
	for i in [0, 2, 5]:
		var c: Vector3 = hills[i][0]
		var top: float = hills[i][2]
		var face := atan2(-c.x, -c.z)   # toward the arena
		var bas := Basis(Vector3.UP, face)
		var at := c + Vector3(0, top, 0)
		boxes.append([at + Vector3(0, 1.5, 0), Vector3(22, 3, 34), face, marble.darkened(0.08)])
		for cx in 6:
			for side in [-1.0, 1.0]:
				var off := bas * Vector3(-8.75 + cx * 3.5, 0, side * 14.0)
				boxes.append([at + off + Vector3(0, 9.0, 0), Vector3(1.4, 12, 1.4), face, marble])
		boxes.append([at + Vector3(0, 9.0, 0), Vector3(14, 12, 24), face, marble.darkened(0.12)])
		boxes.append([at + Vector3(0, 16.0, 0), Vector3(22, 2, 34), face, marble])
		boxes.append([at + Vector3(0, 18.2, 0), Vector3(16, 2.4, 34), face, roofs[0]])
		boxes.append([at + Vector3(0, 20.0, 0), Vector3(8, 1.6, 34), face, roofs[1]])
	# The city between the hills: blocks of flats (insulae) in rings round the bowl.
	for i in 140:
		var a := rng.randf() * TAU
		var d := rng.randf_range(95.0, 190.0)
		var p := Vector3(sin(a) * d, 0, cos(a) * d)
		var w := rng.randf_range(8.0, 16.0)
		var bh := rng.randf_range(9.0, 24.0) * (1.0 - (d - 95.0) / 300.0)
		var col: Color = walls[rng.randi_range(0, walls.size() - 1)]
		boxes.append([p + Vector3(0, bh * 0.5, 0), Vector3(w, bh, w * rng.randf_range(0.6, 1.0)), a, col])
		boxes.append([p + Vector3(0, bh + 0.7, 0), Vector3(w * 1.08, 1.4, w * 0.8), a, roofs[rng.randi_range(0, roofs.size() - 1)]])
		if rng.randf() < 0.25:
			var pt := p + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			boxes.append([pt + Vector3(0, 6.0, 0), Vector3(1.0, 12, 1.0), 0.0, Color(0.32, 0.24, 0.16)])
			boxes.append([pt + Vector3(0, 12.5, 0), Vector3(9, 2.5, 9), rng.randf() * TAU, Color(0.2, 0.3, 0.16)])
	# An aqueduct crossing the plain: piers, the arches' tops, the channel along them.
	var aq_a := 2.3
	var aq0 := Vector3(sin(aq_a) * 150.0, 0, cos(aq_a) * 150.0)
	var aq_dir := Vector3(cos(aq_a), 0, -sin(aq_a))
	var stone := Color(0.78, 0.68, 0.52)
	for k in range(-16, 17):
		var p := aq0 + aq_dir * (k * 12.0)
		var yaw := atan2(aq_dir.x, aq_dir.z)
		boxes.append([p + Vector3(0, 13.0, 0), Vector3(3.0, 26.0, 3.0), yaw, stone])
		boxes.append([p + aq_dir * 6.0 + Vector3(0, 24.5, 0), Vector3(3.0, 3.0, 9.0), yaw, stone.darkened(0.06)])
	boxes.append([aq0 + Vector3(0, 27.5, 0), Vector3(3.4, 3.0, 33 * 12.0), atan2(aq_dir.x, aq_dir.z), stone.darkened(0.1)])
	# The plain it all stands on, out to the hills (under the arena's own floor, which hides it inside).
	boxes.append([Vector3(0, -0.6, 0), Vector3(760.0, 1.0, 760.0), 0.0, Color(0.6, 0.53, 0.38)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # (the colours as written: read as linear they came out washed pale)
	mat.roughness = 1.0
	bm.material = mat
	skyline_mat = mat
	mm.mesh = bm
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var b: Array = boxes[i]
		# (Turned, then sized along its own sides: Basis.scaled sizes along the world's axes, and a
		# turned box came out skewed.)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(b[2])) * Basis.from_scale(b[1]), b[0]))
		var col: Color = b[3]
		mm.set_instance_color(i, col if day else col.darkened(0.55))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Skyline"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## What the arena itself is drawn with is marked (a layer of its own, STATIC_LAYER) so that the
## reflection taken of it holds the bowl and nothing that moves in it.
const STATIC_LAYER := 1 << 2

## Metal shows the arena round it: a reflection of the bowl taken once (the sand, the stone, the
## stands and the cloth; no one standing in it, they are not on STATIC_LAYER), and in it every
## blade, helmet and plate catches the warm stone and the crowd instead of only the sky (a blade
## turned up to the light went the blue of the open sky). Taken once, at the start: it costs
## nothing after.
func _build_reflections() -> void:
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is VisualInstance3D and not (n is ReflectionProbe) and not (n is Decal):
			(n as VisualInstance3D).layers |= STATIC_LAYER
	var rp := ReflectionProbe.new()
	rp.name = "Reflections"
	rp.size = Vector3(RADIUS * 2.0 + 2.0, 14.0, RADIUS * 2.0 + 2.0)
	rp.max_distance = 90.0
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	rp.cull_mask = STATIC_LAYER
	rp.enable_shadows = true
	add_child(rp)
	rp.position = Vector3(0, 1.6, 0)

## The shadows of the clouds the sky's wind carries over (by day): soft dark patches drifting
## across the sand, the stands and the men, one great decal moved a little every frame. When it
## has gone as far as it may, it fades out and comes back in from the other side.
const CLOUD_SPAN := 260.0
const CLOUD_TRAVEL := 90.0
const CLOUD_WIND := Vector3(0.45, 0.0, 0.17)
const CLOUD_DARK := 0.5
var cloud_shade: Decal = null
var _cloud_fade := 1.0
var _cloud_back := false

func _build_cloud_shadows() -> void:
	cloud_shade = Decal.new()
	cloud_shade.name = "CloudShadows"
	cloud_shade.texture_albedo = cloud_texture()
	cloud_shade.modulate = Color(0.06, 0.07, 0.1, CLOUD_DARK)
	cloud_shade.albedo_mix = 1.0
	cloud_shade.size = Vector3(CLOUD_SPAN, 70.0, CLOUD_SPAN)
	cloud_shade.upper_fade = 0.0
	cloud_shade.lower_fade = 0.0
	add_child(cloud_shade)
	# Start with a cloud's edge across the sand (some of it in shade, some in the sun) rather
	# than wherever the noise happens to leave open sky over it: the first place along the
	# wind's way with about half the sand in shade.
	var img := cloud_texture().get_image()
	var wind := CLOUD_WIND.normalized()
	var best := Vector3(-CLOUD_TRAVEL * 0.5, 15.0, -CLOUD_TRAVEL * 0.2)
	var off := INF
	for k in 27:
		var p := wind * (-CLOUD_TRAVEL * 0.88 + k * 6.0) + Vector3(0, 15.0, 0)
		var d := absf(shade_over_sand(img, p) - 0.45)
		if d < off - 0.02:
			off = d
			best = p
	cloud_shade.position = best

## How much of the sand the clouds' shade covers with their decal at `at` (0 open sky, 1 all in
## shade): the texture read at a grid of points over the sand.
static func shade_over_sand(img: Image, at: Vector3) -> float:
	var n := 0
	var sum := 0.0
	var w := img.get_width()
	var h := img.get_height()
	for x in range(-12, 13, 3):
		for z in range(-12, 13, 3):
			var u := (float(x) - at.x) / CLOUD_SPAN + 0.5
			var v := (float(z) - at.z) / CLOUD_SPAN + 0.5
			sum += img.get_pixel(clampi(int(u * w), 0, w - 1), clampi(int(v * h), 0, h - 1)).a
			n += 1
	return sum / n

## The clouds' shadows as a texture: soft patches of shade, made at once (a noise texture made in
## the background came too late for the decal, which kept the empty one it was given).
static var _cloud_tex: ImageTexture = null
static func cloud_texture() -> ImageTexture:
	if _cloud_tex:
		return _cloud_tex
	var n := FastNoiseLite.new()
	n.seed = 17
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 0.03
	n.fractal_octaves = 4
	var size := 256
	var src := n.get_seamless_image(size, size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, Color(0, 0, 0, smoothstep(0.47, 0.66, src.get_pixel(x, y).r)))
	img.generate_mipmaps()
	_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex

func _move_clouds(dt: float) -> void:
	if cloud_shade == null:
		return
	cloud_shade.position += CLOUD_WIND * dt
	# Gone far enough: fade out, go back, fade in (a cloud that passed and the next one coming).
	if not _cloud_back and Vector2(cloud_shade.position.x, cloud_shade.position.z).length() > CLOUD_TRAVEL:
		_cloud_back = true
	if _cloud_back:
		_cloud_fade = maxf(0.0, _cloud_fade - dt / 4.0)
		if _cloud_fade <= 0.0:
			cloud_shade.position = Vector3(-CLOUD_WIND.normalized().x, 0, -CLOUD_WIND.normalized().z) * CLOUD_TRAVEL * 0.9 + Vector3(0, 15.0, 0)
			_cloud_back = false
	elif _cloud_fade < 1.0:
		_cloud_fade = minf(1.0, _cloud_fade + dt / 4.0)
	cloud_shade.modulate.a = CLOUD_DARK * _cloud_fade

## The colour grade (Environment.adjustment_color_correction): a table of what the grade makes of
## each colour, 17 a side. By day the shade leans a little to the cool of the open sky and the
## sunlit to the gold of the sun, the middle tones a little firmer; by night the moonlight a
## little bluer and the torchlight warmer. Made once for each.
static var _luts := {}
static func grade_lut(day: bool) -> ImageTexture3D:
	if _luts.has(day):
		return _luts[day]
	var n := 17
	var imgs: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				img.set_pixel(r, g, grade(Color(float(r) / (n - 1), float(g) / (n - 1), float(b) / (n - 1)), day))
		imgs.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, imgs)
	_luts[day] = t
	return t

## One colour through the grade.
static func grade(c: Color, day: bool) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var l := v.dot(Vector3(0.2126, 0.7152, 0.0722))
	# (Black itself stays black: the cool comes in over the first few shades.)
	var shade := (1.0 - smoothstep(0.0, 0.5, l)) * minf(1.0, l * 12.0)
	var lit := smoothstep(0.45, 1.0, l)
	var cool := Vector3(-0.012, 0.0, 0.022) if day else Vector3(-0.014, -0.004, 0.03)
	var warm := Vector3(0.026, 0.01, -0.024) if day else Vector3(0.032, 0.012, -0.022)
	v += cool * shade + warm * lit
	# A soft S through the middle tones (the ends left where they are).
	var l2 := maxf(1e-4, v.dot(Vector3(0.2126, 0.7152, 0.0722)))
	var s := l2 + 0.32 * (l2 - 0.5) * l2 * (1.0 - l2)
	v *= clampf(s / l2, 0.0, 2.0)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))

## What lies on the sand, drawn only (nothing to trip on): pebbles and stones, thick along the
## foot of the wall and scattered over the ring, and tufts of dry grass where the feet never go.
func _build_ground_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.vertex_color_is_srgb = true   # (read as linear, every stone came out chalk white)
	stone.roughness = 0.9
	var pebbles := MultiMesh.new()
	pebbles.transform_format = MultiMesh.TRANSFORM_3D
	pebbles.use_colors = true
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE
	pm.material = stone
	pebbles.mesh = pm
	var n := 900
	pebbles.instance_count = n
	for i in n:
		# Two in three along the wall's foot, the rest over the ring (fewer in the middle).
		var a := rng.randf() * TAU
		var rr := rng.randf_range(RADIUS - 2.2, RADIUS - 0.25) if i % 5 != 0 else sqrt(rng.randf()) * (RADIUS - 2.0)
		var big := rng.randf() < 0.08
		var sz := Vector3(rng.randf_range(0.03, 0.07), rng.randf_range(0.015, 0.035), rng.randf_range(0.03, 0.07)) * (2.6 if big else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(sz)
		pebbles.set_instance_transform(i, Transform3D(b, Vector3(sin(a) * rr, sz.y * 0.2, cos(a) * rr)))   # (half in the sand)
		var g := rng.randf_range(0.38, 0.6)
		pebbles.set_instance_color(i, Color(g * 1.05, g * 0.97, g * 0.86) if rng.randf() < 0.7 else Color(g * 1.1, g * 0.86, g * 0.66))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = pebbles
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pmi)
	var grass := StandardMaterial3D.new()
	grass.vertex_color_use_as_albedo = true
	grass.roughness = 1.0
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tufts := MultiMesh.new()
	tufts.transform_format = MultiMesh.TRANSFORM_3D
	tufts.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 1.0, 0.012)
	bm.material = grass
	tufts.mesh = bm
	var blades := 1400
	tufts.instance_count = blades
	var at := Vector3.ZERO
	for i in blades:
		if i % 14 == 0:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(RADIUS - 0.55, RADIUS - 0.15)
			at = Vector3(sin(a) * rr, 0, cos(a) * rr)
		var hgt := rng.randf_range(0.06, 0.2)
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.5))
		var off := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
		tufts.set_instance_transform(i, Transform3D(lean.scaled(Vector3(1, hgt, 1)), at + off + lean * Vector3(0, hgt * 0.5, 0)))
		var dry := rng.randf()
		tufts.set_instance_color(i, Color(0.62 + 0.2 * dry, 0.58 + 0.12 * dry, 0.3 + 0.1 * dry) if dry > 0.25 else Color(0.42, 0.5, 0.25))
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tufts
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tmi)
	_build_litter(rng, stone)

## What the fights have left on the sand, out of the way along the wall (drawing only: nothing to
## trip on and nothing to pick up): broken arrows stuck in it at a slant, splinters of shields,
## bones bleached white, wisps of straw from the beasts' bedding. Clear of the gates.
func _build_litter(rng: RandomNumberGenerator, mat: Material) -> void:
	var items := []
	for i in 110:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(RADIUS - 1.7, RADIUS - 0.3)
		var at := Vector3(sin(a) * rr, 0, cos(a) * rr)
		if absf(at.x) > 11.5 and absf(at.z) < 2.8:
			continue
		var kind := rng.randf()
		if kind < 0.32:
			# A broken arrow stuck in at a slant: the shaft, and what is left of its feathers.
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.25, 0.65))
			var ln := rng.randf_range(0.16, 0.38)
			items.append([Transform3D(tilt * Basis.from_scale(Vector3(0.012, ln, 0.012)), at + tilt * Vector3(0, ln * 0.3, 0)), Color(0.48, 0.34, 0.2)])
			items.append([Transform3D(tilt * Basis.from_scale(Vector3(0.035, 0.07, 0.006)), at + tilt * Vector3(0, ln * 0.72, 0)), Color(0.86, 0.84, 0.78)])
		elif kind < 0.58:
			# A splinter of a shield, painted on its face.
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
			var col: Color = [Color(0.55, 0.16, 0.1), Color(0.5, 0.36, 0.2), Color(0.2, 0.28, 0.48)][rng.randi() % 3]
			items.append([Transform3D(b * Basis.from_scale(Vector3(rng.randf_range(0.08, 0.2), 0.018, rng.randf_range(0.04, 0.09))), at + Vector3(0, 0.006, 0)), col])
		elif kind < 0.8:
			# A bone, bleached by the sun.
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			items.append([Transform3D(b * Basis.from_scale(Vector3(0.026, 0.026, rng.randf_range(0.12, 0.22))), at + Vector3(0, 0.008, 0)), Color(0.86, 0.82, 0.7)])
			items.append([Transform3D(b * Basis.from_scale(Vector3(0.045, 0.035, 0.035)), at + b * Vector3(0, 0.012, 0.08)), Color(0.84, 0.8, 0.68)])
		else:
			# Straw.
			for s in 7:
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.25, 0.25))
				items.append([Transform3D(b * Basis.from_scale(Vector3(0.005, rng.randf_range(0.1, 0.2), 0.005)), at + Vector3(rng.randf_range(-0.12, 0.12), 0.006, rng.randf_range(-0.12, 0.12))), Color(0.82, 0.7, 0.38).darkened(rng.randf() * 0.2)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.name = "Litter"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## The arena floor: smooth sand and packed earth (art/textures/floor_*.webp, 4 m a map) laid on
## in world space. Falls back to the old raked sand when the maps are missing.
static func sand_material() -> Material:
	# The floor's own shader: fine sand and packed earth blended across the arena, raked rings,
	# damp sand at the wall (shaders/sand.gdshader). The plain textured sand when it cannot be had.
	var maps := {}
	for k in ["sand_alb", "sand_nrm", "earth_alb", "earth_nrm"]:
		var f: String = {"sand_alb": "floor_sand_albedo", "sand_nrm": "floor_sand_normal", "earth_alb": "floor_earth_albedo", "earth_nrm": "floor_earth_normal"}[k]
		maps[k] = load_texture("res://art/textures/%s.webp" % f)
	var sh = load("res://shaders/sand.gdshader")
	if sh and not maps.values().has(null):
		var sm := ShaderMaterial.new()
		sm.shader = sh
		for k in maps:
			sm.set_shader_parameter(k, maps[k])
		sm.set_shader_parameter("radius", RADIUS)
		return sm
	var old := surface_material("sand", 0.45, 1.0)
	old.albedo_color = Color(1.0, 0.97, 0.93)
	old.normal_scale = 0.9
	return old

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
	var coals := []
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
		l.light_energy = 1.5 if day else 3.0
		l.omni_range = 5.0 if day else 8.0
		l.shadow_enabled = not day
		l.light_volumetric_fog_energy = 2.0
		add_child(l)
		l.position = p + Vector3(0, 1.85, 0)
		torches.append(l)
		var holder := Node3D.new()
		add_child(holder)
		holder.position = p + Vector3(0, 1.55, 0)
		coals.append(holder.position)
		if Fx.current:
			var f := Fx.current.emitter("brazier", holder, 60, 0.18)
			if f:
				f.emitting = true
			var sm := Fx.current.emitter("smoke", holder, 8, 0.1)
			if sm:
				sm.emitting = true
	# Embers rising off the coals on the heat and fading as they climb.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var embers := []
	for c in coals:
		for k in 14:
			embers.append((c as Vector3) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)))
	_specks("Embers", embers, Color(1.0, 0.5, 0.14, 1.0), 1.4, 2.4, 0.05, 0.024, 41)

func _process(_dt: float) -> void:
	_move_clouds(_dt)
	var t := Time.get_ticks_msec() / 1000.0
	for i in torches.size():
		var l: OmniLight3D = torches[i]
		l.light_energy = l.light_energy * 0.8 + 0.2 * ((torch_base if theme != "night" else 3.0) * (0.85 + 0.15 * sin(t * 11.0 + i * 1.7) + 0.08 * sin(t * 23.0 + i)))

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
	box.call(Vector3(0, 0.53, -0.088), Vector3(0.1, 0.12, 0.022), 10.0, 1.0)     # long hair, down the back
	# A sign on a stick in the right hand (hung below it here: raised, the arm turns it up over
	# the head), and a vendor's basket on his head.
	box.call(Vector3(0.175, 0.02, 0.0), Vector3(0.012, 0.15, 0.012), 11.0, 1.0)
	box.call(Vector3(0.175, -0.21, 0.0), Vector3(0.14, 0.09, 0.01), 12.0, 1.0)
	box.call(Vector3(0, 0.79, 0), Vector3(0.12, 0.05, 0.12), 13.0, 1.0)
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
			# (The colour's alpha is who he is, for the shader: 1 the common crowd, 0.5 a citizen in
			# his toga, white with a purple stripe, mostly in the two lowest tiers.)
			tun.a = 0.5 if rng.randf() < (0.3 if t < 2 else 0.05) else 1.0
			# Now and then a child, smaller, on the same seat.
			if rng.randf() < 0.07:
				basis = basis.scaled(Vector3.ONE * 0.74)
			var sk: Color = skins[rng.randi_range(0, skins.size() - 1)]
			var seat_y := (2.6 if voxel else 2.55) + t * 0.7
			list.append([Transform3D(basis, Vector3(sin(a) * (rr - 0.1), seat_y, cos(a) * (rr - 0.1))), tun, Color(sk.r, sk.g, sk.b, rng.randf())])
	# Vendors standing in the aisles' stairs with a basket on the head (alpha 0.25).
	if voxel:
		for k in 12:
			var t := 1 + k % 4
			var rr := RADIUS + 1.4 + t * 1.3
			var a := deg_to_rad(15.0 + 30.0 * ((k * 5) % 12)) + 0.012
			var p := Vector2(sin(a) * rr, cos(a) * rr)
			if (absf(p.x) > 13.0 and absf(p.y) < 2.9) or (absf(p.x) < 3.0 and p.y > 15.0):
				continue
			var vb := Basis(Vector3.UP, a + (PI if k % 2 else 0.0)).scaled(Vector3.ONE * 1.12)
			var vt := Color(0.62, 0.48, 0.3, 0.25)
			var vs := skins[k % skins.size()] as Color
			list.append([Transform3D(vb, Vector3(p.x, 2.6 + t * 0.7 - 0.05, p.y)), vt, Color(vs.r, vs.g, vs.b, fposmod(k * 0.137, 1.0))])
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
	_build_velarium(top_r)
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

## The velarium: sails of cloth lashed to masts along the top of the arcade and stretched in and
## down over the stands toward the sand, cream and red by turns, sagging between their ropes and
## rippling in the wind, two of them furled to let the sun in (from the floor of the arena they
## were a thin striped band at the top of the arcade, seen edge on). Under them, long banners hang
## from the arcade in red and purple, each with a gold border and a wreath. Drawing only
## (cloth.gdshader): no one can touch them, and the fight camera never comes up to them. They
## cast no shadow: the light on the sand stays as it was (sails on the sun's side threw half the
## arena into shade).
func _build_velarium(top_r: float) -> void:
	var cloth: Shader = load("res://shaders/cloth.gdshader")
	var sails := 20
	var r_out := top_r + 0.3
	var r_in := RADIUS + 3.6
	var nr := 6
	var na := 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sails:
		if i == 4 or i == 14:
			continue
		var a0 := (i + 0.03) / sails * TAU
		var a1 := (i + 0.97) / sails * TAU
		var col := Color(0.88, 0.82, 0.68) if i % 2 == 0 else Color(0.66, 0.18, 0.12)
		var grid := []
		for ir in nr + 1:
			var u := float(ir) / nr
			var row := []
			for ia in na + 1:
				var v := float(ia) / na
				var a := lerpf(a0, a1, v)
				var r := lerpf(r_out, r_in, u)
				# Lashed high on the masts, falling toward its free edge, sagging between its ropes.
				var y := lerpf(12.1, 10.7, u) - 0.6 * sin(PI * u) * (0.55 + 0.45 * sin(PI * v)) - 0.25 * sin(PI * v) * u
				row.append([Vector3(sin(a) * r, y, cos(a) * r), Vector2(u, v)])
			grid.append(row)
		for ir in nr:
			for ia in na:
				var q: Array = [grid[ir][ia], grid[ir + 1][ia], grid[ir + 1][ia + 1], grid[ir][ia + 1]]
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_color(col)
					st.set_uv(q[k][1])
					st.add_vertex(q[k][0])
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = cloth
	mat.set_shader_parameter("wave", 0.22)
	if voxel:
		mat.set_shader_parameter("cells", 12.0)
	var sails_mi := MeshInstance3D.new()
	sails_mi.name = "Velarium"
	sails_mi.mesh = st.commit()
	sails_mi.material_override = mat
	sails_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sails_mi)
	# The masts the sails are lashed to, one between each two, along the top of the arcade.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	wood.roughness = 0.85
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = 3.6
	pole.radial_segments = 6
	pole.material = wood
	var masts := MultiMesh.new()
	masts.transform_format = MultiMesh.TRANSFORM_3D
	masts.mesh = pole
	masts.instance_count = sails
	for i in sails:
		var a := float(i) / sails * TAU
		masts.set_instance_transform(i, Transform3D(Basis(), Vector3(sin(a) * r_out, 10.6, cos(a) * r_out)))
	var masts_mi := MultiMeshInstance3D.new()
	masts_mi.multimesh = masts
	masts_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(masts_mi)
	# The banners, clear of the gates (east and west) and the Emperor's box (north).
	var bm := _cloth_strip(1.25, 3.4, 3, 10)
	var k := 0
	for deg in [27.0, 56.0, 124.0, 153.0, 207.0, 236.0, 304.0, 333.0]:
		var a := deg_to_rad(deg)
		var bmat := ShaderMaterial.new()
		bmat.shader = cloth
		bmat.set_shader_parameter("hanging", true)
		bmat.set_shader_parameter("wave", 0.16)
		bmat.set_shader_parameter("field", Color(0.62, 0.11, 0.09) if k % 2 == 0 else Color(0.36, 0.1, 0.36))
		bmat.set_shader_parameter("trim", Color(0.92, 0.72, 0.3))
		if voxel:
			bmat.set_shader_parameter("cells", 10.0)
		var ban := MeshInstance3D.new()
		ban.mesh = bm
		ban.material_override = bmat
		ban.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ban)
		var rr := top_r - 0.55
		ban.transform = Transform3D(Basis(Vector3.UP, a + PI), Vector3(sin(a) * rr, 10.15, cos(a) * rr))
		k += 1

## A strip of cloth `w` wide and `h` long hanging down from its top edge (at the origin), facing
## +z, cut `nx` by `ny`: UV.y 0 at the top, 1 at the foot.
static func _cloth_strip(w: float, h: float, nx: int, ny: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in ny:
		for ix in nx:
			var q := []
			for c in [[ix, iy], [ix + 1, iy], [ix + 1, iy + 1], [ix, iy + 1]]:
				var u := float(c[0]) / nx
				var v := float(c[1]) / ny
				q.append([Vector3((u - 0.5) * w, -v * h, 0.0), Vector2(u, v)])
			for t in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(q[t][1])
				st.add_vertex(q[t][0])
	return st.commit()

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
