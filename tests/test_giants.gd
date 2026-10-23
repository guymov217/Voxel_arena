extends Node
## The giants of myth land their weapons on a man a third their size: each is let at a man for
## a while and must hit him with what it carries, not swing over his head.

var t

func _bout(kind: String, seconds: float, down: bool) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
	spec.pos = Vector3(0, 0.1, 7.0)
	spec.yaw = PI
	spec.diff = 0.6
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	var hits := {"weapon": 0, "any": 0, "J": 0.0, "first": -1.0, "killed": false}
	m.combat.hit.connect(func(h):
		if h.attacker == g and h.char == man:
			hits.any += 1
			if h.get("weapon") != null:
				hits.weapon += 1
				hits.J = maxf(hits.J, float(h.J))
				if hits.first < 0.0:
					hits.first = m.time
				if h.get("killed", false):
					hits.killed = true)
	for i in int(seconds * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		for p in man.parts:
			p.hp = maxf(p.hp, 30.0)
		if down and man.state == "stand":
			man.fall(2.0, true)
		await get_tree().physics_frame
		if not man.alive:
			break
	hits["S"] = g.S
	hits["weapon_name"] = String(g.weapons.R.design.name) if g.weapons.get("R") else "-"
	m.queue_free()
	return hits

func test_every_giant_lands_its_weapon_on_a_man() -> void:
	seed(7)
	for kind in ["cyclops", "giant", "minotaur", "troll", "titan"]:
		# (Sixteen seconds: the titan is slow, and now and then its first swing came after ten.)
		var h := await _bout(kind, 16.0, false)
		var msg := "%s (S %.1f, %s) lands its weapon on a standing man (first hit at %.1fs, J %.0f)" % [kind, h.S, h.weapon_name, h.first, h.J]
		printerr("   : " + msg)
		t.check(h.weapon >= 1 and h.first < 14.0, msg)
		# A giant's blow, pulled as Combat pulls it (Fighter.GIANT_BLOW): the minotaur is a
		# bull-man, not a titan.
		var heavy := (40.0 if h.S >= 2.3 else 25.0) * Fighter.GIANT_BLOW / 0.85
		t.check(h.J >= heavy or h.killed, "%s: and the blow is a giant's (J %.0f, killed %s)" % [kind, h.J, str(h.killed)])

func test_every_giant_reaches_a_man_on_the_sand() -> void:
	seed(8)
	for kind in ["cyclops", "giant", "titan"]:
		var h := await _bout(kind, 14.0, true)
		var msg := "%s brings its weapon down on a man on the sand (first hit at %.1fs, J %.0f)" % [kind, h.first, h.J]
		printerr("   : " + msg)
		t.check(h.weapon >= 1 and h.first < 12.0, msg)

## Every foe stands still (they come in through the gate over time: each step).
func _calm(m: Match) -> void:
	for e in m.enemies():
		if e.has("bot"):
			e.erase("bot")
			e.drive = func(_e): return {}

## An arrow in a giant's eye does not end the bout: with the eye put out he goes berserk (a
## blind rage) and fights on, not knocked out by it, two arrows or one.
func test_a_giant_with_an_eye_put_out_rages_and_fights_on() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5, "loadout": {"main": "bow", "off": ""}})
	m.me.drive = func(_e): return {}
	_calm(m)
	var spec := m.enemy_spec({"e": "giant", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 6.0)
	var ge = m.spawn_fighter(spec)
	var g: Fighter = ge.f
	var raged := [false]
	g.raged.connect(func(_f): raged[0] = true)
	for i in 60:
		_calm(m)
		await get_tree().physics_frame
	t.check(not g.enraged, "the giant is not in a rage before his eye is hit")
	for shot in 2:
		var eye: Array = g._eye_cells().filter(func(i): return g.head.alive[i] != 0)
		var p: Vector3 = g.head.world_of(eye[eye.size() / 2])
		m.throwables._dart("pot_arrow", p, m.me.f, (p - m.me.f.head.global_position).normalized(), g, g.head, 1.0)
		for i in 30:
			_calm(m)
			await get_tree().physics_frame
	t.check(g.enraged and raged[0], "an arrow in the eye sends him into a rage")
	var beaten := false
	for i in 720:
		_calm(m)
		await get_tree().physics_frame
		beaten = beaten or g.is_beaten()
	t.check(g.alive and not beaten, "the giant fights on with his eye out (alive %s, conc %.2f)" % [g.alive, g.concussion])
	t.check(not m.over, "and the bout goes on")
	m.queue_free()

## A man who cannot stand any more (crawling at most) is out of the bout after five seconds:
## with no one on his side able to fight on, the bout is lost.
func test_a_bout_ends_when_no_one_can_stand_and_fight() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5})
	_calm(m)
	m.me.drive = func(_e): return {"mz": 1.0}
	var res := {}
	m.finished.connect(func(r): res.merge(r))
	var f: Fighter = m.me.f
	for i in 30:
		_calm(m)
		await get_tree().physics_frame
	f.cord_legs = 0.0
	f.fall(30.0, true)
	for i in 120 * 4:
		_calm(m)
		await get_tree().physics_frame
	t.check(not m.over, "four seconds crawling: the bout is not yet over")
	t.check(not f.can_stand(), "he cannot stand")
	for i in 150:
		_calm(m)
		await get_tree().physics_frame
	t.check(m.over and res.get("won", true) == false, "after five the bout is lost (over %s, %s)" % [m.over, res.get("won")])
	m.queue_free()

