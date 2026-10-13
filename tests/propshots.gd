extends Node3D
## Every voxel model on its own (`-- --probe propshots`, needs a display): a small studio with
## sun, sky and sand floor, each model framed from three quarters in front. Then the whole bowl
## from above. PNGs go to SHOT_DIR as prop_<name>.png.

const NAMES := ["brazier", "gate_door", "statue", "amphora", "amphora_wide", "crate", "weapon_rack",
	"throne", "sign_post", "target", "smithy", "market_stall", "notice_board", "physician", "column",
	"banner", "spike_plate", "bomb", "forge_anvil"]

var cam: Camera3D

func _save(name_: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("prop_%s.png" % name_))
	print("saved ", name_)

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _ready() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.45, 0.68)
	sm.sky_horizon_color = Color(0.78, 0.72, 0.62)
	sm.ground_horizon_color = Color(0.6, 0.52, 0.42)
	sm.ground_bottom_color = Color(0.3, 0.26, 0.22)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.ssao_enabled = true
	e.ssao_intensity = 2.5
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.1
	e.adjustment_saturation = 1.08
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 20.0
	add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.material = Arena.sand_material()
	floor_.mesh = pm
	add_child(floor_)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	var only := OS.get_environment("SHOT_ONLY").split(",", false)
	for nm in NAMES:
		if not only.is_empty() and not only.has(nm):
			continue
		var n := VoxelArt.make(nm)
		if n == null:
			continue
		add_child(n)
		if nm == "target":
			n.position = Vector3(0, 1.5, 0)
			n.rotation.y = PI
		var b := _aabb(n)
		var c := b.get_center()
		var r := b.size.length() * 0.5
		var dir := Vector3(0.75, 0.45, 1.0).normalized()
		cam.global_position = c + dir * maxf(r, 0.35) * 2.7
		cam.look_at(c, Vector3.UP)
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 0.8, 1.0)
		l.light_energy = 0.5
		l.omni_range = r * 6.0
		add_child(l)
		l.global_position = c + Vector3(-1.5, 0.6, 1.2) * maxf(r, 0.5) * 2.0
		await _save(nm)
		n.queue_free()
		l.queue_free()
	# The bowl from above and outside.
	floor_.queue_free()
	if not only.is_empty() and not only.has("arena"):
		get_tree().quit()
		return
	var bowl := VoxelArt.make("arena")
	if bowl:
		add_child(bowl)
		var sand := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 15.0
		cm.bottom_radius = 15.0
		cm.height = 0.02
		cm.radial_segments = 96
		cm.material = Arena.sand_material()
		sand.mesh = cm
		add_child(sand)
		sun.directional_shadow_max_distance = 120.0
		cam.fov = 45.0
		cam.global_position = Vector3(30, 34, -38)
		cam.look_at(Vector3(0, 1, 2), Vector3.UP)
		await _save("arena_aerial")
		cam.global_position = Vector3(0, 46, 0.01)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		await _save("arena_top")
	get_tree().quit()
