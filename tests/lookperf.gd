extends Node
## Probe: what the look costs (`-- --probe lookperf`, with a display for the drawing; STYLE=human
## or strong). Eight men in the arena: the time to build and dress one, then a stretch of frames
## standing (the drawing alone) and of fighting (blows, wounds, breaks), each frame's time, the
## script's and the physics' share, what the renderer drew (primitives, draw calls), the memory;
## then the cost of knocking voxels out of a man (a wound) and of a bone broken through.
## MEN: how many (8; 0 measures the arena alone). Prints LOOKPERF lines.

var m

func _frames(n: int) -> Dictionary:
	var dts := []
	var proc := 0.0
	var phys := 0.0
	var prims := 0.0
	var calls := 0.0
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var t1 := Time.get_ticks_usec()
		dts.append(float(t1 - t0) / 1000.0)
		t0 = t1
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	dts.sort()
	var avg := 0.0
	for d in dts:
		avg += d
	avg /= n
	return {"avg": avg, "p50": dts[n / 2], "p95": dts[int(n * 0.95)], "proc": proc / n, "phys": phys / n, "prims": prims / n, "calls": calls / n}

func _ready() -> void:
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	Physique.forced = style
	var n_men := int(OS.get_environment("MEN")) if OS.get_environment("MEN") != "" else 8
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "seed": 11})
	m.me.f.teleport(Vector3(0, 0, -16))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(0, 2.6, -7.5)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.fov = 55.0
	var weapons := ["gladius", "axe", "spear", "warhammer", "longsword", "mace", "trident", "zweihander"]
	var men := []
	var build_ms := 0.0
	for i in n_men:
		var a := TAU * float(i) / float(n_men)
		var pos := Vector3(sin(a) * 2.4, 0.1, cos(a) * 2.4)
		var t0 := Time.get_ticks_usec()
		var e = m.spawn_fighter({"kind": "bot", "name": "Bench %d" % i, "loadout": {"main": weapons[i % weapons.size()], "off": "", "armor": ["helmet", "manica"] if i % 2 == 0 else []}, "team": i % 2, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "diff": 0.8})
		build_ms += float(Time.get_ticks_usec() - t0) / 1000.0
		men.append(e)
	var dress_ms := 0.0
	for e in men:
		var t0 := Time.get_ticks_usec()
		Physique.dress(e.f)
		dress_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	print("LOOKPERF %s spawn %.1f ms a man (dress again %.1f ms a man)" % [style, build_ms / n_men, dress_ms / n_men])
	# Standing still: the drawing alone.
	var keep := []
	for e in men:
		keep.append(e.get("bot"))
		e.erase("bot")
		e.drive = func(_e): return {}
	for i in 60:
		await get_tree().process_frame
	var nf := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 240
	var st := await _frames(nf)
	print("LOOKPERF %s standing: frame %.2f ms (p50 %.2f p95 %.2f) script %.2f physics %.2f prims %.0f calls %.0f" % [style, st.avg, st.p50, st.p95, st.proc, st.phys, st.prims, st.calls])
	if men.is_empty():
		get_tree().quit()   # (MEN=0: the arena's own drawing, to take from the men's)
		return
	# Fighting.
	for k in men.size():
		men[k].erase("drive")
		if keep[k] != null:
			men[k]["bot"] = keep[k]
	for i in 30:
		await get_tree().process_frame
	var fi := await _frames(nf * 2)
	print("LOOKPERF %s fighting: frame %.2f ms (p50 %.2f p95 %.2f) script %.2f physics %.2f prims %.0f calls %.0f" % [style, fi.avg, fi.p50, fi.p95, fi.proc, fi.phys, fi.prims, fi.calls])
	# A wound: voxels knocked out of a man (the cost of each blow's hole).
	var f: Fighter = men[0].f
	var cost := 0.0
	var holes := 0
	for p in f.parts:
		if p.severed or p.missing:
			continue
		var h: Vector3 = p.half_ext
		for k in 3:
			var at := Vector3((k - 1) * h.x * 0.5, (k - 1) * h.y * 0.4, h.z)
			var idx := Array(p.voxels_within(at, p.vf * p.part_scale * 2.2))
			var t0 := Time.get_ticks_usec()
			p.remove_voxels(idx)
			cost += float(Time.get_ticks_usec() - t0) / 1000.0
			holes += 1
	print("LOOKPERF %s wound: %.2f ms a hole (%d holes)" % [style, cost / maxf(1.0, holes), holes])
	# Bones broken through on four limbs, the men still fighting: the frame with them swinging.
	var limbs := ["forearmR", "forearmL", "shinR", "shinL"]
	for k in 4:
		var p2: VoxelPart = men[1 + k].f.by_name.get(limbs[k])
		if p2 and not p2.severed:
			var t0 := Time.get_ticks_usec()
			p2.set_kink(Vector3.ZERO, 0.8, 32 * k)
			print("LOOKPERF %s break %s: %.2f ms" % [style, limbs[k], float(Time.get_ticks_usec() - t0) / 1000.0])
	var br := await _frames(nf)
	print("LOOKPERF %s broken: frame %.2f ms (p50 %.2f p95 %.2f) script %.2f physics %.2f prims %.0f calls %.0f" % [style, br.avg, br.p50, br.p95, br.proc, br.phys, br.prims, br.calls])
	print("LOOKPERF %s memory: static %.1f MB, video %.1f MB" % [style, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	get_tree().quit()
