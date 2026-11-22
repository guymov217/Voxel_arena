extends Node
## (scratch) What a man is made of, as the renderer sees it: the nodes, the meshes, the multimesh instances and the spawn time, bare and in each piece of armour (`-- --probe nodes298`).
## env: IDS (comma list of armour pieces, "none" for bare), HOW many men are spawned one after another (the first costs more than the next: caches), HEADLESS.

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _count(root: Node) -> Dictionary:
	var c := {"nodes": 0, "mesh_instances": 0, "multimesh_instances": 0, "mm_instances": 0, "mm_visible": 0, "surfaces": 0, "visible_geo": 0, "other_geo": 0}
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		c.nodes += 1
		if n is MeshInstance3D:
			c.mesh_instances += 1
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				c.surfaces += mi.mesh.get_surface_count()
			if mi.is_visible_in_tree():
				c.visible_geo += 1
		elif n is MultiMeshInstance3D:
			c.multimesh_instances += 1
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				c.mm_instances += mm.instance_count
				c.mm_visible += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				if mm.mesh != null:
					c.surfaces += mm.mesh.get_surface_count()
			if (n as MultiMeshInstance3D).is_visible_in_tree():
				c.visible_geo += 1
		elif n is GeometryInstance3D:
			c.other_geo += 1
		for ch in n.get_children():
			stack.append(ch)
	return c

func _ready() -> void:
	seed(7)
	var ids := _env("IDS", "none")
	var how := int(_env("HOW", "3"))
	Fighter.process_in_headless = true
	var m := Match.new()
	add_child(m)
	var armor: Array = [] if ids == "none" else Array(ids.split(","))
	var lo := {"main": "gladius", "off": "scutum", "armor": armor}
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": _env("HEADLESS", "1") == "1", "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	await get_tree().process_frame
	await get_tree().process_frame
	var base := _count(m)
	for k in how:
		var t0 := Time.get_ticks_usec()
		var spec := {"kind": "bot", "name": "S%d" % k, "loadout": lo.duplicate(true), "team": 10 + k, "pos": Vector3(3 + k * 2, 0.1, 4), "yaw": 0.0}
		var e = m.spawn_fighter(spec)
		var t1 := Time.get_ticks_usec()
		# (the staged builds finish over the next frames: wait for them and count that too)
		var frames := 0
		while frames < 600:
			await get_tree().process_frame
			frames += 1
			if is_instance_valid(e.f) and not e.f.get("building"):
				break
		var t2 := Time.get_ticks_usec()
		var now := _count(m)
		var d := {}
		for key in now:
			d[key] = int(now[key]) - int(base[key])
		print("SPAWN %s #%d: spawn call %.1f ms, with the staged build %.1f ms (%d frames) | +nodes %d, +mesh instances %d, +multimeshes %d (%d instances), +surfaces %d, visible geometry %d" % [ids, k, (t1 - t0) / 1000.0, (t2 - t0) / 1000.0, frames, d.nodes, d.mesh_instances, d.multimesh_instances, d.mm_instances, d.surfaces, d.visible_geo])
		base = now
	get_tree().quit(0)
