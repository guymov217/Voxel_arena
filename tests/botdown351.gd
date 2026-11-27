extends Node
## Probe: a bot against a man lying on the sand, alive (state "down", held there): how many blows land, with what, from how far (#351: where the players lay wounded on the
## floor and not dead, the bots did not know how to hit the man lying there). Prints one DOWN351 line a weapon (and SUM351 lines over several seeds).
## DOWN_W: the weapons (comma list), DOWN_D: the bot's difficulty (0.7), DOWN_S: the seconds (20), DOWN_O: the bot's off hand (none), DOWN_P: his personality (standard),
## DOWN_SEEDS: seeds to run each weapon on and sum (3,4,5), DOWN_A: "crawl" (the bot has smashed shins, he fights from the sand too),
## DOWN_V: "dying" (the victim at death's door) or "crawl" (his shins smashed, he stays where he is), DOWN_STAND: the victim is not held down,
## DOWN_BOTH: the victim fights back (a bot too: two men on the sand), DOWN_T: a trace of the bot's body and blade every quarter second, DOWN_F: where the bot first falls.

func _ready() -> void:
	var weapons := (OS.get_environment("DOWN_W") if OS.get_environment("DOWN_W") != "" else "gladius,axe,spear,warhammer,dagger").split(",", false)
	var diff := float(OS.get_environment("DOWN_D")) if OS.get_environment("DOWN_D") != "" else 0.7
	var secs := int(OS.get_environment("DOWN_S")) if OS.get_environment("DOWN_S") != "" else 20
	var seeds := (OS.get_environment("DOWN_SEEDS") if OS.get_environment("DOWN_SEEDS") != "" else "").split(",", false)
	if seeds.is_empty():
		for wn in weapons:
			await _run(wn, diff, secs)
	else:
		var tot := {}
		for wn in weapons:
			for sd in seeds:
				OS.set_environment("DOWN_SEED", sd)
				var r = await _run(wn, diff, secs)
				var a: Array = tot.get(wn, [0, 0.0, 0])
				a[0] += r[0]
				a[1] += r[1]
				a[2] += 1 if r[2] else 0
				tot[wn] = a
		var all_hits := 0
		var all_hp := 0.0
		var all_kills := 0
		for wn in weapons:
			print("SUM351 %-10s hits %3d hp %5.0f kills %d of %d" % [wn, tot[wn][0], tot[wn][1], tot[wn][2], seeds.size()])
			all_hits += tot[wn][0]
			all_hp += tot[wn][1]
			all_kills += tot[wn][2]
		print("SUM351 ALL        hits %3d hp %5.0f kills %d of %d" % [all_hits, all_hp, all_kills, weapons.size() * seeds.size()])
	get_tree().quit()

