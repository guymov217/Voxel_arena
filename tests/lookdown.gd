extends Node
## Looking down (user: with one weapon or two he bent right over and fell on the sand): a fighter
## driven like the player, his view tipped down, then his hands pulled low with the button held,
## then both; the most his trunk tilts and whether he goes down. `-- --probe lookdown`.
## LOOKS: which loadouts (all).

const LOADOUTS := {
	"gladius": {"main": "gladius"},
	"gladius+dagger": {"main": "gladius", "off": "dagger"},
	"axe+shield": {"main": "axe", "off": "roundShield"},
	"warhammer": {"main": "warhammer"},
	"zweihander": {"main": "zweihander"},
	"zweihander1h": {"main": "zweihander", "grip": true},
	"longsword2h": {"main": "longsword", "grip": true},
	"spear": {"main": "spear"},
	"mace+axe": {"main": "mace", "off": "axe"},
}

func _ready() -> void:
	var want := OS.get_environment("LOOKS").split(",", false)
	for nm in LOADOUTS:
		if not want.is_empty() and not want.has(nm):
			continue
		var lo: Dictionary = LOADOUTS[nm]
		for case in (OS.get_environment("CASES").split(",", false) if OS.get_environment("CASES") != "" else PackedStringArray(["idle", "look", "look+low", "look+low2", "low", "look+walk", "look+low+walk"])):
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
			m.me.f.teleport(Vector3(-12, 0, 0))
			var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": lo.main, "off": lo.get("off", "")}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
			e.erase("bot")
			var f: Fighter = e.f
			var st := {"t": 0.0, "grip": bool(lo.get("grip", false))}
			e.drive = func(_e):
				st.t += 1.0 / 120.0
				var t: float = st.t
				var inp := {"main": {"x": 0.1, "y": 0.15}, "off": {"x": -0.35, "y": 0.1}, "look": {"yaw": 0.0, "pitch": 0.0}}
				if st.grip and t > 0.3:
					inp.grip = true
					st.grip = false
				if t < 1.0:
					return inp
				var k := clampf((t - 1.0) / 0.8, 0.0, 1.0)
				if case.begins_with("look"):
					inp.look.pitch = -1.45 * k
				if case.contains("low"):
					inp.main = {"x": 0.1, "y": lerpf(0.15, -1.6, k)}
					inp.power = true
					if case.contains("low2"):
						inp.off = {"x": -0.35, "y": lerpf(0.1, -1.6, k)}
				if case.contains("walk") and t > 2.0:
					inp.mz = 1.0 if int(t / 1.5) % 2 == 0 else -1.0
				return inp
			var worst := 0.0
			var fell := false
			var fell_at := -1.0
			for i in 120 * 6:
				await get_tree().physics_frame
				var up: Vector3 = f.torso.global_transform.basis.y.normalized()
				worst = maxf(worst, rad_to_deg(acos(clampf(up.y, -1.0, 1.0))))
				if f.state != "stand" and not fell:
					fell = true
					fell_at = st.t
				if OS.get_environment("TRACE") != "" and i % 30 == 0:
					var tb: Basis = f.torso.global_transform.basis
					var yq := Quaternion(Vector3.UP, f.yaw)
					var lu: Vector3 = yq.inverse() * tb.y.normalized()
					var w = f.weapons.R
					var tip: Vector3 = (w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)) if w else Vector3.ZERO
					print("  t %.2f tilt %5.1f fwd %5.1f side %5.1f stoop %.2f hand %s tip_y %.2f torso_y %.2f state %s" % [st.t, rad_to_deg(acos(clampf(tb.y.normalized().y, -1, 1))), rad_to_deg(atan2(lu.z, lu.y)), rad_to_deg(atan2(lu.x, lu.y)), f.stoop, str((yq.inverse() * (f.hand_world("R") - f.torso.global_position)).snapped(Vector3(0.01, 0.01, 0.01))), tip.y, f.torso.global_position.y, f.state])
			print("LOOKDOWN %-15s %-14s two=%s tilt_max %5.1f deg  fell %s %s" % [nm, case, str(f.two_handed), worst, str(fell), ("at %.2f s" % fell_at) if fell else ""])
			m.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
