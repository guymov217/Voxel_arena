extends Node
## The trainer: six abilities bought a session at a time, capped by the bout and their own
## limit, dearer every time; what they teach shows in the man (his breath, his footing, his
## blow) and nothing is learned in the arena itself.

var t

func test_the_trainer_sells_sessions_within_the_bouts_cap() -> void:
	Edition.forced = false
	t.eq(Training.cap("vis", 1), 0, "nothing before the first bout is won")
	t.eq(Training.cap("vis", 6), 9, "two per cent a bout, in whole sessions (bout 6: 9%)")
	t.eq(Training.cap("vis", 40), 30, "and never past the ability's own limit")
	t.eq(Training.cap("corium", 40), 45, "hide goes further")
	var st := {}
	var r := Training.buy(st, "vis", 1, 1000)
	t.check(r.has("error"), "bout 1: nothing to teach yet (%s)" % r.get("error", ""))
	r = Training.buy(st, "vis", 5, 30)
	t.check(r.has("error") and String(r.error).begins_with("Not enough"), "no denarii, no session")
	r = Training.buy(st, "vis", 5, 100)
	t.check(not r.has("error") and int(r.cost) == 40 and int(r.stats.vis) == 3, "the first session: 40 denarii, +3%%")
	st = r.stats
	t.eq(Training.price(st, "vis"), 70, "the next costs more")
	r = Training.buy(st, "vis", 5, 1000)
	st = r.stats
	r = Training.buy(st, "vis", 5, 1000)
	t.check(r.has("error"), "bout 5 allows 6%%: the third session waits (%s)" % r.get("error", ""))
	t.eq(Training.bout_for(9), 6, "and comes before bout 6")
	t.eq(Training.cap("vis", Training.bout_for(9)), 9, "(as the cap says)")
	t.eq(Training.sanitize({"vis": 7, "bogus": 3, "corium": 99, "sanguis": "x"}).get("vis"), 6, "a save is made safe: whole sessions")
	t.eq(Training.sanitize({"corium": 99}).corium, 45, "and within the limit")
	t.eq(Training.sanitize({"virtus": 4}).get("virtus"), 4, "Valour keeps its sessions of 2%")
	t.eq(Training.from_old({"vis": 4, "corium": 24, "enemy": "bear", "bag": {}}), {"vis": 6, "corium": 36}, "the old save's sessions are kept, at today's 3% (the training ground's own keys left out)")
	var m := Training.mods_of({"vis": 9, "sanguis": 21, "spiritus": 6, "firmitas": 9, "ictus": 3, "corium": 12})
	t.check(is_equal_approx(m.strength, 1.09) and is_equal_approx(m.bleed, 0.79) and is_equal_approx(m.wind, 1.06) and is_equal_approx(m.footing, 1.09) and is_equal_approx(m.blow, 1.03) and is_equal_approx(m.toughness, 1.12), "the abilities become the man's mods (%s)" % [m])
	Edition.forced = true
	t.eq(Training.cap("corium", 40), Training.DEMO_MAX, "the demo's trainer teaches two sessions")
	Edition.forced = null

## What he was taught shows in him: more breath, a steadier stance, a heavier blow.
func test_training_shows_in_the_man() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "mods": Training.mods_of({"spiritus": 21, "firmitas": 21, "ictus": 15, "vis": 9})})
	var me: Fighter = m.me.f
	t.check(is_equal_approx(float(me.mods.strength), 1.09) and is_equal_approx(float(me.mods.blow), 1.15), "the mods are on him")
	t.check(me.breath_cap() > 119.0, "a fifth more breath (%.0f)" % me.breath_cap())
	var plain = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {}, "team": 1, "pos": Vector3(3, 0, 0), "yaw": PI})
	plain.erase("bot")
	plain.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	var hit := func(f: Fighter) -> float:
		f.stagger = 0.0
		var p: Vector3 = f.torso.global_transform * Vector3(0, 0.1, -f.torso.half_ext.z)
		f.apply_hit(f.torso, {"impulse": 30.0, "type": "blunt", "hardness": 0.8, "sharpness": 0.0, "point": p, "dir": Vector3.FORWARD})
		return f.stagger
	var s_plain: float = hit.call(plain.f)
	var s_trained: float = hit.call(me)
	t.check(s_trained < s_plain * 0.9 and s_plain > 0.0, "the same blow rocks the trained man less (%.2f against %.2f)" % [s_trained, s_plain])
	m.queue_free()

