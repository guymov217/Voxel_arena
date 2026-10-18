extends Node
## The same moment of a fight under several lighting looks, side by side for choosing one
## (`-- --probe lightshots`, needs a display; SHOT_DIR is where the PNGs go). A training bout runs
## on autopilot until a hard blow lands, the physics is stopped there, and every look in LOOKS is
## put on the same frozen scene: once close on the fight, once wide over the arena.

const LOOKS := {
	"a_now": {},
	"b_afternoon": {"tonemap": "agx", "exposure": 1.0, "sat": 1.0, "contrast": 1.04,
		"sun_pitch": -34.0, "sun_energy": 1.45, "sun_color": Color(1.0, 0.86, 0.68), "ambient": 0.7,
		"sand": 0.82, "sky_top": Color(0.33, 0.5, 0.75), "sky_horizon": Color(0.92, 0.8, 0.62), "vfog": 0.008},
	"c_golden": {"tonemap": "agx", "exposure": 1.05, "sat": 1.05, "contrast": 1.06,
		"sun_pitch": -16.0, "sun_energy": 1.8, "sun_color": Color(1.0, 0.68, 0.42), "ambient": 0.55,
		"ambient_color": Color(0.9, 0.66, 0.5), "sand": 0.9, "sky_top": Color(0.3, 0.42, 0.68),
		"sky_horizon": Color(1.0, 0.72, 0.48), "vfog": 0.012, "vfog_albedo": Color(1.0, 0.8, 0.6)},
	"d_haze": {"tonemap": "agx", "exposure": 1.1, "sat": 0.9, "contrast": 1.0,
		"sun_pitch": -40.0, "sun_energy": 1.0, "shadow_blur": 3.0, "ambient": 1.0, "sky_contrib": 0.8,
		"sand": 0.8, "sky_top": Color(0.55, 0.62, 0.72), "sky_horizon": Color(0.88, 0.84, 0.76), "cover": 0.75, "vfog": 0.012},
	"e_clear": {"exposure": 0.8, "sat": 1.05, "contrast": 1.1, "sun_pitch": -38.0, "sun_energy": 1.5,
		"sun_color": Color(1.0, 0.9, 0.78), "ambient": 0.65, "sand": 0.74, "sky_top": Color(0.28, 0.47, 0.78),
		"sky_horizon": Color(0.88, 0.8, 0.68), "vfog": 0.004},
	"f_clear_warm": {"tonemap": "agx", "exposure": 1.15, "sat": 1.25, "contrast": 1.15, "sun_pitch": -32.0,
		"sun_energy": 1.6, "sun_color": Color(1.0, 0.86, 0.7), "ambient": 0.7, "sand": 0.76,
		"sky_top": Color(0.27, 0.46, 0.8), "sky_horizon": Color(0.9, 0.8, 0.66), "vfog": 0.004},
}

var menu
var out := ""
var big: Dictionary = {}

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	seed(3)
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": OS.get_environment("LIGHT_FOE") if OS.get_environment("LIGHT_FOE") != "" else "bear", "immortal": true}, "autopilot": true, "decrees": [], "hazards": [], "seed": 3, "loadout_override": {"main": "axe", "off": "roundShield"}})
	var m = menu.match_
	m.combat.hit.connect(func(h): if big.is_empty() and float(h.get("J", 0.0)) > 25.0 and h.get("p") is Vector3: big = h)
	var waited := 0
	while big.is_empty() and waited < 120 * 30:
		await get_tree().physics_frame
		waited += 1
	for i in 4:
		await get_tree().physics_frame
	PhysicsServer3D.set_active(false)
	m.set_physics_process(false)
	menu.hud.visible = false
	m.cam.set_process(false)
	m.set_process(false)
	var arena = m.arena
	var base := _capture(arena)
	var p: Vector3 = big.p if not big.is_empty() else Vector3(0, 1, 0)
	var a = big.get("attacker")
	var v = big.get("char")
	var pa: Vector3 = a.torso.global_position if a is Fighter and is_instance_valid(a) else p
	var pv: Vector3 = v.torso.global_position if v is Fighter and is_instance_valid(v) else p
	var c := (pa + pv + p) / 3.0
	var across := pv - pa
	across.y = 0
	if across.length() < 0.2:
		across = Vector3(1, 0, 0)
	var side := across.normalized().cross(Vector3.UP)
	if (c + side).length() > (c - side).length():
		side = -side
	var shots := [
		["close", c + side * (2.6 + pa.distance_to(pv) * 0.7) + Vector3(0, 0.5, 0), c + Vector3(0, 0.1, 0), 48.0],
		["wide", Vector3(c.x, 0, c.z) + side * 10.0 + Vector3(0, 4.5, 0), c, 60.0],
		["wall", Vector3(sin(deg_to_rad(145.0)), 0, cos(deg_to_rad(145.0))) * 9.0 + Vector3(0, 2.2, 0), Vector3(sin(deg_to_rad(145.0)), 0, cos(deg_to_rad(145.0))) * 14.6 + Vector3(0, 0.6, 0), 55.0],
		["top", Vector3(0.5, 19.0, 6.0), Vector3(0, 0, 0), 60.0],
	]
	var only := OS.get_environment("LOOK_ONLY")
	for look in LOOKS:
		if only != "" and not only.split(",").has(look):
			continue
		_restore(arena, base)
		_apply(arena, LOOKS[look])
		for sh in shots:
			m.cam.global_position = sh[1]
			m.cam.look_at(sh[2], Vector3.UP)
			m.cam.fov = sh[3]
			for i in 40:   # the screen-space effects and the fog settle over a few frames
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [look, sh[0]]))
			print("saved ", look, " ", sh[0])
	get_tree().quit()

