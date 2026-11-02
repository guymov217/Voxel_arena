extends Node
## How long the forge takes over each block put on or taken off (user: the forge should run
## smoothly), for a small weapon and for one near the anvil's limit, and what a frame of the
## swing preview costs. `-- --probe forgeperf`.

func _big_design() -> Dictionary:
	var vox := []
	for y in 8:
		vox.append([0, y, 0, "wood", "grip"])
	# A broad slab of a blade: 9 wide, 2 thick, 60 long (~1100 voxels).
	for y in range(8, 68):
		for x in range(-4, 5):
			for z in [0, 1]:
				vox.append([x, y, z, "steel", "edge" if absi(x) == 4 else "blunt"])
	return {"name": "Slab", "kind": "weapon", "voxels": vox}

func _ready() -> void:
	for which in ["gladius", "slab"]:
		var f = load("res://scripts/ui/forge.gd").new()
		add_child(f)
		var d: Dictionary = Data.preset("gladius") if which == "gladius" else _big_design()
		f.free_build = true
		f.open(d, 99999, func(_d, _c): pass)
		f.mode = "voxels"
		f.mirror = false
		f.mirror_z = false
		for i in 3:
			await get_tree().process_frame
		# Blocks put on the top, one at a time, then taken off.
		var top := Vector3i.ZERO
		for c in f.cells:
			if c.y > top.y:
				top = c
		var times := []
		for i in 20:
			var c := top + Vector3i(0, i + 1, 0)
			var t0 := Time.get_ticks_usec()
			f._place([c])
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		var rtimes := []
		for i in 20:
			var c := top + Vector3i(0, 20 - i, 0)
			var t0 := Time.get_ticks_usec()
			f._remove([c])
			rtimes.append((Time.get_ticks_usec() - t0) / 1000.0)
		var hov := []
		for i in 20:
			var t0 := Time.get_ticks_usec()
			f._hover(Vector2(400 + i * 5, 300))
			hov.append((Time.get_ticks_usec() - t0) / 1000.0)
		# The swing preview: a frame of it.
		f.swing_t = 0.0
		var sw := []
		for i in 10:
			var t0 := Time.get_ticks_usec()
			f._process(1.0 / 60.0)
			sw.append((Time.get_ticks_usec() - t0) / 1000.0)
		# Where the time goes: each piece of a change on its own.
		var parts := {}
		var t1 := Time.get_ticks_usec()
		f._rebuild()
		parts["rebuild"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		f._update_texts()
		parts["texts"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		var dn: Dictionary = f._design_now()
		parts["design_now"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		ForgeLib.compute_stats(dn)
		parts["stats"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		var jobs := {}
		var faces := {}
		for kk in f.cells:
			jobs[kk] = str(f.cells[kk][1])
		var memo := {}
		for kk in f.cells:
			VoxelPart.taper_code(jobs, kk, -1, faces, memo)
		parts["taper"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		ForgeLib.attached(f.cells, [top + Vector3i(0, 1, 0)])
		parts["attached"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		ForgeLib.kept_piece(f.cells)
		parts["kept_piece"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		f._push_undo()
		parts["undo"] = (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		f._value_now()
		parts["value"] = (Time.get_ticks_usec() - t1) / 1000.0
		print("FORGEPARTS %s %s" % [which, str(parts)])
		var avg := func(a: Array) -> float:
			var s := 0.0
			for x in a:
				s += x
			return s / maxf(1.0, a.size())
		print("FORGEPERF %-8s %4d voxels  put on %.2f ms (max %.2f)  take off %.2f ms  hover %.2f ms  swing frame %.2f ms" % [which, f.cells.size(), avg.call(times), times.max(), avg.call(rtimes), avg.call(hov), avg.call(sw)])
		f.queue_free()
		await get_tree().process_frame
	get_tree().quit()
