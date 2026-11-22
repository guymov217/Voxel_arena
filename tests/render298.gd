extends Node
## What a frame costs the processor with N men on the sand, drawn for real (`-- --probe render298`, in a window: under Xvfb with Mesa's software Vulkan (lavapipe)
## when there is no graphics card, `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --rendering-driver vulkan --resolution 640x360 ...`).
## The card's own time is then the software rasteriser's and means nothing; what the engine's renderer asks of the processor does: the draw calls, the objects,
## the primitives, the time it takes to record a frame (the engine's measure, RenderingServer.viewport_get_measured_render_time_cpu), and the scripts' frame.
## env: N (men, 8), BEHAVIOR (idle|walk|brawl), FRAMES (measured, 120), WARM (frames to settle, 240), QUALITY (low|medium|high|ultra: Arena.apply_quality), SHADOWS (0: the sun casts none),
## MSAA (0: off), SCALE (the 3D resolution scale), FOG (0: no volumetric fog), SSIL (0/1), CROWD (0: the stands' people hidden), MEN_DRAW (0: the men not drawn at all).

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

var frame_us := PackedInt32Array()
var rec_ms := PackedFloat32Array()
var setup_ms := PackedFloat32Array()
var gpu_ms := PackedFloat32Array()
var calls := PackedInt32Array()
var objs := PackedInt32Array()
var prims := PackedInt32Array()
var proc_ms := PackedFloat32Array()
var phys_ms := PackedFloat32Array()
var measuring := false
var last_us := 0

func _process(_dt: float) -> void:
	if not measuring:
		return
	var now := Time.get_ticks_usec()
	if last_us > 0:
		frame_us.append(now - last_us)
	last_us = now
	var rid := get_viewport().get_viewport_rid()
	rec_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	setup_ms.append(RenderingServer.get_frame_setup_time_cpu())
	gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	calls.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	objs.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
	prims.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

func _ready() -> void:
	var n_men := int(_env("N", "8"))
	var behavior := _env("BEHAVIOR", "walk")
	var frames := int(_env("FRAMES", "120"))
	var warm := int(_env("WARM", "240"))
	seed(7)
	Fighter.process_in_headless = true
	var m := Match.new()
	add_child(m)
	var lo := {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"]}
	if _env("ARMOR", "1") == "0":
		lo["armor"] = []
	if _env("ARMOR_IDS", "") != "":
		lo["armor"] = Array(_env("ARMOR_IDS", "").split(","))
	if _env("ARMOR_IDS", "") == "none":
		lo["armor"] = []
	m.setup({"mode": "yard", "headless": false, "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	for e in m.entities.duplicate():
		if e.kind == "npc":
			m._remove_entity(e)
	var heading := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n_men - 1:
		var a := TAU * float(i) / float(maxi(1, n_men - 1))
		var spec := {"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * 3.0, 0.1, sin(a) * 3.0 + 4.0), "yaw": a + PI}
		var e = m.spawn_fighter(spec)
		if behavior != "brawl":
			e.erase("bot")
			heading[e.id] = rng.randf() * TAU
			if behavior == "idle":
				e.drive = func(_e): return {}
			else:
				e.drive = func(en):
					var id: int = en.id
					if rng.randf() < 0.01:
						heading[id] = rng.randf() * TAU
					return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
	# the render knobs
	var q := _env("QUALITY", "")
	if m.arena != null:
		if q != "":
			Arena.apply_quality(m.arena.env, m.arena.sun, q)
		if _env("SHADOWS", "1") == "0" and m.arena.sun != null:
			m.arena.sun.shadow_enabled = false
		if _env("FOG", "1") == "0":
			m.arena.env.volumetric_fog_enabled = false
		if _env("SSIL", "") != "":
			m.arena.env.ssil_enabled = _env("SSIL", "1") == "1"
	var vp := get_viewport()
	if _env("MSAA", "") == "0":
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if _env("SCALE", "") != "":
		vp.scaling_3d_scale = float(_env("SCALE", "1.0"))
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var t_w := Time.get_ticks_msec()
	for i in warm:
		await get_tree().process_frame
		if i % 10 == 0:
			print("WARM ", i, " of ", warm, " at ", (Time.get_ticks_msec() - t_w) / 1000.0, " s")
	measuring = true
	for i in frames:
		await get_tree().process_frame
	measuring = false
	print("RENDER n=%d %s q=%s shadows=%s msaa=%s scale=%s | frame %.1f ms (median %.1f) | engine record %.2f ms + setup %.2f ms | gpu(sw) %.1f ms | draw calls %d, objects %d, primitives %d | scripts' frame %.1f ms, physics step %.1f ms" % [
		n_men, behavior, _env("QUALITY", "default"), _env("SHADOWS", "1"), _env("MSAA", "default"), _env("SCALE", "1"),
		_avg_i(frame_us) / 1000.0, _median_i(frame_us) / 1000.0, _avg_f(rec_ms), _avg_f(setup_ms), _avg_f(gpu_ms), int(_avg_i(calls)), int(_avg_i(objs)), int(_avg_i(prims)), _avg_f(proc_ms), _avg_f(phys_ms)])
	get_tree().quit(0)

static func _avg_i(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()

static func _avg_f(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()

static func _median_i(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := Array(a)
	b.sort()
	return float(b[b.size() / 2])