func _sand(arena) -> MeshInstance3D:
	for ch in arena.get_children():
		if ch is MeshInstance3D and ch.mesh is CylinderMesh and (ch.mesh as CylinderMesh).top_radius == Arena.RADIUS:
			return ch
	return null

func _sky(arena) -> ShaderMaterial:
	return arena.env.sky.sky_material

func _capture(arena) -> Dictionary:
	var e: Environment = arena.env
	var sm := _sky(arena)
	var sand := _sand(arena)
	return {"tonemap": e.tonemap_mode, "exposure": e.tonemap_exposure, "sat": e.adjustment_saturation,
		"contrast": e.adjustment_contrast, "ambient": e.ambient_light_energy, "ambient_color": e.ambient_light_color,
		"sky_contrib": e.ambient_light_sky_contribution, "vfog": e.volumetric_fog_density, "vfog_albedo": e.volumetric_fog_albedo,
		"sun_rot": arena.sun.rotation, "sun_energy": arena.sun.light_energy, "sun_color": arena.sun.light_color,
		"shadow_blur": arena.sun.shadow_blur,
		"sky_top": sm.get_shader_parameter("top_color"), "sky_horizon": sm.get_shader_parameter("horizon_color"),
		"cover": sm.get_shader_parameter("cover"),
		"sand": (sand.mesh.material as StandardMaterial3D).albedo_color if sand else Color.WHITE}

func _restore(arena, b: Dictionary) -> void:
	var e: Environment = arena.env
	e.tonemap_mode = b.tonemap
	e.tonemap_exposure = b.exposure
	e.adjustment_saturation = b.sat
	e.adjustment_contrast = b.contrast
	e.ambient_light_energy = b.ambient
	e.ambient_light_color = b.ambient_color
	e.ambient_light_sky_contribution = b.sky_contrib
	e.volumetric_fog_density = b.vfog
	e.volumetric_fog_albedo = b.vfog_albedo
	arena.sun.rotation = b.sun_rot
	arena.sun.light_energy = b.sun_energy
	arena.sun.light_color = b.sun_color
	arena.sun.shadow_blur = b.shadow_blur
	var sm := _sky(arena)
	sm.set_shader_parameter("top_color", b.sky_top if b.sky_top != null else Color(0.22, 0.42, 0.78))
	sm.set_shader_parameter("horizon_color", b.sky_horizon if b.sky_horizon != null else Color(0.86, 0.78, 0.64))
	sm.set_shader_parameter("cover", b.cover if b.cover != null else 0.48)
	var sand := _sand(arena)
	if sand:
		(sand.mesh.material as StandardMaterial3D).albedo_color = b.sand

func _apply(arena, l: Dictionary) -> void:
	var e: Environment = arena.env
	if l.has("tonemap"):
		e.tonemap_mode = Environment.TONE_MAPPER_AGX if l.tonemap == "agx" else Environment.TONE_MAPPER_ACES
	if l.has("exposure"):
		e.tonemap_exposure = l.exposure
	if l.has("sat"):
		e.adjustment_saturation = l.sat
	if l.has("contrast"):
		e.adjustment_contrast = l.contrast
	if l.has("ambient"):
		e.ambient_light_energy = l.ambient
	if l.has("ambient_color"):
		e.ambient_light_color = l.ambient_color
	if l.has("sky_contrib"):
		e.ambient_light_sky_contribution = l.sky_contrib
	if l.has("vfog"):
		e.volumetric_fog_density = l.vfog
	if l.has("vfog_albedo"):
		e.volumetric_fog_albedo = l.vfog_albedo
	if l.has("sun_pitch"):
		arena.sun.rotation.x = deg_to_rad(l.sun_pitch)
	if l.has("sun_energy"):
		arena.sun.light_energy = l.sun_energy
	if l.has("sun_color"):
		arena.sun.light_color = l.sun_color
	if l.has("shadow_blur"):
		arena.sun.shadow_blur = l.shadow_blur
	var sm := _sky(arena)
	if l.has("sky_top"):
		sm.set_shader_parameter("top_color", l.sky_top)
	if l.has("sky_horizon"):
		sm.set_shader_parameter("horizon_color", l.sky_horizon)
	if l.has("cover"):
		sm.set_shader_parameter("cover", l.cover)
	var sand := _sand(arena)
	if sand and l.has("sand"):
		var mat := sand.mesh.material as StandardMaterial3D
		mat.albedo_color = Color(l.sand, l.sand, l.sand)