## Half his head cut away kills a man (he does not lie there alive for ever).
## A split head rings a man and fells him; only most of his head gone ends him.
func test_most_of_a_head_is_death() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var f: Fighter = m.me.f
	var cut := func(share: float) -> void:
		var some := []
		for i in f.head.fx.size():
			if f.head.alive[i] and f.head.fx[i] < f.head.dims.x * int(Data.body_res) * share:
				some.append(i)
		f.head.remove_voxels(some)
	cut.call(0.3)
	for i in 10:
		await get_tree().physics_frame
	t.check(f.alive, "a third of his head gone: still alive (integrity %.2f)" % f.head.integrity)
	cut.call(0.75)
	for i in 10:
		await get_tree().physics_frame
	t.check(not f.alive, "most of his head gone: dead (integrity %.2f)" % f.head.integrity)
	m.queue_free()

## Whatever keeps a man on the sand, twelve seconds there without getting up and he is out:
## the bout does not hang on a man who will not rise.
func test_a_man_down_for_good_is_out_of_the_bout() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5})
	_calm(m)
	m.me.drive = func(_e): return {"limp": true}
	var res := {}
	m.finished.connect(func(r): res.merge(r))
	var f: Fighter = m.me.f
	for i in 30:
		_calm(m)
		await get_tree().physics_frame
	f.fall(60.0, true)
	for i in 120 * 10:
		_calm(m)
		await get_tree().physics_frame
	t.check(not m.over and f.can_stand(), "ten seconds down (he could stand): the bout goes on")
	for i in 120 * 3:
		_calm(m)
		await get_tree().physics_frame
	t.check(m.over and res.get("won", true) == false, "after twelve he is out and the bout is lost (state %s down_t %.1f unfit %.1f over %s)" % [f.state, float(m.me.get("down_t", -1.0)), float(m.me.get("unfit_t", -1.0)), m.over])
	m.queue_free()

## A foe the bout has counted beaten stays beaten: he does not get up and fight on after the
## round was called over him (and its kill cam shown).
func test_a_beaten_foe_does_not_fight_on() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5})
	_calm(m)
	for i in 30:
		_calm(m)
		await get_tree().physics_frame
	var e: Dictionary = m.enemies()[0]
	e.erase("bot")
	e.drive = func(_e): return {"limp": true}
	e.f.fall(60.0, true)
	for i in 120 * 13:
		await get_tree().physics_frame
	t.check(e.get("beaten", false), "down for good: counted beaten")
	e.f.down_timer = 0.0
	e.f.concussion = 0.0
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(not e.has("bot") and e.drive.call(e).get("limp", false), "and he stays down: no bot fights on in him")
	m.queue_free()

## A giant is not felled by a man's hard blows to the legs and the body: his bones are thicker
## and he stands steadier, a dozen warhammer blows in a row leave him on his feet.
func test_a_giant_stands_up_to_hard_blows() -> void:
	for kind in ["cyclops", "giant"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
		m.me.f.teleport(Vector3(0, 0, -15))
		var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
		spec.pos = Vector3(0, 0.1, 0)
		var e = m.spawn_fighter(spec)
		e.erase("bot")
		e.drive = func(_e): return {}
		var g: Fighter = e.f
		for k in 90:
			await get_tree().physics_frame
		var falls := 0
		for n in ["torso", "thighL", "torso", "shinR", "thighR", "torso", "shinL", "thighL"]:
			var p: VoxelPart = g.torso if n == "torso" else g.by_name[n]
			g.apply_hit(p, {"impulse": 34.0, "type": "blunt", "hardness": 0.9, "sharpness": 0.0, "point": p.global_position - Vector3(0, 0, p.half_ext.z), "dir": Vector3(0, 0, 1), "axis": Vector3.RIGHT, "edge": Vector3(0, 0, 1), "heavy": 0.4, "wsz": 1.0})
			for k in 45:
				await get_tree().physics_frame
				if g.state != "stand":
					falls += 1
					break
		t.eq(falls, 0, "%s stays on his feet under 8 warhammer blows" % kind)
		m.queue_free()
		await get_tree().physics_frame
