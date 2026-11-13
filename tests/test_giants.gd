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
		# (Eighteen seconds: the man on the sand keeps getting up and is put down again, and a
		# giant's first blow at him comes at four to eleven seconds over ten seeds.)
		var h := await _bout(kind, 18.0, true)
		var msg := "%s brings its weapon down on a man on the sand (first hit at %.1fs, J %.0f)" % [kind, h.first, h.J]
		printerr("   : " + msg)
		t.check(h.weapon >= 1 and h.first < 16.0, msg)

## A giant with a long-hafted weapon fought as a spear (the giant's nail plank) brings it down on
## a man on the sand, whatever way the fight goes (three seeds). The rule that sends a spearman
## back out past his point kept the giant from striking from where he stood over the man: no blow
## at all in fourteen seconds in three seeds of ten.
func test_a_giant_with_a_long_haft_strikes_a_man_on_the_sand() -> void:
	for sd in [1, 2, 9]:
		seed(sd)
		var h := await _bout("giant", 16.0, true)
		t.check(h.weapon >= 1, "seed %d: the giant (%s) strikes the man on the sand (first hit at %.1fs)" % [sd, h.weapon_name, h.first])

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

## A man who cannot stand any more is out of the bout five seconds after he stops crawling at
## the foe (crawling is fighting on; lying still is not): with no one on his side able to
## fight on, the bout is lost.
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
	m.me.drive = func(_e): return {}
	for i in int(120 * 5.5):
		_calm(m)
		await get_tree().physics_frame
	t.check(m.over and res.get("won", true) == false, "lying still, after five the bout is lost (over %s, %s)" % [m.over, res.get("won")])
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

## A man with nothing left to hurt anyone with is out of the bout, crawling or not: no arm that
## swings or holds, no legs to get up and kick on (user: one of them could not fight any more, nor
## could the other, and the bout went on). A man who still has an arm fights on from the sand,
## and a beast is out the same way once it has nothing to bite with and no legs to run on.
func test_a_man_with_nothing_left_to_fight_with_is_out_of_the_bout() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5})
	m.me.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	var e: Dictionary = m.enemies()[0]
	var f: Fighter = e.f
	var res := {"removed": [], "severed": []}
	f.detach_limb(f.by_name.thighL, res)
	f.detach_limb(f.by_name.thighR, res)
	f.detach_limb(f.arm.L.upper, res)
	for i in 60:
		f.blood = 100.0
		await get_tree().physics_frame
	t.check(not m._spent(f), "legs and one arm gone: the other arm still fights")
	f.detach_limb(f.arm.R.upper, res)
	var out_at := -1.0
	for i in 120 * 9:
		f.blood = 100.0
		await get_tree().physics_frame
		if out_at < 0.0 and e.get("beaten", false):
			out_at = i / 120.0
	t.check(m._spent(f) or e.get("beaten", false), "legs and both arms gone: nothing left to fight with")
	t.check(out_at > 0.0 and out_at < 8.0, "and out of the bout within the count (after %.1f s; state %s, crawling %s)" % [out_at, f.state, f.crawling])
	var b = m.spawn_beast({"beast": "hyena", "team": Match.ENEMY_TEAM, "pos": Vector3(5, 0.1, 5), "yaw": 0.0})
	for i in 30:
		await get_tree().physics_frame
	b.f.detach_limb(b.f.by_name.beastHead, {"removed": [], "severed": []})
	for i in 10:
		await get_tree().physics_frame
	t.check(not m._spent(b.f), "a hyena with its head off still has its legs to run a man down")
	for n in ["legFL", "legFR", "legBL", "legBR"]:
		b.f.detach_limb(b.f.by_name[n], {"removed": [], "severed": []})
	for i in 10:
		b.f.blood = 100.0
		await get_tree().physics_frame
	# (Its four legs off at once, a hyena does not live: dead or spent, it is out.)
	t.check(m._spent(b.f) or not b.f.alive, "with its legs off too it can do nothing (leg power %.2f, alive %s, disarmed %s)" % [b.f.leg_power(), b.f.alive, b.f.disarmed()])
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

## Nor does the man the bout was lost on: knocked out cold, he does not come round after the
## kill cam and fight on in a bout already called against him (user, a cyclops' blow).
func test_a_man_beaten_cold_stays_down_after_the_bout_is_lost() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 5})
	_calm(m)
	for i in 30:
		_calm(m)
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	# (Out cold: his own hands do nothing until the bout is called.)
	m.me.drive = func(_e): return {"limp": true, "mine": true}
	f.fall(60.0, true)
	for i in 120 * 13:
		_calm(m)
		await get_tree().physics_frame
	t.check(m.over, "out on the sand: the bout is lost")
	t.check(m.me.get("beaten", false) and m.me.drive.call(m.me).get("limp", false) and not m.me.drive.call(m.me).has("mine"), "and the bout holds him down from then on, whatever his hands do (%s)" % [m.me.drive.call(m.me)])
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

