extends Node
## Probe: frame by frame, both soles over the sand and whether each foot is stepping, walking.

func _ready() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var f := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "A", "slot": 0})
	for i in 120:
		f.control(1.0 / 120.0, {})
		await get_tree().physics_frame
	for i in 240:
		f.control(1.0 / 120.0, {"mz": 1.0, "sprint": OS.get_environment("RUN") != ""})
		await get_tree().physics_frame
		if i >= 120 and i < 200:
			var row := []
			for sd in ["L", "R"]:
				var sh: VoxelPart = f.by_name["shin" + sd]
				var p := sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
				var g := f._ground_under(p, f.ground_level)
				var ft = f.feet[sd]
				row.append("%s %+.3f %s anc %+.3f" % [sd, p.y - g, "SW" if ft and ft.swing else "--", float(ft.anchor.y) - g if ft else 0.0])
			print("TR %3d %s | torso %.3f" % [i, "  ".join(row), f.torso.global_position.y - f.ground_level])
	get_tree().quit()
