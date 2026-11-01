extends Node
## The sharp voxels of blades with corners, close up (user: the blade's corners do not join): an
## axe and an executioner's axe (their horns run past the head), a dagger, and a blade rounded at
## the tip in steps, each from the flat and from along the edge. `-- --probe bladeshots`, needs a
## display; PNGs to SHOT_DIR, named with SHOT_TAG. DESIGNS: which (axe,executioner,dagger,rounded).

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var tag := OS.get_environment("SHOT_TAG")
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("blade_%s%s.png" % [tag + "_" if tag != "" else "", name_]))
	print("saved ", name_)

## A broad blade a voxel thick, rounded at its point in steps as a smith would draw one: the haft
## below, a guard, the body above, both sides and the rounded tip all edge.
static func rounded_blade() -> Dictionary:
	var vox := []
	for y in 6:
		vox.append([0, y, 0, "wood", "grip"])
	for x in range(-4, 5):
		vox.append([x, 6, 0, "iron", "blunt"])
	# Half its width row by row: straight up the sides, then cut back in steps round the tip.
	var half := {7: 3, 8: 3, 9: 3, 10: 3, 11: 3, 12: 3, 13: 3, 14: 3, 15: 2, 16: 2, 17: 1, 18: 0}
	var cells := {}
	for y in half:
		for x in range(-int(half[y]), int(half[y]) + 1):
			cells[Vector2i(x, y)] = true
	for c in cells:
		var open := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			if not cells.has(c + d):
				open = true
		vox.append([c.x, c.y, 0, "steel", "edge" if open else "blunt"])
	return {"name": "Rounded blade", "kind": "weapon", "voxels": vox}

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": "none"}})
	var m: Match = menu.match_
	for i in 60:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var base: Vector3 = m.me.f.torso.global_position + Vector3(0, 0.4, 3.0)
	var designs := {
		"axe": Data.preset("axe"),
		"executioner": Data.preset("executionerAxe"),
		"dagger": Data.preset("dagger"),
		"rounded": rounded_blade(),
	}
	var only := OS.get_environment("DESIGNS").split(",", false)
	var i := 0
	for key in designs:
		if not only.is_empty() and not only.has(key):
			continue
		var w := Weapon.new()
		w.freeze = true
		m.add_child(w)
		w.setup(designs[key], 1.0)
		var at := base + Vector3(i * 1.2, 0, 0)
		w.global_transform = Transform3D(Basis(), at)
		i += 1
		for k in 4:
			await get_tree().physics_frame
		# The head: where the edge voxels are.
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for v in w.vox:
			if str(v[4]) == "edge" or str(v[4]) == "point":
				var q := w.global_transform * (Vector3(v[0], v[1], v[2]) * w.vs)
				lo = lo.min(q)
				hi = hi.max(q)
		var mid := (lo + hi) * 0.5
		var size := maxf(0.12, (hi - lo).length())
		cam.global_position = mid + Vector3(0.0, 0.0, size * 2.4)
		cam.look_at(mid, Vector3.UP)
		await _save(key + "_flat")
		cam.global_position = mid + Vector3(size * 1.9, size * 0.5, size * 1.2)
		cam.look_at(mid, Vector3.UP)
		await _save(key + "_edge")
		cam.global_position = mid + Vector3(size * 0.7, size * 1.4, size * 1.6)
		cam.look_at(mid, Vector3.UP)
		await _save(key + "_above")
	get_tree().quit()
