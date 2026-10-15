extends Node
## The smith at his anvil (`-- --probe smithshot`, needs a display): the yard's smith hammering
## at the anvil with his hammer, from beside the smithy. PNGs to SHOT_DIR/smith_<n>.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "roundShield"}})
	m.me.f.teleport(Vector3(0, 0, 0))
	m.set_process(false)
	var cam: Camera3D = m.cam
	cam.fov = 45.0
	var smith = null
	for k in m.yard.keepers:
		if String(k.display_name).to_lower().contains("smith"):
			smith = k
	var sp: Vector3 = Yard.STATIONS.smith.p
	var out_v := Vector3(sp.x, 0, sp.z).normalized()
	var side := Vector3(-out_v.z, 0, out_v.x)
	var n := 0
	for i in 6 * 60:
		await get_tree().physics_frame
		if i % 60 == 20 and smith:
			var tp: Vector3 = smith.torso.global_position
			cam.global_position = tp + side * 3.4 + Vector3(0, 0.6, 0) - out_v * 0.4
			cam.look_at(tp + out_v * 0.5 + Vector3(0, -0.2, 0), Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			n += 1
			get_viewport().get_texture().get_image().save_png(out.path_join("smith_%d.png" % n))
			var w = smith.weapons.R
			print("smith %d weapon %s at %s" % [n, str(w.design.name) if w else "none", str(tp)])
	get_tree().quit()
