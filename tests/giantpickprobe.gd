extends Node
## A giant reaching for a man on the sand (`-- --probe giantpickprobe`): an empty-handed giant, a
## man put down a stride before him (PICK_Z, 1.6 m), and the giant's grab set going (PICK_TRIES
## times, 3). Every 1/12 s: the giant's trunk (height, lean), the reaching hand's height and how far
## it is from the man, and whether he has hold of him; then whether he lifted him and what he did.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(7)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -14))
	m.me.f.state = "dead"
	var z := float(OS.get_environment("PICK_Z")) if OS.get_environment("PICK_Z") != "" else 1.6
	var tries := int(OS.get_environment("PICK_TRIES")) if OS.get_environment("PICK_TRIES") != "" else 3
	var victim = m.spawn_fighter({"kind": "npc", "name": "Victim", "loadout": {"main": "", "off": ""}, "team": 0, "pos": Vector3(0, 0.02, z), "yaw": PI, "mods": {"toughness": 6.0}})
	victim.drive = func(_e): return {}
	var giant = m.spawn_fighter({"kind": "bot", "name": "Giant", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0, "mods": {"bodyScale": 2.0, "strength": 2.0}, "diff": 0.9})
	var feed := []
	m.feed.connect(func(s): feed.append(s))
	for i in 60:
		await get_tree().physics_frame
	var v: Fighter = victim.f
	var g: Fighter = giant.f
	for k in tries:
		g.teleport(Vector3(0, 0, 0))
		v.teleport(Vector3(0, 0, z))
		v.fall(30.0, true)
		for i in 180:
			v.blood = 100.0
			await get_tree().physics_frame
		var t0: Vector3 = g.torso.global_position
		giant.bot.grab_cool = 0.0
		giant.bot.grab_reach = Bot.GRAB_REACH * Bot.GRAB_DOWN_REACH
		giant.bot.hold_t = 0.0
		var held_at := -1.0
		var low_hand := 9.0
		print("== try %d: the man lies with his trunk at (%.2f, %.2f, %.2f) (%s); the giant's trunk at %.2f m" % [k, v.torso.global_position.x, v.torso.global_position.y, v.torso.global_position.z, "alive" if v.alive else "dead", t0.y])
		for i in 360:
			v.blood = 100.0
			await get_tree().physics_frame
			var side := "R" if not g.weapons.R else "L"
			var hw: Vector3 = g.hand_world(side)
			low_hand = minf(low_hand, hw.y)
			if held_at < 0.0 and g.holding != null:
				held_at = i / 120.0
			if i % 10 == 0 and i < 160:
				var up: Vector3 = PD.quat_of(g.torso) * Vector3.UP
				print("  %.2f s  trunk y %.2f lean %4.0f deg  hand y %.2f, %.2f m from him  holding %s  bot %s" % [i / 120.0, g.torso.global_position.y, rad_to_deg(acos(clampf(up.y, -1, 1))), hw.y, hw.distance_to(v.torso.global_position), g.holding != null, giant.bot.state])
		print("   lowest hand %.2f m; hold %s; the man's trunk now at %.2f m up; feed: %s" % [low_hand, ("at %.2f s" % held_at) if held_at >= 0.0 else "never", v.torso.global_position.y, str(feed.filter(func(s): return s.contains("grab") or s.contains("SLAM") or s.contains("toss")))])
		feed.clear()
		for i in 240:
			await get_tree().physics_frame
	get_tree().quit()
