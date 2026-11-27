extends Node
## Knocked down and left alive, a man gets up again; and a blade opens the same wound in a
## giant as in a man (the wound is the size of the weapon, not of the one it is in).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -12))
	return m

func _man(m: Match, pos: Vector3, mods := {}) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI, "mods": mods})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func test_a_man_knocked_out_comes_round_and_stands() -> void:
	var m := _match()
	for why in ["concussion", "blood"]:
		var f := _man(m, Vector3(0, 0, 0))
		await _steps(30)
		if why == "concussion":
			f.concussion = 1.0
		else:
			f.blood = 10.0
		f.fall(99.0, true)
		await _steps(60)
		t.check(f.state != "stand", "%s: he is down" % why)
		var up := false
		for i in 120 * 14:
			await get_tree().physics_frame
			if f.state == "stand":
				up = true
				break
		t.check(up and f.alive, "%s: he comes round and stands again (%s, blood %.0f, concussion %.2f)" % [why, f.state, f.blood, f.concussion])
		m.entities.erase(m.entity_of(f))
		m.combat.fighters.erase(f)
		f.teleport(Vector3(20, 0, 20 + (5 if why == "blood" else 0)))
	m.queue_free()

func test_a_cut_is_the_size_of_the_blade_in_a_giant_as_in_a_man() -> void:
	var m := _match()
	var man := _man(m, Vector3(0, 0, 0))
	var giant := _man(m, Vector3(6, 0, 0), {"bodyScale": 3.0})
	await _steps(60)
	var lost := []
	for f in [man, giant]:
		var p: VoxelPart = f.torso
		var tf := p.global_transform
		var fwd := tf.basis.orthonormalized() * Vector3(0, 0, 1)
		var n0 := p.alive_count
		f.apply_hit(p, {"impulse": 40.0, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "point": tf * Vector3(0.0, 0.0, p.half_ext.z), "dir": -fwd, "axis": tf.basis.orthonormalized() * Vector3(1, 0, 0), "edge": -fwd, "heavy": 0.5, "wsz": 1.0})
		# In metres of flesh: each voxel of the giant is bigger.
		var vs: float = p.vf * p.part_scale
		lost.append((n0 - p.alive_count) * vs * vs * vs)
		print("   %s: %d voxels of %.3f m gone (of %d)" % [f.display_name, n0 - p.alive_count, vs, n0])
	t.check(lost[0] > 0.0 and lost[1] > 0.0, "both are cut (%.5f and %.5f cubic metres)" % [lost[0], lost[1]])
	t.check(lost[1] < lost[0] * 3.0, "the giant loses no great slab to a man's sword (%.1fx the man's wound)" % (lost[1] / maxf(1e-9, lost[0])))
	m.queue_free()

## A blow does not set a man lying on the sand turning head over heels (user video): while a
## foe's weapon presses on him, the turn it puts into his trunk is held to Fighter.STRUCK_W.
func test_a_blow_does_not_flip_a_man_lying_down() -> void:
	var m := _match()
	var f := _man(m, Vector3(0, 0, 0))
	await _steps(30)
	f.fall(2.0, true)
	await _steps(90)
	var worst := 0.0
	for k in 20:
		f.struck_frame = Engine.get_physics_frames()
		f.torso.angular_velocity = Vector3(18.0, 0.0, 0.0)
		await _steps(1)
		worst = maxf(worst, f.torso.angular_velocity.length())
	t.check(worst < 8.0, "a struck man's trunk turns slower than a somersault (%.1f rad/s, set at 18)" % worst)
	m.queue_free()

## A bot over (or beside) a man down on the sand, alive and held there, for `secs` seconds (user: where the players lay wounded on the sand and not dead, the bots
## did not know how to hit the man lying there). `smashed`: the bot has both shins smashed, he fights from the sand too. What it landed on him and how his body lay.
func _bot_on_a_man_down(weapon: String, secs: int, smashed := false) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.state = "dead"
	var e: Dictionary = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": weapon, "off": ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0, "diff": 0.7, "personality": "standard"})
	var ve: Dictionary = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(0, 0, 2.5), "yaw": PI})
	ve.erase("bot")
	ve.drive = func(_e): return {}
	var f: Fighter = e.f
	var v: Fighter = ve.f
	if smashed:
		for n in ["shinL", "shinR"]:
			f.by_name[n].fractured = true
			f.by_name[n].hp = 5.0
	var r := {"hits": 0, "lost": 0.0, "angle": 0.0}
	m.combat.hit.connect(func(h):
		if h.get("attacker") == f and h.get("char") == v:
			r.hits += 1)
	var hp0 := 0.0
	for i in secs * 120:
		if v.state == "stand" and v.alive:
			v.fall(30.0, true)
		elif v.state == "down" and v.alive:
			v.down_timer = maxf(v.down_timer, 5.0)
		await get_tree().physics_frame
		if i == 60:
			hp0 = v.total_hp()
		if not v.alive:
			break
	var head: Vector3 = f.torso.global_transform.basis * Vector3.UP
	var to_him: Vector3 = v.torso.global_position - f.torso.global_position
	r.angle = Vector2(head.x, head.z).angle_to(Vector2(to_him.x, to_him.z))
	r.angle = absf(r.angle)
	r.lost = hp0 - v.total_hp()
	r.state = f.state
	m.queue_free()
	await get_tree().process_frame
	return r

## A spear's point is passed over a man lying on the sand when the spearman keeps off at the shaft's length: held at its own length and level, three hits in fifteen seconds
## and a few points of harm. Nearer, the point comes down on him from above.
func test_a_spearman_lands_blows_on_a_man_lying_on_the_sand() -> void:
	for wn in ["spear", "trident"]:
		var r: Dictionary = await _bot_on_a_man_down(wn, 15)
		print("   %s over a man down: %d hits, %.0f hp lost" % [wn, r.hits, r.lost])
		t.check(r.hits >= 5 and r.lost >= 100.0, "%s: his point comes down on the man on the sand (%d hits, %.0f hp)" % [wn, r.hits, r.lost])

## A man with his legs gone fights on from the sand, and turns on it with his head to his man (his arms reach from his shoulders): lying with his feet to him, he crawled at
## the man feet first, shoved him along with his own legs and swung at the air a metre short of him.
func test_a_man_lying_on_the_sand_turns_his_head_to_the_man_he_fights() -> void:
	var r: Dictionary = await _bot_on_a_man_down("gladius", 20, true)
	print("   a crawler's head %.0f degrees off his man; %d hits, %.0f hp lost; he is %s" % [rad_to_deg(r.angle), r.hits, r.lost, r.state])
	t.eq(r.state, "down", "he is down on the sand")
	t.check(r.angle < 1.2, "his head is turned to the man (%.0f degrees off)" % rad_to_deg(r.angle))
	t.check(r.hits >= 4, "and he lands blows from where he lies (%d hits)" % r.hits)