func _run(wn: String, diff: float, secs: int) -> Array:
	seed(5)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": (int(OS.get_environment("DOWN_SEED")) if OS.get_environment("DOWN_SEED") != "" else 3), "decrees": [], "hazards": []})
	m.me.f.state = "dead"
	var e: Dictionary = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": wn, "off": OS.get_environment("DOWN_O")}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0, "diff": diff, "personality": (OS.get_environment("DOWN_P") if OS.get_environment("DOWN_P") != "" else "standard")})
	var ve: Dictionary = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(0, 0, 2.5), "yaw": PI})
	if OS.get_environment("DOWN_BOTH") == "":
		ve.erase("bot")
		ve.drive = func(_e): return {}
	var f: Fighter = e.f
	var v: Fighter = ve.f
	if OS.get_environment("DOWN_A") == "crawl":
		for n in ["shinL", "shinR"]:
			f.by_name[n].fractured = true
			f.by_name[n].hp = 5.0
	if OS.get_environment("DOWN_V") == "crawl":
		for n in ["shinL", "shinR"]:
			v.by_name[n].fractured = true
			v.by_name[n].hp = 5.0
	var hits := [0, 0.0, -1.0, 0]
	var states := {}
	var dists := []
	var tips := []
	m.combat.hit.connect(func(h):
		if h.get("attacker") == v and h.get("char") == f:
			hits[3] += 1
		if h.get("attacker") == f and h.get("char") == v:
			hits[0] += 1
			hits[1] += float(h.get("dmg", 0.0))
			if hits[2] < 0.0:
				hits[2] = m.combat.time)
	var hp0 := 0.0
	var hpb0 := 0.0
	var died_at := -1.0
	var fell_said := false
	Fighter.trace_falls = OS.get_environment("DOWN_F") != ""
	for i in secs * 120:
		if OS.get_environment("DOWN_BOTH") != "":
			pass
		elif v.state == "stand" and v.alive and OS.get_environment("DOWN_STAND") == "":
			v.fall(30.0, true)
			if OS.get_environment("DOWN_V") == "dying" and v.dying <= 0.0:
				v._fall_dying()
		elif v.state == "down" and v.alive:
			v.down_timer = maxf(v.down_timer, 5.0)
			if OS.get_environment("DOWN_V") == "dying":
				v.dying = maxf(v.dying, 5.0)
		await get_tree().physics_frame
		if i == 60:
			hp0 = v.total_hp()
			hpb0 = f.total_hp()
		if i > 60 and e.bot != null:
			var b: Bot = e.bot
			states[b.state] = int(states.get(b.state, 0)) + 1
			if OS.get_environment("DOWN_T") != "" and OS.get_environment("DOWN_BOTH") != "" and i % 120 == 0:
				var vb = ve.get("bot")
				print("V351 i=%d v.state=%s crawling=%s bot=%s botstate=%s pos=(%.2f %.2f %.2f) can_stand=%s fights_down=%s over=%s" % [i, v.state, v.crawling, vb != null, (vb.state if vb != null else "-"), v.torso.global_position.x, v.torso.global_position.y, v.torso.global_position.z, v.can_stand(), v.fights_down(), m.over])
			if OS.get_environment("DOWN_T") != "" and OS.get_environment("DOWN_BOTH") == "" and i % 30 == 0 and i < 1500:
				var wq: Weapon = f.weapons.R
				var bt: Basis = f.torso.global_transform.basis
				var rel := Vector3.ZERO
				var tipw := Vector3.ZERO
				if wq != null:
					tipw = wq.global_position + PD.quat_of(wq) * Vector3(0, wq.reach * 0.9, 0) - f.torso.global_position
				var hand: Dictionary = b.hand
				print("T351 i=%d state=%s key=%d keyt=%.2f yaw %.2f need %.2f torsoUp=(%.2f %.2f %.2f) torsoFwd=(%.2f %.2f %.2f) pos=(%.2f %.2f %.2f) foe at (%.2f %.2f %.2f) tip rel (%.2f %.2f %.2f) hand=(%.2f %.2f) crawling %s fd %s" % [i, b.state, b.key, b.key_t, f.yaw, atan2(v.torso.global_position.x - f.torso.global_position.x, v.torso.global_position.z - f.torso.global_position.z), bt.y.x, bt.y.y, bt.y.z, bt.z.x, bt.z.y, bt.z.z, f.torso.global_position.x, f.torso.global_position.y, f.torso.global_position.z, v.torso.global_position.x - f.torso.global_position.x, v.torso.global_position.y, v.torso.global_position.z - f.torso.global_position.z, tipw.x, tipw.y, tipw.z, float(hand.x), float(hand.y), f.crawling, f.fights_down()])
			if i % 12 == 0:
				var tp: Vector3 = v.torso.global_position
				var me: Vector3 = f.torso.global_position
				dists.append(Vector2(tp.x - me.x, tp.z - me.z).length())
				var w: Weapon = f.weapons.R
				if w != null:
					var tip: Vector3 = w.global_position + PD.quat_of(w) * Vector3(0, w.reach * 0.9, 0)
					tips.append(tip.distance_to(tp))
		if OS.get_environment("DOWN_F") != "" and f.state == "down" and not fell_said and OS.get_environment("DOWN_A") == "":
			fell_said = true
			print("FELL351 at %.2f s: bot y %.2f, tilt state; blood %.0f, can_stand %s, legs %.2f %.2f, conc %.2f, stagger %.2f" % [i / 120.0, f.torso.global_position.y, f.blood, f.can_stand(), f.leg_func("L"), f.leg_func("R"), f.concussion, f.stagger])
			for fr in f.fall_stack:
				print("   ", fr)
		if not v.alive and died_at < 0.0:
			died_at = i / 120.0
		if not v.alive or not f.alive:
			break
	dists.sort()
	tips.sort()
	print("BACK351 the other man's hits on the bot: %d, the bot's hp lost %.0f" % [hits[3], hpb0 - f.total_hp()])
	print("DOWN351 %-10s p=%s a=%s v=%s o=%s diff %.1f: hits %d dmg %.0f first at %.1f s; died at %.1f; victim %s, hp lost %.0f; bot %s; states %s; torso dist median %.2f; tip-to-torso min %.2f median %.2f; victim torso y %.2f" % [wn, OS.get_environment("DOWN_P"), OS.get_environment("DOWN_A"), OS.get_environment("DOWN_V"), OS.get_environment("DOWN_O"), diff, hits[0], hits[1], hits[2], died_at, v.state, hp0 - v.total_hp(), f.state, states, (dists[dists.size() / 2] if dists.size() > 0 else -1.0), (tips[0] if tips.size() > 0 else -1.0), (tips[tips.size() / 2] if tips.size() > 0 else -1.0), v.torso.global_position.y])
	var lost := hp0 - v.total_hp()
	m.queue_free()
	await get_tree().process_frame
	return [hits[0], lost, died_at >= 0.0]