## Strength (Vis) is in every throw too (user): a weapon, darts, a discus leave a stronger arm
## faster, still on the line to the crosshair (a bot's lob too), and land harder: half of the
## strength goes into the blow, as into a weapon's.
func test_a_stronger_arm_throws_faster_and_harder() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var me: Fighter = m.me.f
	var foe = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 3), "yaw": PI})
	foe.erase("bot")
	foe.drive = func(_e): return {}
	var v: Fighter = foe.f
	for i in 20:
		await get_tree().physics_frame
	var blows := []
	m.combat.hit.connect(func(h): if h.get("char") == v: blows.append(float(h.J)))
	var runs := []
	for s in [1.0, 1.3]:
		me.mods.strength = s
		var aim := Vector3(0.0, 1.2, 14.0)
		var n0: int = m.items.list.size()
		m.throwables.throw_type(me, "pot_dart", aim, null, true, 1.0)
		m.throwables.throw_type(me, "pot_discus", aim, null, true, 1.0)
		m.throwables.throw_type(me, "pot_discus", aim, null, false)
		var thrown: Array = m.items.list.slice(n0)
		var dart: Dictionary = thrown[1]   # the middle one of the three goes at the mark
		var p0: Vector3 = dart.p
		var dv: Vector3 = dart.vel
		var tt := Vector2(aim.x - p0.x, aim.z - p0.z).length() / Vector2(dv.x, dv.z).length()
		var lob: Vector3 = thrown[4].vel
		runs.append({"weapon": me.launch_velocity(me.torso.global_position + Vector3(0, 0.3, 0), aim, 1.0, 1.0).length(),
			"dart": dv.length(), "discus": (thrown[3].vel as Vector3).length(), "lob": Vector2(lob.x, lob.z).length(),
			"miss": absf(p0.y + dv.y * tt - 0.5 * 9.81 * tt * tt - aim.y)})
		for it in thrown:
			m.items.remove(it)
		blows.clear()
		m.throwables.explode("pot_dart", v.torso.global_position, me, Vector3(0, 0, 1), v, v.torso)
		m.throwables.explode("pot_discus", v.torso.global_position + Vector3(0, -0.2, 0), me, Vector3(0, 0, 1), v, v.torso)
		runs[-1]["blows"] = blows.duplicate()
	var a: Dictionary = runs[0]
	var b: Dictionary = runs[1]
	for k in ["weapon", "dart", "discus", "lob"]:
		t.check(absf(float(b[k]) / float(a[k]) - 1.3) < 0.01, "a third more strength, a third faster: the %s (%.1f against %.1f m/s)" % [k, b[k], a[k]])
	t.check(float(a.miss) < 0.02 and float(b.miss) < 0.02, "and still on the crosshair (%.3f and %.3f m off)" % [a.miss, b.miss])
	t.check(a.blows.size() == 2 and b.blows.size() == 2, "the dart and the discus land (%d, %d)" % [a.blows.size(), b.blows.size()])
	if a.blows.size() == 2 and b.blows.size() == 2:
		for i in 2:
			t.check(absf(float(b.blows[i]) / float(a.blows[i]) - 1.15) < 0.01, "half of it goes into the blow: %s (%.1f against %.1f)" % [["the dart", "the discus"][i], b.blows[i], a.blows[i]])
	m.queue_free()

