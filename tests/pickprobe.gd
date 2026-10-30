extends Node
## Probe: a man with empty hands takes up a weapon lying on the sand (G), weapons long and short,
## lying every which way: is it in his hand in the end, or did it slip from it (taken, then let
## fall: user), or did the hand never get it. OUT: one line per try.

func _ready() -> void:
	var tally := {"held": 0, "dropped": 0, "never": 0}
	var kinds: Array = OS.get_environment("KINDS").split(",") if OS.get_environment("KINDS") != "" else ["spear", "javelin", "trident", "swissSpear", "zweihander", "longsword", "gladius", "axe", "mace", "warhammer"]
	for kind in kinds:
		for ang in [0.0, 45.0, 90.0, 135.0]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
			m.me.f.teleport(Vector3(-10, 0, 0))
			var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {}, "team": 0, "pos": Vector3(0, 0, 4), "yaw": 0.0})
			e.erase("bot")
			e.drive = func(_e): return {}
			var f: Fighter = e.f
			for i in 60:
				await get_tree().physics_frame
			var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
			var at: Vector3 = f.torso.global_position * Vector3(1, 0, 1) + fwd * 0.5 + Vector3(0, 0.12, 0)
			var w: Weapon = m.spawn_loose_weapon(Data.preset(kind), at)
			w.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, deg_to_rad(ang)), at)
			for i in 90:
				await get_tree().physics_frame
			var got = f.grab_nearest(m.combat.loose_weapons)
			var side := "R" if f.reach.R != null else "L"
			var phases := []
			var had := false
			var held_at := -1
			for i in 600:
				await get_tree().physics_frame
				var r = f.reach[side]
				if r != null:
					var g: Vector3 = w.grip_world()
					f.set_meta("pk_last", [i, f.hand_world(side).distance_to(g), Vector2(g.x - f.torso.global_position.x, g.z - f.torso.global_position.z).length(), g.y, f.hand_world(side).y, r.t])
				var ph: String = r.phase if r != null else ("held" if f.weapons[side] == w else "-")
				if phases.is_empty() or phases[-1] != ph:
					phases.append(ph)
				if r != null and r.phase == "fist":
					had = true
				if f.weapons[side] == w and held_at < 0:
					held_at = i
				if r == null and i > 5:
					break
			var res := "held" if f.weapons[side] == w else ("dropped" if had else "never")
			tally[res] += 1
			var pl = f.get_meta("pk_last", [])
			var why := "" if res == "held" else "  last: step %d palm-grip %.2f grip-out %.2f gripY %.2f palmY %.2f t %.2f" % pl if pl.size() == 6 else ""
			print("PICK %-11s %5.0f deg: %-7s %s%s%s" % [kind, ang, res, " -> ".join(phases), (" (%.1f s)" % (held_at / 120.0)) if held_at >= 0 else "", why])
			m.queue_free()
			await get_tree().physics_frame
	print("PICK tally %s" % str(tally))
	get_tree().quit()
