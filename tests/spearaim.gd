extends Node
## Where a couched spear really points for a hand mark (bots' spears were up over the other man's
## head: duel.gd): for several marks, standing and on the move, the pitch and the turn aside from
## the grip to the point, against what the mark asks. `-- --probe spearaim`; WEAPON (spear).

func _ready() -> void:
	var wk := OS.get_environment("WEAPON") if OS.get_environment("WEAPON") != "" else "spear"
	var cases := [[0.0, 0.0, 0.0], [0.0, -0.3, 0.0], [0.0, 0.3, 0.0], [-0.5, 0.0, 0.0], [0.5, 0.0, 0.0], [-0.5, -0.3, 0.0], [0.0, 0.0, 1.0], [0.0, -0.3, 1.0], [0.0, 0.0, -1.0], [0.0, -0.3, -1.0]]
	for cs in cases:
		var hx: float = cs[0]
		var hy: float = cs[1]
		var mz: float = cs[2]
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		f.is_bot = true
		var st := {"t": 0.0}
		m.me.drive = func(_e):
			st.t += 1.0 / 120.0
			var inp := {"main": {"x": hx, "y": hy}, "faceAt": f.torso.global_position + Vector3(0, 0, 5)}
			if st.t > 1.0:
				inp.mz = mz
			return inp
		var pit := 0.0
		var yw := 0.0
		var n := 0
		var av := 0.0
		for i in 360:
			await get_tree().physics_frame
			if i >= 180:
				var w: Weapon = f.weapons.R
				var d: Vector3 = PD.quat_of(w) * Vector3.UP
				pit += rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
				yw += rad_to_deg(wrapf(atan2(d.x, d.z) - f.yaw, -PI, PI))
				av += w.angular_velocity.length()
				n += 1

		print("SPEARAIM %s hand %+.1f,%+.1f walk %+.0f  asked pitch %+5.1f turn %+5.1f   real pitch %+5.1f turn %+5.1f  fix %s  spin %.2f" % [wk, hx, hy, mz, rad_to_deg(hy * 0.55), rad_to_deg(-hx * 0.6), pit / n, yw / n, str(f.spear_true.R), av / n])
		m.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