## A giant in his blind rage does not go straight for the man as if he saw him: he lurches
## about, facing every way, and swings at the air; when the man is close he feels for him.
func test_a_raging_giant_lurches_blind_and_swings_at_the_air() -> void:
	seed(9)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 9})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	m.me.drive = func(_e): return {}
	var spec: Dictionary = m.enemy_spec({"e": "cyclops"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 9.0)
	spec.yaw = PI
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	for i in 30:
		await get_tree().physics_frame
	g.enrage()
	var facing := 0
	var n := 0
	var fast := 0.0
	var swings := 0
	var was_fast := false
	for i in int(10.0 * 120):
		man.blood = 100.0
		await get_tree().physics_frame
		n += 1
		var fwd: Vector3 = PD.quat_of(g.torso) * Vector3(0, 0, 1)
		var to: Vector3 = man.torso.global_position - g.torso.global_position
		fwd.y = 0.0; to.y = 0.0
		if fwd.angle_to(to) < deg_to_rad(30.0):
			facing += 1
		var w: Weapon = g.weapons.R
		if w:
			var sp := (w.linear_velocity - g.torso.linear_velocity).length()
			fast = maxf(fast, sp)
			# A stroke: the hammer getting up to speed from rest (enraged he chains blow on
			# blow in one long attack, so the bot's attack state starts once and tells nothing).
			var fast_now := sp > 8.0
			if fast_now and not was_fast:
				swings += 1
			was_fast = fast_now if fast_now else (was_fast and sp > 3.0)
	var share := float(facing) / maxf(1.0, n)
	t.check(share < 0.75, "blind, he is not turned on the man most of the time (%.0f%% of it)" % (share * 100.0))
	t.check(swings >= 2 and fast > 5.0, "and swings all the same (%d strokes, the hammer at %.1f m/s)" % [swings, fast])
	t.check(g.alive and g.enraged, "still raging")
	m.queue_free()

## A giant with a leg blown off is not out of the fight: he crawls at the man and swings from
## the sand, and the bout does not run out on him while he does (a thunder pot took a giant's
## leg and he lay there until the count put him out: user).
func test_a_giant_with_a_leg_blown_off_crawls_at_the_man_and_fights_on() -> void:
	seed(11)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 11})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	m.me.drive = func(_e): return {}
	var spec: Dictionary = m.enemy_spec({"e": "giant"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 12.0)   # (far enough that he has to crawl a way: the blast shoved him a few metres closer)
	spec.yaw = PI
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	for i in 30:
		await get_tree().physics_frame
	var shin: VoxelPart = g.by_name["shinR"]
	m.throwables.explode("pot_thunder", shin.global_position + Vector3(0.3, 0, 0), man, null, g, shin, 2.5)
	for i in 60:
		await get_tree().physics_frame
	if g.leg_func("R") > 0.0:
		g.by_name["shinR"].severed = true   # (the blast did not take it: the leg is taken for him)
	for i in 120:
		await get_tree().physics_frame
	t.check(not g.can_stand() and g.alive, "his leg gone, he cannot stand (leg %.2f, state %s)" % [g.leg_func("R"), g.state])
	var d0: float = Vector2(g.torso.global_position.x - man.torso.global_position.x, g.torso.global_position.z - man.torso.global_position.z).length()
	var crawled := 0
	var swings := 0
	var was_attack := false
	var fast := 0.0
	for i in int(14.0 * 120):
		man.blood = 100.0
		await get_tree().physics_frame
		if g.crawling:
			crawled += 1
		var attacking: bool = e.has("bot") and e.bot.state == "attack"
		if attacking and not was_attack:
			swings += 1
		was_attack = attacking
		var w: Weapon = g.weapons.R
		if w:
			fast = maxf(fast, (w.linear_velocity - g.torso.linear_velocity).length())
	var d1: float = Vector2(g.torso.global_position.x - man.torso.global_position.x, g.torso.global_position.z - man.torso.global_position.z).length()
	t.check(crawled > 120 and d1 < d0 - 1.0, "he crawls at the man (%d frames crawling, %.1f m closer)" % [crawled, d0 - d1])
	t.check(swings >= 1 or fast > 4.0, "and swings from the sand (%d swings, %.1f m/s)" % [swings, fast])
	t.check(not m.over and g.alive, "and fourteen seconds on the bout is still on (over %s)" % m.over)
	m.queue_free()

## A giant never goes down through the floor (user): legs sunk into the sand while the support
## spring held him (they pass through it standing) come up on top of it when he falls, and a part
## driven into the ground by his weight is set back on it.
func test_a_falling_giant_stays_on_the_sand() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -12))
	var spec: Dictionary = m.enemy_spec({"e": "giant"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 4.0)
	spec.yaw = PI
	var e = m.spawn_fighter(spec)
	e.erase("bot")
	e.drive = func(_e): return {}
	var g: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	# His legs pushed deep into the sand, then down he goes.
	for n in ["shinL", "shinR", "thighL"]:
		var p: VoxelPart = g.by_name[n]
		p.global_position += Vector3(0, -0.9 * g.S * 0.5, 0)
	g.fall(3.0, true)
	var lowest := INF
	for i in 240:
		await get_tree().physics_frame
		if i > 10:
			for p in g.parts:
				lowest = minf(lowest, p.global_position.y)
	t.check(lowest > -0.05, "every part of him stays on the sand as he falls (lowest middle %.2f m)" % lowest)
	t.check(g.torso.global_position.y > 0.0 and g.torso.global_position.y < 2.0 * g.S, "he lies on the floor, not under it (%.2f m)" % g.torso.global_position.y)
	m.queue_free()


## How far points on a part's collider faces lie from what is drawn of it in its giant's build
## (own frame: its fine voxels that lie over a voxel of it): [mean, most], m (most counted to
## 0.16 m).
func _off_drawing(p: VoxelPart, bn: String) -> Array:
	var d := FineBody.part_data(bn, String(p.part_name))
	var L := FineBody._layout(p, d, bn + "|" + String(p.part_name) + "|" + str(snappedf(p.vf * p.part_scale, 0.00001)), false)
	var B := 0.08
	var near := {}
	var par: PackedInt32Array = L.par
	for s in par.size():
		if par[s] < 0:
			continue
		var c: Vector3 = (L.xf[s] as Transform3D).origin
		var k := Vector3i((c / B).floor())
		if not near.has(k):
			near[k] = []
		(near[k] as Array).append(c)
	var h := Vector3.ONE * float(L.fsz) * 0.5
	var sum := 0.0
	var most := 0.0
	var n := 0
	for c in p.get_children():
		if not (c is CollisionShape3D) or (c as CollisionShape3D).disabled or not ((c as CollisionShape3D).shape is BoxShape3D):
			continue
		var sz: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
		for ax in 3:
			for sg in [-1.0, 1.0]:
				for u in 3:
					for v in 3:
						var q := Vector3.ZERO
						q[ax] = sg * 0.5
						q[(ax + 1) % 3] = (u + 0.5) / 3.0 - 0.5
						q[(ax + 2) % 3] = (v + 0.5) / 3.0 - 0.5
						var w: Vector3 = (c as CollisionShape3D).position + q * sz
						var best := 2.0 * B
						var k0 := Vector3i((w / B).floor())
						for dx in range(-2, 3):
							for dy in range(-2, 3):
								for dz in range(-2, 3):
									for cc in near.get(k0 + Vector3i(dx, dy, dz), []):
										best = minf(best, ((w - cc).abs() - h).max(Vector3.ZERO).length())
						sum += best
						most = maxf(most, best)
						n += 1
	return [sum / maxf(1.0, n), most]

func _shapes_of(p: VoxelPart) -> Array:
	var out := []
	for c in p.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			out.append([(c as CollisionShape3D).position.snapped(Vector3.ONE * 0.0001), ((c as CollisionShape3D).shape as BoxShape3D).size.snapped(Vector3.ONE * 0.0001)])
	return out

## The user: a giant knocked a man down with nothing on screen touching him, his shin's box a hand
## wider than the shin drawn in it, his forearm's swung through the air beside the arm on screen.
## What strikes and is struck of a giant is what is drawn of him: each limb's boxes kept to his
## build's sculpt (FineBody.fit_giant), whole and cut, the same in any look.
func test_a_giant_strikes_and_is_struck_where_he_is_drawn() -> void:
	for kind in ["cyclops", "minotaur", "troll", "titan"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
		m.me.f.teleport(Vector3(0, 0, -12))
		var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
		spec.pos = Vector3(0, 0.1, 4.0)
		spec.yaw = PI
		var g: Fighter = m.spawn_fighter(spec).f
		var bn := Physique.giant_of(g)
		for n in ["forearmR", "forearmL", "shinR", "shinL"]:
			var off := _off_drawing(g.by_name[n], bn)
			printerr("   : %s %s: box faces off the drawing, mean %.3f m, most %.3f m" % [kind, n, off[0], off[1]])
			t.check(off[0] < 0.045 and off[1] < 0.15, "%s %s: struck where it is drawn (box faces off the drawing: mean %.3f m, most %.3f m)" % [kind, n, off[0], off[1]])
		# The same in the old look (drawn as his voxels): the look is drawing only.
		var was := {}
		for p in g.parts:
			was[p.part_name] = _shapes_of(p)
		Physique.dress(g, "classic")
		var same := true
		for p in g.parts:
			same = same and _shapes_of(p) == was[p.part_name]
		Physique.dress(g)
		t.check(same, "%s: the same boxes in the old look" % kind)
		# Cut into: what is left is still struck where it is drawn.
		var fa: VoxelPart = g.by_name.forearmR
		var lps := fa.local_positions()
		var chop := []
		for i in fa.fx.size():
			if lps[i].x > 0.0 and absf(lps[i].y) < fa.half_ext.y * 0.4:
				chop.append(i)
		fa.remove_voxels(chop)
		fa.fit_collider()
		var cut := _off_drawing(fa, bn)
		t.check(fa.split and cut[0] < 0.05, "%s: a forearm cut into still struck where it is drawn (mean %.3f m, %d boxes)" % [kind, cut[0], fa.shape_count()])
		m.queue_free()
		await get_tree().physics_frame

## The giants sculpted anew (a smooth skin, limbs that run on at their joints, a fighter's feet and
## the Minotaur's hooves: user, what was done for the gladiators on every monster) strike and are
## struck by the boxes they always had: each part's fit is kept in his build (tools/gen_fine_body.py
## "fit": the giant as he was first sculpted, row by row) and his boxes are made of that, not of
## what is drawn of him now. His new skin is drawing only.
func test_a_giant_sculpted_anew_keeps_the_boxes_he_had() -> void:
	# (An upper arm's boxes as they were before: their sizes, from its hand end up.)
	var was := {
		"cyclops": [Vector3(0.3575, 0.1358, 0.3575), Vector3(0.286, 0.1358, 0.3575), Vector3(0.3825, 0.6792, 0.4075)],
		"troll": [Vector3(0.253, 0.1202, 0.2846), Vector3(0.253, 0.1202, 0.253), Vector3(0.253, 0.2403, 0.3162), Vector3(0.3384, 0.3605, 0.3605)],
	}
	for kind in ["cyclops", "giant", "minotaur", "troll", "titan"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
		m.me.f.teleport(Vector3(0, 0, -12))
		var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
		spec.pos = Vector3(0, 0.1, 4.0)
		spec.yaw = PI
		var g: Fighter = m.spawn_fighter(spec).f
		var bn := Physique.giant_of(g)
		var kept_all := true
		var parts_n := 0
		for p: VoxelPart in g.parts:
			if p == g.head:
				continue
			parts_n += 1
			var d := FineBody.part_data(bn, String(p.part_name))
			var kept := FineBody.slabs_kept(p, d.get("fit", PackedInt32Array()), p.vf * p.part_scale)
			kept_all = kept_all and not kept.is_empty() and kept == p.fit_slabs
		t.check(kept_all and parts_n == 9, "%s: each of his parts struck by the boxes kept in his build (%d parts)" % [kind, parts_n])
		if was.has(kind):
			var got: Array = (g.by_name.upperArmR as VoxelPart).fit_slabs
			var same: bool = got.size() == (was[kind] as Array).size()
			if same:
				for i in got.size():
					same = same and ((got[i] as AABB).size - (was[kind][i] as Vector3)).length() < 0.0006
			t.check(same, "%s: his upper arm's boxes the ones it had (%d boxes)" % [kind, got.size()])
		m.queue_free()
		await get_tree().physics_frame

## The arm a giant holds his weapon in with both hands is drawn where it is: the turn of the drawing
## about the shoulder that lays a man's elbow out of his chest (Fighter._swivel_drawing) drew a
## giant's a third of a metre off it, and his arm struck a man where nothing was drawn (user).
func test_a_giants_guard_arm_is_drawn_where_it_is() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -12))
	var spec: Dictionary = m.enemy_spec({"e": "cyclops"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 4.0)
	spec.yaw = PI
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	for i in 90:
		await get_tree().physics_frame
	g.two_handed = true
	for i in 30:
		g._seat_drawing(false, 1.0 / 60.0)
	var most := 0.0
	for p in [g.arm[g.two_side].upper, g.arm[g.two_side].fore]:
		var td: Transform3D = (p as VoxelPart).draw_turn * (p as VoxelPart).global_transform
		td.origin += (p as VoxelPart).draw_shift
		most = maxf(most, td.origin.distance_to((p as VoxelPart).global_position))
	t.check(absf(g.swivel_a) < 0.001 and most < 0.06, "his guard arm drawn where it is (turned %.2f, drawn %.3f m off)" % [g.swivel_a, most])
	m.queue_free()
