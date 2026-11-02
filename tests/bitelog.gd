extends Node
## Where a beast's bites go (the sweep: a dragon lunging at the player every second or two for
## half a minute and not one bite landing): for every strike of a biting head, what it touched
## (the man, his weapon, nothing), how close it came to him and how fast it was going.
## `-- --probe bitelog`. FOE (dragon), MINE (spear), SEED (57), BOUT_S (30).

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "dragon"
	var mine := OS.get_environment("MINE") if OS.get_environment("MINE") != "" else "spear"
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 57
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 30.0
	seed(sd)
	var arms := mine.split("+")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": foe, "immortal": true, "respawn": false, "difficulty": 0.7}, "autopilot": true, "headless": true, "seed": sd, "decrees": [], "hazards": [], "loadout": {"main": arms[0], "off": arms[1] if arms.size() > 1 else ""}})
	var me: Fighter = m.me.f
	var b = null
	for e in m.enemies():
		b = e.f
	var landed := [0]
	m.combat.hit.connect(func(h):
		if h.get("char") == me and h.get("attacker") == b:
			landed[0] += 1)
	var cur := {}      # head -> the strike being watched
	var strikes := 0
	var summary := {"body": 0, "weapon": 0, "nothing": 0}
	for i in int(secs * 120.0):
		await get_tree().physics_frame
		if b == null or not is_instance_valid(b) or not b.alive:
			break
		for h in b.biting_heads():
			var on: bool = b.strikes.has(h) and float(b.strikes[h]) > 0.0 and not b.wind.has(h)
			if on and not cur.has(h):
				cur[h] = {"t": m.time, "min_d": INF, "body": 0, "weapon": 0, "vmax": 0.0, "spd_at_touch": 0.0, "head_y": h.global_position.y, "my_y": me.torso.global_position.y, "min_hy": INF, "pitch": 0.0, "dur": 0.0}
				strikes += 1
			if cur.has(h):
				var s: Dictionary = cur[h]
				var near := INF
				for p in me.parts:
					if is_instance_valid(p) and not p.severed:
						near = minf(near, h.global_position.distance_to(p.global_position))
				s.min_d = minf(float(s.min_d), near)
				s.vmax = maxf(float(s.vmax), h.linear_velocity.length())
				s.min_hy = minf(float(s.min_hy), h.global_position.y)
				s.dur = float(s.dur) + 1.0 / 120.0
				var nk = h.parent_part
				if nk and is_instance_valid(nk) and nk.parent_part:
					var nu: Vector3 = nk.global_transform.basis.y.normalized()
					var bu: Vector3 = nk.parent_part.global_transform.basis.y.normalized()
					s.pitch = maxf(float(s.pitch), rad_to_deg(nu.angle_to(bu)))
				for body in h.get_colliding_bodies():
					if body is VoxelPart and body.fighter == me:
						s.body += 1
						s.spd_at_touch = maxf(float(s.spd_at_touch), (h.linear_velocity - body.linear_velocity).length())
					elif body is Weapon and body.holder == me:
						s.weapon += 1
				if not on:
					var what := "body" if s.body > 0 else ("weapon" if s.weapon > 0 else "nothing")
					summary[what] += 1
					print("%5.1f strike %.2f s: touched %-7s nearest %.2f m  head y %.2f -> lowest %.2f, neck bent %.0f deg from the body, man trunk y %.2f, dist %.2f" % [float(s.t), float(s.dur), what, float(s.min_d), float(s.head_y), float(s.min_hy), float(s.pitch), float(s.my_y), b.torso.global_position.distance_to(me.torso.global_position)])
					cur.erase(h)
	print("strikes %d: %s; bites that landed %d" % [strikes, str(summary), landed[0]])
	get_tree().quit()
