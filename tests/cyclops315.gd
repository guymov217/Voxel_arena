extends Node
## #315 probe: does a bare-handed giant (Polyphemus) or a Cyclops who has lost his weapon hurt a man with his fists, feet and throws?
## `-- --probe cyclops315` (one worker thread, --fixed-fps 120). For each giant, standing and lying victim (a plain man; _run can also take
## a player or a guest's fighter, with or without armour) it prints the hits the giant landed on him over 30 s, what the man lost (blood,
## the parts' hp) and whether he lived. (The bout's own rule for a giant who cannot stand: tests/test_giants.gd.)

const ARMOUR := ["helmet", "lorica", "manica", "greaves"]

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run(giant: String, victim: String, disarm: bool, armour: bool, lying := false) -> String:
	seed(5)
	var m := Match.new()
	add_child(m)
	var o := {"mode": "training", "training": {"enemy": "none", "respawn": false, "immortal": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": "", "armor": ARMOUR if armour else []}}
	if victim == "remote":
		o["mode"] = "endless"
		o.erase("training")
		o["role"] = "host"
		o["endless"] = {"seed": 11}
		o["peers"] = [{"id": 7, "name": "Friend", "loadout": {"main": "", "off": "", "armor": ARMOUR if armour else []}, "kit": {}}]
	m.setup(o)
	var man: Fighter
	var ve = null
	if victim == "remote":
		m.me.f.teleport(Vector3(0, 0, -18))
		m.me.drive = func(_e): return {}
		var fe = m.humans().filter(func(x): return x.kind == "remote")[0]
		fe.drive = func(_e): return {}
		man = fe.f
		man.teleport(Vector3(0, 0, 0))
	elif victim == "player":
		man = m.me.f
		man.teleport(Vector3(0, 0, 0))
		m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.0}}
	else:
		m.me.f.teleport(Vector3(0, 0, -18))
		m.me.drive = func(_e): return {}
		ve = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "", "off": "", "armor": ARMOUR if armour else []}, "team": 0, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		ve.erase("bot")
		ve.drive = func(_e): return {}
		man = ve.f
	var spec: Dictionary = m.enemy_spec({"e": giant, "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 3.5)
	spec.yaw = PI
	var ge = m.spawn_fighter(spec)
	var g: Fighter = ge.f
	if disarm:
		for side in ["R", "L"]:
			var w = g.release(side)
			if w != null:
				m.combat.loose_weapons.erase(w)
				w.queue_free()
	await _steps(60)
	if lying:
		man.cord_legs = 0.0
		man.fall(90.0, true)
		await _steps(30)
	var armed: bool = g.weapons.R != null or g.weapons.L != null
	var hits := []
	m.combat.hit.connect(func(h):
		if h.get("char") == man and h.get("attacker") == g:
			hits.append({"J": float(h.get("J", 0.0)), "kick": bool(h.get("kick", false)), "punch": bool(h.get("punch", false)), "landing": bool(h.get("landing", false)), "dmg": float(h.get("dmg", -1.0))}))
	var hp0 := 0.0
	for p in man.parts:
		hp0 += p.hp
	var blood0 := man.blood
	var died_at := -1.0
	for i in 120 * 30:
		await get_tree().physics_frame
		if not man.alive:
			died_at = float(i) / 120.0
			break
	var hp1 := 0.0
	for p in man.parts:
		hp1 += p.hp
	var kicks := 0
	var punches := 0
	var lands := 0
	var jsum := 0.0
	for h in hits:
		kicks += 1 if h.kick else 0
		punches += 1 if h.punch else 0
		lands += 1 if h.landing else 0
		jsum += h.J
	var line := "%-9s on %-6s%s %s%s: hits %3d (kick %d, punch %d, landing %d, sumJ %.0f); blood %.0f -> %.0f, parts' hp %.0f -> %.0f; %s; giant's state %s, grabbed %s" % [giant, victim, " LYING" if lying else "", "disarmed" if disarm else ("armed" if armed else "bare"), " IN ARMOUR" if armour else "", hits.size(), kicks, punches, lands, jsum, blood0, man.blood, hp0, hp1, ("DIED at %.1f s" % died_at) if died_at >= 0.0 else "lived", g.state, str(man.grabbed_by != null)]
	m.queue_free()
	await _steps(4)
	return line

func _ready() -> void:
	await _steps(2)
	for cfg in [["giant", false], ["cyclops", true]]:
		for lying in [false, true]:
			var l: String = await _run(cfg[0], "man", cfg[1], false, lying)
			print("CYC315 ", l)
	get_tree().quit()
