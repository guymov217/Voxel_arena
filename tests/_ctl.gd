extends Node
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	for main in ["gladius", "axe", "longsword", "warhammer", "spear"]:
		var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": main, "off": ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
		e.erase("bot")
		var hp := {"x": 0.0, "y": 0.2}
		e.drive = func(_e): return {"main": hp, "off": {"x": -0.35, "y": 0.1}, "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
		var f: Fighter = e.f
		for i in 100:
			await get_tree().physics_frame
		var ext := []
		var back := 1.0
		for pt in [[2.0, 0.2], [-2.0, 0.2], [0.0, 1.6], [0.0, -1.6], [2.0, 1.6], [-2.0, -1.4]]:
			hp.x = pt[0]; hp.y = pt[1]
			for i in 110:
				await get_tree().physics_frame
				var yq0 := Quaternion(Vector3.UP, f.yaw).inverse()
				back = minf(back, (yq0 * (PD.quat_of(f.weapons.R) * Vector3.UP)).z)
			var yq := Quaternion(Vector3.UP, f.yaw).inverse()
			var ax: Vector3 = yq * (PD.quat_of(f.weapons.R) * Vector3.UP)
			ext.append("%d/%d" % [rad_to_deg(atan2(ax.x, ax.z)), rad_to_deg(asin(clampf(ax.y, -1, 1)))])
		var bmin := 9.0
		var bmax := -9.0
		var peak := 0.0
		for k in 4:
			hp.x = 1.8 if k % 2 == 0 else -1.8
			hp.y = 0.3
			for i in 60:
				await get_tree().physics_frame
				var w: Weapon = f.weapons.R
				peak = maxf(peak, w.velocity_at(w.global_transform * Vector3(0, w.reach, 0)).length())
				var b := (PD.quat_of(f.arm.R.upper) * Vector3.DOWN).angle_to(PD.quat_of(f.arm.R.fore) * Vector3.DOWN)
				if i > 6:
					bmin = minf(bmin, b); bmax = maxf(bmax, b)
		print("CTL %-10s R %s L %s up %s down %s upR %s downL %s | elbow %.2f..%.2f, blade back-most z %.2f, tip %.1f m/s, standing %s" % [main, ext[0], ext[1], ext[2], ext[3], ext[4], ext[5], bmin, bmax, back, peak, f.state])
		m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
