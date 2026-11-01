extends Node
## Gladiator against gladiator, both bots, headless (user: the gladiators should fight like real
## ones with every weapon, and the difficulty should matter): bouts of A against B, each to the
## death or BOUT_S seconds (then the one with more of his blood and body left wins), every blow
## that lands counted. `-- --probe duel`.
## A, B: "diff:weapon[+off][:personality]" (0.8:gladius+roundShield, 0.2:spear); BOUTS (6);
## BOUT_S (60); MATCHUPS: several "A/B" pairs, comma-separated, instead of A and B.

func _side(spec: String) -> Dictionary:
	var parts := spec.split(":")
	var d := float(parts[0])
	var lo := String(parts[1]) if parts.size() > 1 else "gladius"
	var arms := lo.split("+")
	return {"diff": d, "main": arms[0], "off": arms[1] if arms.size() > 1 else "", "personality": String(parts[2]) if parts.size() > 2 else "standard", "name": spec}

func _health(f: Fighter) -> float:
	if not f.alive:
		return 0.0
	return f.blood * (1.0 - 0.6 * f.wound())

func _bout(a: Dictionary, b: Dictionary, secs: float, sd: int) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": sd, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(30, 0, 30))
	var ea = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": a.main, "off": a.off}, "team": 1, "pos": Vector3(0, 0.1, -2.5), "yaw": 0.0, "diff": a.diff, "personality": a.personality})
	var eb = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": b.main, "off": b.off}, "team": 2, "pos": Vector3(0, 0.1, 2.5), "yaw": PI, "diff": b.diff, "personality": b.personality})
	if ea == null or eb == null:
		push_error("duel: a side would not spawn")
		get_tree().quit(1)
		return {}
	var fa: Fighter = ea.f
	var fb: Fighter = eb.f
	var st := {"a_hits": 0, "b_hits": 0, "a_dmg": 0.0, "b_dmg": 0.0, "a_blocked": 0, "b_blocked": 0}
	m.combat.hit.connect(func(h):
		var att = h.get("attacker")
		var vic = h.get("char")
		var res: Dictionary = h.get("res", {})
		var dmg := float(res.get("dmg", 0.0))
		if att == fa and vic == fb:
			st.a_hits += 1
			st.a_dmg += dmg
			if OS.get_environment("HITLOG") != "" and sd == 11:
				var bt: Bot = ea.bot
				var nm := ""
				for k in Bot.ATTACKS:
					if bt.attack == Bot.ATTACKS[k]:
						nm = k
				print("      A HIT %-6s J %5.1f  on %-10s dmg %5.1f  %s %s k%d %.2f stab %s  thrust ext %.2f" % [str(h.get("type")), float(h.get("J", 0.0)), str(h.get("part").part_name) if h.get("part") else "?", dmg, bt.state, nm, bt.key, bt.key_t, bt.stab_at, float(fa.thrust_ext.R)])
		elif att == fb and vic == fa:
			st.b_hits += 1
			st.b_dmg += dmg
		if res.get("blocked", false) or h.get("blocked", false):
			if vic == fa:
				st.a_blocked += 1
			elif vic == fb:
				st.b_blocked += 1)
	# Each keeps to the other.
	ea.target_lock = eb
	eb.target_lock = ea
	var tr := OS.get_environment("TRACE")
	if sd == 11:
		for e in [ea, eb]:
			var w: Weapon = e.f.weapons.R
			print("  %s: %s reach %.2f style %s stats %s two-handed %s" % [e.f.name, w.design.get("name", "?") if w else "fists", w.reach if w else 0.0, Bot.style_of(w), str(w.stats if w else {}), str(e.f.two_handed)])
	var t := 0.0
	var fr := 0
	while t < secs and fa.alive and fb.alive:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		fr += 1
		if tr != "" and sd == 11 and fr % (int(OS.get_environment("TRACE_EVERY")) if OS.get_environment("TRACE_EVERY") != "" else 12) == 0:
			var e = ea if tr == "A" else eb
			var o = eb if tr == "A" else ea
			var bt: Bot = e.bot
			var nm := ""
			for k in Bot.ATTACKS:
				if bt.attack == Bot.ATTACKS[k]:
					nm = k
			var w: Weapon = e.f.weapons.R
			var tip := Vector3.ZERO
			var td := -1.0
			var gp := Vector3.ZERO
			if w:
				var top := 0.0
				for v in w.vox:
					top = maxf(top, float(v[1]))
				tip = w.global_transform * Vector3(0, top * w.vs, 0)
				gp = w.grip_world()
				td = tip.distance_to(o.f.torso.global_position)
			var me: Vector3 = e.f.torso.global_position
			var fwd: Vector3 = o.f.torso.global_position - me
			fwd.y = 0.0
			fwd = fwd.normalized()
			var d := Vector2(o.f.torso.global_position.x - me.x, o.f.torso.global_position.z - me.z).length()
			print("    t %5.2f dist %.2f  %-8s %-8s k%d %.2f thk %.2f bias %s st %3.0f  tip-foe %.2f  tip h %.2f fwd %.2f  grip h %.2f fwd %.2f  foe h %.2f  ext %+.2f hand %.2f,%.2f  %s %s  hits %d/%d" % [t, d, bt.state, nm, bt.key, bt.key_t, bt.think, str(bt.aim_bias), e.f.stamina, td, tip.y, (tip - me).dot(fwd), gp.y, (gp - me).dot(fwd), o.f.torso.global_position.y, float(e.f.thrust_ext.R), float(bt.hand.x), float(bt.hand.y), e.f.state, bt.dodge if bt.dodge_t > 0.0 else "-", st.a_hits, st.b_hits])
	var ha := _health(fa)
	var hb := _health(fb)
	var winner := "A" if (fa.alive and not fb.alive) or (fa.alive == fb.alive and ha > hb) else "B"
	var out := {"winner": winner, "t": t, "a_alive": fa.alive, "b_alive": fb.alive, "ha": ha, "hb": hb}
	out.merge(st)
	m.queue_free()
	await get_tree().physics_frame
	return out

