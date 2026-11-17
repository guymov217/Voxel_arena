extends Node
## Fists and breath: a punch that lands is felt (the man rocked back, reeling, slow for a moment;
## a giant's fist more); empty hands come up into a boxer's guard; a few hard strokes no longer
## leave a man without breath.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A fist landing on a man's head, driven by the combat as a contact would be: what it does to him.
func _punch(m: Match, att: Fighter, vic: Fighter, speed: float) -> Dictionary:
	var fist: VoxelPart = att.arm.R.fore
	var dir: Vector3 = (vic.head.global_position - fist.global_position).normalized()
	fist.linear_velocity = att.torso.linear_velocity + dir * speed
	# (The combat reads the bodies' speeds as they were at the start of the step.)
	m.combat.vel[fist.get_instance_id()] = [fist.linear_velocity, Vector3.ZERO]
	m.combat.vel[vic.head.get_instance_id()] = [vic.head.linear_velocity, Vector3.ZERO]
	att.jab_t["R"] = Fighter.JAB_TIME * (1.0 - 0.5 * (Fighter.JAB_DRAW + Fighter.JAB_BACK))   # (on its way out)
	var v0: Vector3 = vic.torso.linear_velocity
	var h: Dictionary = m.combat._blow({"att": fist, "vic": vic.head, "J": 0.0, "rank": 0, "type": "blunt", "mat": "", "box": {}, "p": vic.head.global_position - dir * 0.08})
	var out := {"hit": h, "stagger": vic.stagger, "daze": vic.daze_t}
	# (The push is the physics' to carry out, on its next step.)
	await get_tree().physics_frame
	out.push = (vic.torso.linear_velocity - v0).dot(Vector3(dir.x, 0, dir.z).normalized())
	return out

## User: every punch an enemy or the player takes must really be felt, in harm and in what it does
## to him (knockback, stun, stagger).
func test_a_punch_is_felt() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	me.teleport(Vector3(0, 0, 0))
	var man = m.spawn_fighter({"kind": "npc", "name": "Bag", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.02, 0.9), "yaw": PI})
	man.drive = func(_e): return {}
	await _steps(120)
	var r: Dictionary = await _punch(m, me, man.f, 7.0)
	t.check(not (r.hit as Dictionary).is_empty(), "the fist lands")
	t.check(float(r.hit.get("J", 0.0)) >= 20.0, "and lands hard (J %.1f)" % float(r.hit.get("J", 0.0)))
	t.check(float(r.push) > 0.3, "he is rocked back by it (%.2f m/s)" % float(r.push))
	t.check(float(r.stagger) > 0.25, "he reels (stagger %.2f)" % float(r.stagger))
	t.check(float(r.daze) > 0.15, "and for a moment his hands and feet are slow (%.2f s)" % float(r.daze))
	m.queue_free()
	await get_tree().physics_frame
	# A giant's fist on a man: harder, and it throws him further.
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me2: Fighter = m2.me.f
	me2.teleport(Vector3(0, 0, 0))
	var giant = m2.spawn_fighter({"kind": "npc", "name": "Big", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.05, 2.4), "yaw": PI, "mods": {"bodyScale": 2.4}})
	giant.drive = func(_e): return {}
	await _steps(120)
	var rg: Dictionary = await _punch(m2, giant.f, me2, 7.0)
	t.check(float(rg.hit.get("J", 0.0)) > float(r.hit.get("J", 0.0)), "a giant's fist lands harder than a man's (J %.1f against %.1f)" % [float(rg.hit.get("J", 0.0)), float(r.hit.get("J", 0.0))])
	t.check(float(rg.push) > float(r.push), "and rocks him further")
	m2.queue_free()
	await get_tree().physics_frame

## With no weapon the fists come up into a boxer's guard whenever they are not being thrown; a
## weapon stays where it was last aimed (user: no weapon, he boxes, hands up in a guard).
func test_empty_hands_come_up_into_a_guard() -> void:
	var pi := PlayerInput.new()
	add_child(pi)
	pi.set_unarmed(true, true)
	pi.main = {"x": 1.2, "y": -0.8}
	pi.off = {"x": -1.0, "y": -0.6}
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(absf(float(pi.main.y) - float(PlayerInput.GUARD_MAIN.y)) < 0.05 and absf(float(pi.off.y) - float(PlayerInput.GUARD_OFF.y)) < 0.05, "both fists up in the guard (%s, %s)" % [str(pi.main), str(pi.off)])
	pi.set_unarmed(false, false)
	pi.main = {"x": 1.2, "y": -0.8}
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(absf(float(pi.main.x) - 1.2) < 1e-6, "a weapon hand stays where it was aimed")
	pi.queue_free()

