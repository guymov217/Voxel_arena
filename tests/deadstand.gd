extends Node
## Every creature killed where it stands (user: a beast that dies sometimes dies on its feet and
## stays standing): four seconds on, how upright its trunk still is and how high it still stands
## against its height alive. `-- --probe deadstand`. BEASTS: which (all).

func _ready() -> void:
	var want := OS.get_environment("BEASTS").split(",", false)
	var bad := []
	for sp in Data.beasts.keys():
		if not want.is_empty() and not want.has(sp):
			continue
		for how in ["wounds", "walking"]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
			m.me.f.teleport(Vector3(14, 0, 14))
			var e = m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
			var b: Beast = e.f
			for i in 150:
				await get_tree().physics_frame
			var h0: float = b.torso.global_position.y
			if how == "walking":
				b.target = m.me.f
				for i in 60:
					await get_tree().physics_frame
			b.die("wounds")
			for i in 480:
				await get_tree().physics_frame
			var up: float = b.torso.global_transform.basis.y.normalized().y
			var h1: float = b.torso.global_position.y
			var standing := up > 0.8 and h1 > h0 * 0.75
			if standing:
				bad.append("%s(%s)" % [sp, how])
			print("DEAD %-10s %-8s up %.2f height %.2f of %.2f %s" % [sp, how, up, h1, h0, "  <-- STILL STANDING" if standing else ""])
			m.queue_free()
			await get_tree().physics_frame
	print("DEAD standing: %s" % ", ".join(bad))
	get_tree().quit()