func _ready() -> void:
	var bouts := int(OS.get_environment("BOUTS")) if OS.get_environment("BOUTS") != "" else 6
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 60.0
	var pairs := []
	if OS.get_environment("MATCHUPS") != "":
		for mu in OS.get_environment("MATCHUPS").split(",", false):
			var ab := String(mu).split("/")
			pairs.append([ab[0], ab[1]])
	else:
		pairs.append([OS.get_environment("A") if OS.get_environment("A") != "" else "0.8:gladius", OS.get_environment("B") if OS.get_environment("B") != "" else "0.2:gladius"])
	for pr in pairs:
		var a := _side(pr[0])
		var b := _side(pr[1])
		var wins := {"A": 0, "B": 0}
		var kills := 0
		var tot := {"a_hits": 0, "b_hits": 0, "a_dmg": 0.0, "b_dmg": 0.0, "a_blocked": 0, "b_blocked": 0, "t": 0.0}
		for i in bouts:
			var r: Dictionary = await _bout(a, b, secs, 11 + i * 7)
			wins[r.winner] += 1
			if not (r.a_alive and r.b_alive):
				kills += 1
			for k in tot:
				tot[k] += r[k]
			print("  bout %d: %s wins in %.0f s  (A %d hits %.0f dmg, B %d hits %.0f dmg; blocked A %d B %d)" % [i + 1, r.winner, r.t, r.a_hits, r.a_dmg, r.b_hits, r.b_dmg, r.a_blocked, r.b_blocked])
		print("DUEL %-32s vs %-32s  A won %d of %d (%d to the death)  hits %d/%d  dmg %.0f/%.0f  blocked %d/%d  mean %.0f s" % [pr[0], pr[1], wins.A, bouts, kills, tot.a_hits, tot.b_hits, tot.a_dmg, tot.b_dmg, tot.a_blocked, tot.b_blocked, tot.t / bouts])
	get_tree().quit()
