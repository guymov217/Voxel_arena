extends Node
## The same moment of a fight from five cameras, and how long the frame takes to draw there
## (`-- --probe gfxshots`, needs a display). For comparing the look before and after a change
## to the graphics: a training bout runs on autopilot until a hard blow lands, the physics is
## stopped there, the shots are taken, then the wide view is drawn a while and timed.
## SHOT_DIR: where the PNGs go; GFX_TAG: their prefix; GFX_QUALITY: low/medium/high/ultra (the
## Options' setting otherwise); GFX_FOE: the beast in the ring (bear); GFX_THEME: day or night;
## GFX_SHOTS: which of close, low, wide, wall, top (all); GFX_SETTLE: frames drawn before a shot
## (40); GFX_FRAMES: frames timed (40, 0 for none); GFX_LOOKS: looks to try on the same moment,
## from LOOKS below ("base": the game's own).
## Run single-threaded at a fixed rate so the moment is the same every time:
##   printf '[threading]\nworker_pool/max_threads=1\n' > override.cfg
##   godot --path . --fixed-fps 120 --resolution 1280x720 -- --probe gfxshots

## Trial looks, put on over the game's own (the environment, the sun, a film layer).
const LOOKS := {
	"base": {},
	"warm": {"sun_color": Color(1.0, 0.86, 0.7), "sun_energy": 1.75, "sun_angle": 0.6,
		"ambient_color": Color(0.62, 0.72, 0.9), "sky_contrib": 0.75, "ambient": 0.6},
	"haze": {"sun_color": Color(1.0, 0.86, 0.7), "sun_energy": 1.75, "sun_angle": 0.6,
		"ambient_color": Color(0.62, 0.72, 0.9), "sky_contrib": 0.75, "ambient": 0.6,
		"fog": 0.006, "fog_aerial": 0.7, "fog_sun": 0.25, "vfog": 0.009, "vfog_sun": 2.0},
	"film": {"sun_color": Color(1.0, 0.86, 0.7), "sun_energy": 1.75, "sun_angle": 0.6,
		"ambient_color": Color(0.62, 0.72, 0.9), "sky_contrib": 0.75, "ambient": 0.6,
		"fog": 0.006, "fog_aerial": 0.7, "fog_sun": 0.25, "vfog": 0.009, "vfog_sun": 2.0, "film": true},
}

var menu
var out := ""
var big: Dictionary = {}
var film: CanvasLayer = null

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	var tag := OS.get_environment("GFX_TAG")
	if tag == "":
		tag = "shot"
	seed(3)
	var q := OS.get_environment("GFX_QUALITY")
	var q_was = Save.get_value("settings", {}).get("quality") if Save else null
	if q != "" and Save:
		var st: Dictionary = Save.get_value("settings", {})
		st["quality"] = q
		Save.set_value("settings", st)
	# The same bout to the step every run (one physics thread, --fixed-fps 120, contacts in a set
	# order), drawn nothing until its moment: the shots before and after a change match.
	Combat.canonical = true
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	var foe := OS.get_environment("GFX_FOE")
	var spec := {"mode": "training", "training": {"enemy": foe if foe != "" else "bear", "immortal": true}, "autopilot": true, "decrees": [], "hazards": [], "seed": 3, "loadout_override": {"main": "axe", "off": "roundShield"}}
	if OS.get_environment("GFX_THEME") == "night":
		spec["arena"] = "night"
	menu.start(spec)
	# Nothing to see until the moment: the 3D off, the HUD hidden, the window a postage stamp (the
	# software renderer of a machine without a graphics card spends seconds on a full frame).
	get_viewport().disable_3d = true
	menu.hud.visible = false
	var full := get_window().size
	get_window().size = Vector2i(160, 90)
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
	get_window().size = full
	get_viewport().disable_3d = false
	menu.hud.visible = false
	m.cam.set_process(false)
	m.set_process(false)
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
	var wall_a := deg_to_rad(145.0)
	var shots := [
		["close", c + side * (2.6 + pa.distance_to(pv) * 0.7) + Vector3(0, 0.5, 0), c + Vector3(0, 0.1, 0), 48.0],
		["low", c + side * (1.6 + pa.distance_to(pv) * 0.5) + across.normalized() * 0.8 + Vector3(0, -0.55, 0), c + Vector3(0, 0.35, 0), 55.0],
		["wide", Vector3(c.x, 0, c.z) + side * 10.0 + Vector3(0, 4.5, 0), c, 60.0],
		["wall", Vector3(sin(wall_a), 0, cos(wall_a)) * 9.0 + Vector3(0, 2.2, 0), Vector3(sin(wall_a), 0, cos(wall_a)) * 14.6 + Vector3(0, 0.6, 0), 55.0],
		["top", Vector3(0.5, 19.0, 6.0), Vector3(0, 0, 0), 60.0],
	]
	var want := OS.get_environment("GFX_SHOTS").split(",", false)
	var settle := int(OS.get_environment("GFX_SETTLE")) if OS.get_environment("GFX_SETTLE") != "" else 40
	var n := int(OS.get_environment("GFX_FRAMES")) if OS.get_environment("GFX_FRAMES") != "" else 40
	var looks := OS.get_environment("GFX_LOOKS").split(",", false)
	if looks.is_empty():
		looks = PackedStringArray(["base"])
	var arena = m.arena
	var base := _capture(arena)
	for look in looks:
		_restore(arena, base)
		_apply(arena, LOOKS.get(look, {}))
		var nm := tag if looks.size() == 1 else "%s_%s" % [tag, look]
		for sh in shots:
			if not want.is_empty() and not want.has(sh[0]):
				continue
			m.cam.global_position = sh[1]
			m.cam.look_at(sh[2], Vector3.UP)
			m.cam.fov = sh[3]
			for i in settle:   # the screen-space effects, the fog and the exposure settle over a few frames
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [nm, sh[0]]))
			print("saved ", nm, " ", sh[0])
		if n <= 0:
			continue
		# Timing: the wide view (the fighters, the sand, the stands and the sky all in it).
		var wide: Array = shots[2]
		m.cam.global_position = wide[1]
		m.cam.look_at(wide[2], Vector3.UP)
		m.cam.fov = wide[3]
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		for i in 10:
			await get_tree().process_frame
		var cpu := 0.0
		var gpu := 0.0
		var t0 := Time.get_ticks_usec()
		for i in n:
			await get_tree().process_frame
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var frame := float(Time.get_ticks_usec() - t0) / 1000.0 / n
		print("GFXPERF %s quality=%s frame=%.2f ms render_cpu=%.2f ms render_gpu=%.2f ms" % [nm, str(Save.get_value("settings", {}).get("quality", "high")) if Save else "?", frame, cpu / n, gpu / n])
	if q != "" and Save:
		var st: Dictionary = Save.get_value("settings", {})
		if q_was == null:
			st.erase("quality")
		else:
			st["quality"] = q_was
		Save.set_value("settings", st)
	get_tree().quit()

