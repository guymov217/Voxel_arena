extends Node
## How hard the bots' blows land (user: the foes should always strike with as much momentum as
## their weapons can give). A foe of each kind in FOES fights a man who only stands on guard
## (immortal) for BOUT_S seconds a seed; every blow of his that lands is put down: its J, the
## speed of the blade where it struck (against his own trunk), how far out along the blade it
## struck (of its reach: the sweet spot of a blade is its outer third), and how far apart the two
## men stood. `-- --probe swingprobe`. FOES (foe:recruit,foe:brute,foe:executioner,foe:murmillo),
## BOUT_S (40), SEEDS (1,2,3).

func _ready() -> void:
	var foes: Array = Array((OS.get_environment("FOES") if OS.get_environment("FOES") != "" else "foe:recruit,foe:brute,foe:executioner,foe:murmillo").split(","))
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 40.0
	var seeds: Array = Array((OS.get_environment("SEEDS") if OS.get_environment("SEEDS") != "" else "1,2,3").split(",")).map(func(s): return int(s))
	var all := []
	for foe in foes:
		var rows := []
		var starts := 0
		for sd in seeds:
			seed(sd)
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": foe, "immortal": true, "respawn": false, "difficulty": 0.8}, "headless": true, "seed": sd, "decrees": [], "hazards": [],
				"loadout": {"main": "gladius", "off": "", "armor": ["helmet"]}})
			var me: Fighter = m.me.f
			m.me.drive = func(_e): return {"main": {"x": 0.15, "y": 0.35}}
			var e: Dictionary = m.enemies()[0]
			var g: Fighter = e.f
			m.combat.hit.connect(func(h):
				if h.get("char") != me or h.get("weapon") == null or not is_instance_valid(h.weapon) or h.weapon.holder != g:
					return
				var w: Weapon = h.weapon
				var p: Vector3 = h.p
				var v: Vector3 = w.linear_velocity + w.angular_velocity.cross(p - w.global_position) - g.torso.linear_velocity
				var along: float = (p - w.grip_world()).dot(PD.quat_of(w) * Vector3.UP) / maxf(0.1, w.reach)
				var gap := Vector2(me.torso.global_position.x - g.torso.global_position.x, me.torso.global_position.z - g.torso.global_position.z).length()
				rows.append({"J": float(h.J), "v": v.length(), "along": along, "gap": gap, "type": String(h.type)}))
			var was := ""
			for i in int(secs * 120):
				await get_tree().physics_frame
				if not is_instance_valid(me) or not is_instance_valid(g) or not g.alive:
					break
				me.blood = maxf(me.blood, 60.0)
				var st: String = String(e.bot.state) if e.get("bot") else ""
				if st == "attack" and was != "attack":
					starts += 1
				was = st
			m.queue_free()
			await get_tree().process_frame
		var n := rows.size()
		var sum := func(k: String) -> float:
			var s := 0.0
			for r in rows:
				s += float(r[k])
			return s / maxf(1, n)
		var weak := rows.filter(func(r): return float(r.J) < 10.0).size()
		var inner := rows.filter(func(r): return float(r.along) < 0.45).size()
		print("SWING %s: %d blows from %d strokes; J %.1f (weak <10: %d), blade %.1f m/s, struck at %.2f of the blade (inner half: %d), apart %.2f m" % [foe, n, starts, sum.call("J"), weak, sum.call("v"), sum.call("along"), inner, sum.call("gap")])
		all.append([foe, n, starts, sum.call("J"), weak, sum.call("v"), sum.call("along"), inner])
	print("SWING DONE")
	get_tree().quit()