## Training's next foe is brought in over a few frames as one dies (Match.spawn_fighter_staged: built
## whole in the frame of the death, the game stopped each time): he comes in whole, drawn and in
## the fight. Taken out while he is still being dressed (the arena gone), nothing more is done to
## him: the dressing went on with him gone and the game crashed.
func test_the_next_foe_is_brought_in_over_a_few_frames() -> void:
	for gone in [false, true]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "gladiator", "count": 1, "difficulty": 0.5}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
		m.me.f.teleport(Vector3(0, 0, -14))
		m.me.drive = func(_e): return {}
		for i in 30:
			await get_tree().physics_frame
		var foe = null
		for e in m.entities:
			if e.team == Match.ENEMY_TEAM and e.f.alive:
				foe = e
		t.check(foe != null, "a foe to fight")
		if foe == null:
			m.queue_free()
			return
		var n0 := m.entities.size()
		foe.f.die("test")
		if gone:
			var dressing = null
			for i in 300:
				await get_tree().process_frame
				for c in m.get_children():
					if c is Fighter and (c as Fighter).parts.size() == 10 and not c.has_meta("physique"):
						dressing = c
				if dressing != null:
					break
			t.check(dressing != null, "caught him being dressed")
			m.queue_free()
			for i in 60:
				await get_tree().process_frame
			t.check(not is_instance_valid(dressing), "the arena gone under him: he went with it, and the game goes on")
			continue
		var came := -1
		for i in 300:
			await get_tree().process_frame
			if m.entities.size() > n0:
				came = i
				break
		t.check(came > 2, "the next one comes in a few frames after the death (%d)" % came)
		if came > 0:
			var nf: Fighter = m.entities.back().f
			t.check(nf.alive and nf.parts.size() == 10 and nf.visible and nf.process_mode == Node.PROCESS_MODE_INHERIT, "whole, drawn and in the fight")
		m.queue_free()
		await get_tree().process_frame

## A beast brought in while the fight goes on is built a part a frame too (Match.
## spawn_beast_staged: a lion in one frame was a stop of half a second, user: the frame rate
## drops in a fight): out of the world until it is whole, then in, the same beast as one built
## in a frame; and if the arena goes while it is being made, it goes with it.
func test_a_beast_is_brought_in_over_a_few_frames() -> void:
	for gone in [false, true]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
		m.me.drive = func(_e): return {}
		var n0 := m.entities.size()
		var spec := {"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 8), "yaw": PI}
		var box := [null, false]
		var bring := func() -> void:
			box[0] = await m.spawn_beast_staged(spec)
			box[1] = true
		bring.call()
		t.eq(m.entities.size(), n0, "not in the fight in the frame that called for it")
		var making = null
		for c in m.get_children():
			if c is Beast:
				making = c
		t.check(making != null and not (making as Beast).visible and (making as Node).process_mode == Node.PROCESS_MODE_DISABLED, "being made out of the world")
		if gone:
			for i in 4:
				await get_tree().process_frame
			m.queue_free()
			for i in 60:
				await get_tree().process_frame
			t.check(not is_instance_valid(making), "the arena gone under it: it went with it, and the game goes on")
			continue
		var frames := 0
		while not box[1] and frames < 900:
			await get_tree().process_frame
			frames += 1
		t.check(frames > 8 and frames < 900, "made over the frames that follow (%d of them)" % frames)
		var e = box[0]
		if not t.check(e != null and m.entities.has(e), "then in the fight"):
			m.queue_free()
			continue
		var b: Beast = e.f
		t.check(b == making and b.visible and b.process_mode != Node.PROCESS_MODE_DISABLED and b.alive, "whole, drawn and moving")
		var plain = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(6, 0.1, 8), "yaw": PI})
		var same: bool = b.parts.size() == plain.f.parts.size()
		for p: VoxelPart in b.parts:
			var q: VoxelPart = plain.f.by_name.get(p.part_name)
			same = same and q != null and p.fx == q.fx and p.colors == q.colors and p.ao == q.ao and p.fine.has("body") == q.fine.has("body") and (p.joint != null) == (q.joint != null)
			if same and p.fine.has("body"):
				same = (p.fine.own as PackedColorArray) == (q.fine.own as PackedColorArray)
		t.check(same, "the same beast as one built in a frame, part for part")
		t.eq(b.legs.size(), plain.f.legs.size(), "on as many legs")
		for i in 240:
			await get_tree().physics_frame
		t.check(b.alive and b.torso.global_position.y > 0.2 and b.torso.global_position.y < 3.0, "standing on the sand two seconds on (its body at %.2f)" % b.torso.global_position.y)
		m.queue_free()