func _capture(arena) -> Dictionary:
	var e: Environment = arena.env
	return {"ambient": e.ambient_light_energy, "ambient_color": e.ambient_light_color, "sky_contrib": e.ambient_light_sky_contribution,
		"fog_on": e.fog_enabled, "fog": e.fog_density, "fog_aerial": e.fog_aerial_perspective, "fog_sun": e.fog_sun_scatter,
		"fog_sky": e.fog_sky_affect, "vfog": e.volumetric_fog_density,
		"sun_color": arena.sun.light_color, "sun_energy": arena.sun.light_energy, "sun_angle": arena.sun.light_angular_distance,
		"vfog_sun": arena.sun.light_volumetric_fog_energy}

func _restore(arena, b: Dictionary) -> void:
	var e: Environment = arena.env
	e.ambient_light_energy = b.ambient
	e.ambient_light_color = b.ambient_color
	e.ambient_light_sky_contribution = b.sky_contrib
	e.fog_enabled = b.fog_on
	e.fog_density = b.fog
	e.fog_aerial_perspective = b.fog_aerial
	e.fog_sun_scatter = b.fog_sun
	e.fog_sky_affect = b.fog_sky
	e.volumetric_fog_density = b.vfog
	arena.sun.light_color = b.sun_color
	arena.sun.light_energy = b.sun_energy
	arena.sun.light_angular_distance = b.sun_angle
	arena.sun.light_volumetric_fog_energy = b.vfog_sun
	if film:
		film.queue_free()
		film = null

func _apply(arena, l: Dictionary) -> void:
	var e: Environment = arena.env
	if l.has("ambient"):
		e.ambient_light_energy = l.ambient
	if l.has("ambient_color"):
		e.ambient_light_color = l.ambient_color
	if l.has("sky_contrib"):
		e.ambient_light_sky_contribution = l.sky_contrib
	if l.has("fog"):
		e.fog_enabled = true
		e.fog_density = l.fog
		e.fog_sky_affect = 0.0
	if l.has("fog_aerial"):
		e.fog_aerial_perspective = l.fog_aerial
	if l.has("fog_sun"):
		e.fog_sun_scatter = l.fog_sun
	if l.has("vfog") and e.volumetric_fog_enabled:
		e.volumetric_fog_density = l.vfog
	if l.has("sun_color"):
		arena.sun.light_color = l.sun_color
	if l.has("sun_energy"):
		arena.sun.light_energy = l.sun_energy
	if l.has("sun_angle"):
		arena.sun.light_angular_distance = l.sun_angle
	if l.has("vfog_sun"):
		arena.sun.light_volumetric_fog_energy = l.vfog_sun
	if l.get("film", false):
		film = CanvasLayer.new()
		film.layer = -1
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/film.gdshader")
		r.material = sm
		film.add_child(r)
		add_child(film)