## Only a man with both hands empty boxes (user: with a sword in one hand the free one was held up
## in a boxer's guard): the free hand beside a weapon goes down to his side, whichever hand holds
## it, and once both are empty again both fists come up into the guard.
func test_a_free_hand_beside_a_weapon_is_not_in_a_guard() -> void:
	var pi := PlayerInput.new()
	add_child(pi)
	pi.set_unarmed(true, true)
	for i in 60:
		pi.sample(1.0 / 60.0)
	pi.set_unarmed(false, true)   # a sword taken up in the right hand
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(float(pi.off.y) < 0.3, "a sword in the right hand: the left hangs at his side (%s)" % str(pi.off))
	pi.set_unarmed(true, false)   # in the left (a shield, a blade)
	pi.main = PlayerInput.GUARD_MAIN.duplicate()
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(float(pi.main.y) < 0.3, "something in the left hand: the right hangs at his side (%s)" % str(pi.main))
	pi.set_unarmed(true, true)
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(absf(float(pi.main.y) - float(PlayerInput.GUARD_MAIN.y)) < 0.05 and absf(float(pi.off.y) - float(PlayerInput.GUARD_OFF.y)) < 0.05, "both hands empty again: both fists up in the guard (%s, %s)" % [str(pi.main), str(pi.off)])
	pi.queue_free()

## A man swinging hard has breath for a fight's exchanges: a dozen hard strokes of a sword and he
## is still standing well (user: three swings and his breath was gone, and he waited to be killed).
func test_hard_strokes_leave_him_his_breath() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "longsword", "off": "", "armor": ["helmet", "lorica"]}})
	var f: Fighter = m.me.f
	var st := {"t": 0.0}
	m.me.drive = func(_e):
		var ph := fmod(float(st.t), 1.0)
		var u := clampf(ph / 0.25, 0.0, 1.0) if ph < 0.25 else clampf(1.0 - (ph - 0.25) / 0.25, 0.0, 1.0)
		return {"main": {"x": -1.8 + 3.6 * u, "y": 0.3 + 0.5 * sin(u * PI)}, "off": {"x": -0.35, "y": 0.1}, "power": ph < 0.5, "look": {"yaw": f.yaw, "pitch": 0.0}}
	await _steps(120)
	for i in 120 * 12:
		await get_tree().physics_frame
		st.t = float(st.t) + 1.0 / 120.0
	t.check(f.stamina > 45.0, "a dozen hard strokes of a longsword in armour leave him %.0f breath" % f.stamina)
	m.queue_free()
	await get_tree().physics_frame

## A punch like a real one (user: it starts from the bent elbow, and at the end the arm
## straightens and the fist lands): out of the guard the elbow stays bent, it opens on the way
## out and locks straight for the blow (not before), the fist going fast, and on the way back the
## arm folds into the guard again at once (it once hung out straight, or bent the elbow up and
## out, and swung up before it came in).
func test_a_punch_opens_the_elbow_on_its_way_out() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	me.teleport(Vector3(0, 0, 0))
	var st := {"jab": ""}
	m.me.drive = func(_e):
		var o := {"look": {"yaw": 0.0, "pitch": 0.0}, "main": PlayerInput.GUARD_MAIN, "off": PlayerInput.GUARD_OFF}
		if st.jab != "":
			o["jab" + String(st.jab)] = true
			st.jab = ""
		return o
	var bend := func(side: String) -> float:
		return (PD.quat_of(me.arm[side].upper) * Vector3.DOWN).angle_to(PD.quat_of(me.arm[side].fore) * Vector3.DOWN)
	await _steps(150)
	for side in ["R", "L"]:
		var guard: float = bend.call(side)
		st.jab = side
		var start := PI      # the least bend in the punch's first frames
		var least := PI      # the least on its way out
		var locked_at := -1
		var fastest := 0.0
		var rise := -PI      # how far the upper arm rose above level once the blow was struck
		var home := 0.0      # the bend a little after the punch is done
		var fore: VoxelPart = me.arm[side].fore
		for f in 60:
			await get_tree().physics_frame
			var b: float = bend.call(side)
			if f < 4:
				start = minf(start, b)
			elif f < 26:
				least = minf(least, b)
				fastest = maxf(fastest, fore.velocity_at(me.hand_world(side)).length())
			if locked_at < 0 and fore.get_meta("elbow_locked", false):
				locked_at = f
			if f >= 26:
				var ua: Vector3 = PD.quat_of(me.arm[side].upper) * Vector3.DOWN
				rise = maxf(rise, asin(clampf(ua.y, -1.0, 1.0)))
			if f == 45:
				home = b
		t.check(guard > 0.8, "%s: the guard's elbow is bent (%.0f deg)" % [side, rad_to_deg(guard)])
		t.check(start > 0.8, "%s: the punch leaves the guard with the elbow bent (%.0f deg at the least)" % [side, rad_to_deg(start)])
		t.check(least < 0.1 and locked_at >= 4 and locked_at < 26, "%s: and the arm is straight, locked, by the end of its way out (%.0f deg; locked at step %d)" % [side, rad_to_deg(least), locked_at])
		t.check(fastest > 8.0, "%s: the fist goes out fast (%.1f m/s)" % [side, fastest])
		t.check(home > guard - 0.25 and not fore.get_meta("elbow_locked", false), "%s: on its way back the arm folds into the guard again (%.0f deg, the guard's %.0f)" % [side, rad_to_deg(home), rad_to_deg(guard)])
		t.check(rise < deg_to_rad(30.0), "%s: and comes home without swinging up first (the upper arm %.0f deg above level at the most)" % [side, rad_to_deg(rise)])
		await _steps(90)
	m.queue_free()
	await get_tree().physics_frame

