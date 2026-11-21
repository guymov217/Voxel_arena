extends Node
## F3 in the Ludus yard with N men, on a screen (`-- --probe f3shot298`, under a display: xvfb-run with a software renderer is enough): what the meter
## reads, the draw calls the frame asks of the graphics card and a picture of the yard with the meter on it. The times are those of a software
## renderer and mean little; the draw calls and the men's share are the scene's own. env: N (men, 8), BEHAVIOR (idle|walk), WARM (frames, 240),
## SHOT_DIR (where the picture goes; none: no picture), IDLE, ARM_LOD.

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	var n_men := int(_env("N", "8"))
	var behavior := _env("BEHAVIOR", "walk")
	seed(7)
	Fighter.arm_lod_on = _env("ARM_LOD", "1") != "0"
	Match.human_idle_on = _env("IDLE", "1") != "0"
	var m := Match.new()
	add_child(m)
	var lo := {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"]}
	m.setup({"mode": "yard", "headless": false, "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	var heading := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n_men - 1:
		var a := TAU * float(i) / float(maxi(1, n_men - 1))
		var e = m.spawn_fighter({"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * 3.0, 0.1, sin(a) * 3.0 + 4.0), "yaw": a + PI})
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
	var meter := FpsMeter.new()
	add_child(meter)
	meter.show_meter(true)
	for i in int(_env("WARM", "240")):
		await get_tree().process_frame
	var calls := 0.0
	var objs := 0.0
	var prims := 0.0
	var k := 30
	for i in k:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var asleep := 0
	for e in m.entities:
		if e.kind != "npc" and is_instance_valid(e.f) and e.f.draw_rest_ready:
			asleep += 1
	print("F3SHOT n=%d %s: %.0f draw calls, %.0f objects, %.0f primitives a frame; %d of the men drawn at rest" % [n_men, behavior, calls / k, objs / k, prims / k, asleep])
	print("F3SHOT the meter says: %s" % " | ".join(Array(meter.label.text.split("\n"))))
	var dir := _env("SHOT_DIR", "")
	if dir != "":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f3_%d_%s.png" % [dir, n_men, behavior])
		print("F3SHOT saved %s/f3_%d_%s.png" % [dir, n_men, behavior])
	get_tree().quit()
