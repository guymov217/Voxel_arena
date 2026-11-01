extends Node
## Thrusts aimed every way (user: the thrust must go exactly where the blade is aimed, and land
## hard): the blade set on a line with the mouse, then the thrust key held. How far the stab goes
## off the line the blade was on when the key went down (degrees), how far the point travels
## along it, how fast, and what it does to a man standing on that line. `-- --probe thrustprobe`.
## WEAPONS: which (gladius,spear,dagger,longsword2h).

var AIMS := {
	"level": {"x": 0.0, "y": 0.15},
	"up": {"x": 0.0, "y": 0.8},
	"down": {"x": 0.0, "y": -0.5},
	"left": {"x": 0.9, "y": 0.2},
	"right": {"x": -0.9, "y": 0.2},
}

func _tip(w: Weapon) -> Vector3:
	return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)

func _ready() -> void:
	var want := OS.get_environment("WEAPONS").split(",", false)
	if want.is_empty():
		want = PackedStringArray(["gladius", "spear", "dagger", "longsword2h"])
	var only_aim := OS.get_environment("AIM")
	for wn in want:
		var key := String(wn).replace("2h", "")
		for an in AIMS:
			if only_aim != "" and an != only_aim:
				continue
			for with_foe in [false, true]:
				var m := Match.new()
				add_child(m)
				m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
				m.me.f.teleport(Vector3(-12, 0, 8))
				var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": key}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
				e.erase("bot")
				var f: Fighter = e.f
				var st := {"t": 0.0, "thrust": 0.0, "grip": String(wn).ends_with("2h")}
				var aim: Dictionary = AIMS[an]
				e.drive = func(_e):
					st.t += 1.0 / 120.0
					var inp := {"main": aim, "off": {"x": -0.35, "y": 0.1}, "power": true, "thrust": st.thrust, "look": {"yaw": 0.0, "pitch": 0.0}}
					if st.grip and st.t > 0.3:
						inp.grip = true
						st.grip = false
					return inp
				for i in 200:
					await get_tree().physics_frame
				var foe: Fighter = null
				var hits := []
				if with_foe:
					var w0: Weapon = f.weapons.R
					var ax0: Vector3 = PD.quat_of(w0) * Vector3.UP
					var spot := _tip(w0) + ax0 * 0.35
					var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {}, "team": 2, "pos": Vector3(spot.x, 0, spot.z) + Vector3(ax0.x, 0, ax0.z).normalized() * 0.15, "yaw": PI})
					d.erase("bot")
					d.drive = func(_e): return {}
					foe = d.f
					m.combat.hit.connect(func(h): if h.get("char") == foe and h.get("weapon") == f.weapons.R: hits.append(h))
					for i in 30:
						await get_tree().physics_frame
				var w: Weapon = f.weapons.R
				var ax: Vector3 = PD.quat_of(w) * Vector3.UP
				var tip0 := _tip(w)
				var far := tip0
				var trunk0 := f.torso.global_position
				var fell := false
				var vmax := 0.0
				var prev := tip0
				st.thrust = 1.0
				for i in 72:
					await get_tree().physics_frame
					var tp := _tip(w)
					if OS.get_environment("TRACE") != "" and i % int(OS.get_environment("TRACE_EVERY") if OS.get_environment("TRACE_EVERY") != "" else "6") == 0:
						var tl = f.thrust_line.R
						var mark := Vector3.ZERO
						if tl != null and tl.has("o_w"):
							mark = (tl.o_w as Vector3) + (tl.dir_w as Vector3) * float(f.thrust_ext.R)
						print("  t %d line %s ext %.2f hand %s tip %s  hand off its mark %.2f m  tip speed %.1f m/s  trunk moved %.2f m" % [i, "on" if tl != null else "off", float(f.thrust_ext.R), str((f.hand_world("R") - f.torso.global_position).snapped(Vector3(0.01, 0.01, 0.01))), str((tp - f.torso.global_position).snapped(Vector3(0.01, 0.01, 0.01))), f.hand_world("R").distance_to(mark) if mark != Vector3.ZERO else -1.0, (tp - prev).length() * 120.0, (f.torso.global_position - trunk0).length()])
					if f.state != "stand":
						fell = true
					vmax = maxf(vmax, (tp - prev).length() * 120.0 - f.torso.linear_velocity.length())
					prev = tp
					if (tp - tip0).dot(ax) > (far - tip0).dot(ax):
						far = tp
				st.thrust = 0.0
				var mv := far - tip0
				var off_deg := rad_to_deg(mv.angle_to(ax)) if mv.length() > 0.02 else -1.0
				# Which way off the line: up (+) or down, and to his left (+) or right, in cm.
				var side_v := Vector3.UP.cross(ax).normalized() if absf(ax.y) < 0.95 else Vector3.RIGHT
				var up_v := ax.cross(side_v).normalized()
				var line := "THRUST %-11s %-5s %s went %.2f m off-line %5.1f deg (up %+.0f cm, left %+.0f cm)  tip speed %.1f m/s" % [wn, an, "foe " if with_foe else "air ", mv.dot(ax), off_deg, mv.dot(up_v) * 100.0, mv.dot(side_v) * 100.0, vmax]
				if fell:
					line += "  FELL (%s)" % f.state
				if with_foe:
					var Jmax := 0.0
					var dmg := 0.0
					var removed := 0
					for h in hits:
						Jmax = maxf(Jmax, float(h.J))
						dmg += float(h.res.get("dmg", 0.0))
						for r in h.res.get("removed", []):
							removed += (r.indices as Array).size()
					line += "  hits %d J %.0f dmg %.1f voxels %d" % [hits.size(), Jmax, dmg, removed]
				print(line)
				m.queue_free()
				await get_tree().physics_frame
	get_tree().quit()