## A foe brought in while the fight goes on in a helmet over a hairstyle not laid out before (a
## helmet is laid over each hairstyle, FineArmor): its shell is worked out a little a frame (in
## one, a tenth to a quarter of a second's hitch), and comes out as it would laid out at once.
func test_a_new_foes_helmet_is_laid_out_over_a_few_frames() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -14))
	m.me.drive = func(_e): return {}
	await get_tree().physics_frame
	FineArmor._bands.clear()
	FineArmor._shells.clear()
	FineArmor.pace_us = 0   # (a frame's wait at every turn: it is laid out over many)
	var f0 := Engine.get_process_frames()
	var e = await m.spawn_fighter_staged({"kind": "bot", "name": "Late", "loadout": {"main": "gladius", "off": "", "armor": ["murmilloHelm", "hair_curly"]}, "team": 1, "pos": Vector3(0, 0.1, 4.0), "yaw": PI})
	var frames := Engine.get_process_frames() - f0
	FineArmor.pace_us = 4000
	t.check(e != null, "he comes in")
	if e == null:
		m.queue_free()
		return
	t.check(frames > 100, "his helmet worked out over many frames (%d)" % frames)
	var helm := {}
	for ad in e.f.head.get_meta("armor", []):
		if String(ad.id) == "murmilloHelm":
			helm = ad
	t.check(helm.get("shell") is Dictionary and is_instance_valid(helm.shell.mi), "in his helmet, drawn")
	var paced := _kept_shell("|murmilloHelm|")
	# The same laid out at once, nothing kept.
	FineArmor._bands.clear()
	FineArmor._shells.clear()
	FineArmor.clear(helm)
	FineArmor.build(e.f, e.f.head, helm)
	var once := _kept_shell("|murmilloHelm|")
	t.check(not paced.is_empty() and not once.is_empty(), "laid out both ways")
	t.eq(int(paced.get("cnt", -1)), int(once.get("cnt", -2)), "as many of its voxels")
	t.check(paced.get("buf") == once.get("buf"), "each where it was and of the colour it was")
	t.check(helm.get("shell") is Dictionary and is_instance_valid(helm.shell.mi), "and drawn again at once")
	m.queue_free()
	await get_tree().process_frame

## Drawn anew (a look picked in Options) while his helmet is being worked out: the helmet laid on
## him then stays on him (the one given up, as it ended, took it off him again).
func test_a_man_drawn_anew_while_his_helmet_is_worked_out_keeps_it() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -14))
	m.me.drive = func(_e): return {}
	await get_tree().physics_frame
	var e = m.spawn_fighter({"kind": "bot", "name": "Anew", "loadout": {"main": "gladius", "off": "", "armor": ["murmilloHelm", "hair_curly"]}, "team": 1, "pos": Vector3(0, 0.1, 4.0), "yaw": PI})
	var f: Fighter = e.f
	var helm := {}
	for ad in f.head.get_meta("armor", []):
		if String(ad.id) == "murmilloHelm":
			helm = ad
	FineArmor._bands.clear()
	FineArmor._shells.clear()
	FineArmor.clear(helm)
	FineArmor.pace_us = 0   # (a frame's wait at every turn: it is laid out over many)
	var done := [false]
	var lay := func():
		await FineArmor.build(f, f.head, helm, true)
		done[0] = true
	lay.call()
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(not done[0] and not helm.has("shell"), "his helmet being worked out")
	Physique.dress(f)
	var given = helm.shell.mi if helm.get("shell") is Dictionary else null
	t.check(given != null and is_instance_valid(given), "drawn anew, in his helmet at once")
	for i in 240:
		if done[0]:
			break
		await get_tree().process_frame
	FineArmor.pace_us = 4000
	t.check(done[0], "the one being worked out given up")
	t.check(helm.get("shell") is Dictionary and is_instance_valid(helm.shell.mi) and is_same(helm.shell.mi, given), "and the helmet he was given stays on him")
	t.check(not (helm.node as Node3D).visible, "its plates' own tiles not shown under it")
	m.queue_free()
	await get_tree().process_frame

static func _kept_shell(piece: String) -> Dictionary:
	for k in FineArmor._shells:
		if String(k).contains(piece):
			return FineArmor._shells[k]
	return {}