## A punch is one motion (user: it jumped from the pullback to its full reach): its mark never
## jumps from one step to the next, it is drawn in first and is out at the end of the drive; and
## the trunk is most of the way round before the fist is out.
func test_a_punch_is_one_motion() -> void:
	var worst := 0.0
	var dk := 1.0 / (Fighter.JAB_TIME * 120.0)
	var k := 0.0
	while k < 1.0:
		worst = maxf(worst, absf(Fighter.jab_reach_at(minf(1.0, k + dk)) - Fighter.jab_reach_at(k)))
		k += dk
	t.check(worst < 0.6, "the fist's mark moves on step by step (the most in one step %.2f)" % worst)
	t.check(Fighter.jab_reach_at(Fighter.JAB_DRAW * 0.9) < 0.0 and Fighter.jab_reach_at(Fighter.JAB_OUT) > 1.7, "drawn in first, out at the end of the drive")
	t.check(Fighter.jab_reach_at(1.0) < 0.01, "and home at the end")
	t.check(Fighter.jab_turn_at(Fighter.JAB_DRAW) > 0.5 and Fighter.jab_turn_at(Fighter.JAB_OUT) > 0.99, "the trunk is turning before the fist goes (%.2f) and round when it is out" % Fighter.jab_turn_at(Fighter.JAB_DRAW))

## A fist strikes while it is thrown or swung, not drawn in or on its way home or flung by a blow
## (any touch of it while the punch's clock ran was a punch); a foot while it goes out, not as the
## knee comes up or the foot is set down.
func test_fists_and_feet_strike_only_on_their_way() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	var at := func(k: float) -> int:
		me.jab_t["R"] = Fighter.JAB_TIME * (1.0 - k)
		return me.fist_strike("R")
	t.eq(at.call(0.05), 0, "drawn in: no punch")
	t.eq(at.call(0.25), 2, "on its way out: a punch")
	t.eq(at.call(0.8), 0, "on its way home: no punch")
	me.jab_t["R"] = 0.0
	me.fist_swing["R"] = 0.0
	t.eq(me.fist_strike("R"), 0, "a hand at rest (or knocked aside) strikes nothing")
	me.fist_swing["R"] = 0.1
	t.eq(me.fist_strike("R"), 1, "swung by its owner it strikes")
	me.fist_swing["R"] = 0.0
	me.stomp_at = null
	me.kick_timer = Fighter.KICK_TIME - 0.03
	t.check(not me.kick_strike(), "the knee coming up kicks nothing")
	me.kick_timer = Fighter.KICK_TIME - 0.18
	t.check(me.kick_strike(), "the foot going out kicks")
	me.kick_timer = Fighter.KICK_TIME - 0.38
	t.check(not me.kick_strike(), "nor does the foot being set down")
	me.kick_timer = 0.0
	m.queue_free()
	await get_tree().physics_frame

## A hand that holds a weapon is no fist, however fast the weapon is swung (two sword arms touching
## were punches that cracked bone: user): only an empty hand, swung, strikes as one.
func test_a_hand_that_holds_a_weapon_is_not_a_fist() -> void:
	for armed in [true, false]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius" if armed else "", "off": ""}})
		var me: Fighter = m.me.f
		var box := {"x": 0.0}
		m.me.drive = func(_e): return {"main": {"x": box.x, "y": 0.15}, "power": true, "thrust": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}
		await _steps(60)
		var struck := 0
		for i in 120:
			box.x = 1.8 if (i / 6) % 2 == 0 else -1.8   # (whipped from side to side)
			await get_tree().physics_frame
			struck = maxi(struck, me.fist_strike("R"))
		if armed:
			t.eq(struck, 0, "the hand with a sword in it is no fist, however it is swung")
		else:
			t.check(struck > 0, "the empty hand swung so is a fist")
		m.queue_free()
		await get_tree().physics_frame
