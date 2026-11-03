extends Node
## Weapons in the hand: a two-hander meant for both hands is taken in both again after a let-go;
## nothing held lies in the sand; a weapon broken down to a stump is thrown aside and the fight
## goes on without it.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match(opts: Dictionary) -> Match:
	var m := Match.new()
	add_child(m)
	opts.merge({"headless": true, "seed": 3, "decrees": [], "hazards": []}, false)
	m.setup(opts)
	return m

## Let go of the haft for a while (dragged round behind his back in a wide stroke, a stroke going
## on), the off hand takes it again as soon as it can, however long that is (it gave up after a
## second and a half: user video 1026, a two-handed sword swung in one hand); H lets go for good.
func test_a_two_hander_is_taken_again_in_both_hands() -> void:
	var m := _match({"mode": "training", "training": {"enemy": "none", "respawn": false}, "loadout": {"main": "longsword", "off": ""}})
	var f: Fighter = m.me.f
	var hand := {"x": 0.1, "y": 0.3}
	m.me.drive = func(_e): return {"main": hand, "off": {"x": -0.35, "y": 0.1}, "power": true, "look": {"yaw": f.yaw, "pitch": 0.0}}
	await _steps(120)
	t.check(f.two_handed and f.grip_want, "the longsword starts in both hands")
	f._off_hand_off_haft()
	f.grip_want = true      # (as the let-go in a wide stroke leaves it)
	f.grip_wait = 1.5
	# Out wide to the right and low for three seconds, longer than the old reach lasted.
	hand.x = 1.8
	hand.y = -0.6
	await _steps(360)
	hand.x = 0.1
	hand.y = 0.3
	var back := -1
	for i in 360:
		await get_tree().physics_frame
		if f.two_handed:
			back = i
			break
	t.check(back >= 0, "back in front, the off hand is on the haft again (after %.2f s)" % (back / 120.0))
	t.eq(String(f.toggle_grip()), "one", "H lets go of it")
	await _steps(360)
	t.check(not f.two_handed and not f.grip_want, "and it stays let go")
	m.queue_free()
	await get_tree().physics_frame

## Put into a hand hanging low (bought at the smith with the hand down), a long blade is not put
## in through the sand, and run with it stays on top of the sand (user: he ran with the new
## sword half under the floor).
func test_a_weapon_in_hand_never_lies_in_the_sand() -> void:
	for nm in ["zweihander", "longsword", "spear"]:
		var m := _match({"mode": "yard", "loadout_override": {"main": "", "off": ""}})
		var f: Fighter = m.me.f
		var run := [false]
		var yaw0 := f.yaw
		m.me.drive = func(_e): return {"mz": 1.0 if run[0] else 0.0, "sprint": run[0], "main": {"x": 0.1, "y": -1.3}, "off": {"x": -0.35, "y": 0.1}, "look": {"yaw": yaw0, "pitch": 0.0}}
		await _steps(180)
		f.rearm(Data.preset(nm), null)
		var w: Weapon = f.weapons.R
		t.check(w != null and Fighter.lowest_of(w) > -0.03, "%s: put in his hand clear of the sand (lowest %.3f m)" % [nm, Fighter.lowest_of(w) if w else 0.0])
		await _steps(60)
		run[0] = true
		var under := 0
		for i in 480:
			await get_tree().physics_frame
			if is_instance_valid(w) and Fighter.lowest_of(w) < -0.06:
				under += 1
		t.check(under < 12, "%s: run with, it stays on the sand (%d steps more than 6 cm in)" % [nm, under])
		m.queue_free()
		await get_tree().physics_frame

## A weapon broken off near the hand reaches only as far as what is left of it; a fighter left
## with a stump throws it aside and fights on with his fists (user: the giant whose hammer broke
## could not attack or do anything any more).
func test_a_broken_weapon_is_thrown_aside_and_he_fights_on() -> void:
	var m := _match({"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": true, "respawn": false, "difficulty": 0.7}, "loadout": {"main": "gladius", "off": ""}})
	var me: Fighter = m.me.f
	m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "look": {"yaw": me.yaw, "pitch": 0.0}}
	await _steps(120)
	var g: Fighter = m.enemies()[0].f
	var w: Weapon = g.weapons.R
	t.check(w != null, "the cyclops has his hammer")
	var full := w.reach
	# Snapped just above the grip: everything past it falls off.
	var top_grip := -INF
	for i in w.vox.size():
		if w.alive[i] and String(w.vox[i][4]) == "grip":
			top_grip = maxf(top_grip, float(w.vox[i][1]))
	var cut := []
	for i in w.vox.size():
		if w.alive[i] and float(w.vox[i][1]) == top_grip + 1.0:
			cut.append(i)
	for i in cut:
		w.knock(i, 1e6)
	t.check(w.reach < full * 0.5 and w.is_stub(), "broken at the haft it reaches %.2f m of %.2f" % [w.reach, full])
	var landed := [0]   # (a lambda's own copy of a number would not count)
	m.combat.hit.connect(func(h):
		if h.get("attacker") == g and h.get("char") == me:
			landed[0] += 1)
	for i in 120 * 40:
		await get_tree().physics_frame
		if landed[0] >= 1:
			break
	t.check(g.weapons.R != w, "he threw the stump aside")
	t.check(landed[0] >= 1, "and he still lands blows on the man (%d)" % landed[0])
	m.queue_free()
	await get_tree().physics_frame

## A giant with nothing in his hands and nothing to pick up brings his fists down on a man a third
## his size: he stoops to him and the fist lands on the man's head or body, and he stays on his
## feet (thrown straight out from a giant's shoulder, the fist passed a metre over the man's head
## and never landed: user, the giant whose hammer broke could not attack any more).
func test_a_bare_handed_giant_brings_his_fists_down_on_a_man() -> void:
	var m := _match({"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": true, "respawn": false, "difficulty": 0.7}, "loadout": {"main": "gladius", "off": ""}})
	var me: Fighter = m.me.f
	m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "look": {"yaw": me.yaw, "pitch": 0.0}}
	await _steps(60)
	var g: Fighter = m.enemies()[0].f
	# His hammer gone altogether: nothing on the sand to take up instead.
	for side in ["R", "L"]:
		var w: Weapon = g.weapons[side]
		if w:
			g.release(side)
			w.queue_free()
	await _steps(2)
	var fists := []
	m.combat.hit.connect(func(h):
		if h.get("attacker") == g and h.get("char") == me and h.get("punch", false):
			fists.append(String(h.part.part_name) if h.get("part") else "?"))
	var fell := false
	var bent := 0.0
	for i in 120 * 30:
		await get_tree().physics_frame
		fell = fell or g.state != "stand"
		bent = maxf(bent, g.grab_bend)
		if fists.size() >= 2:
			break
	t.check(fists.size() >= 2, "his fists land on the man (%s)" % str(fists))
	t.check(fists.any(func(p): return p in ["head", "torso"]), "on his head or his body, not only his arms")
	t.check(bent > 0.3, "stooping to him to do it (%.2f)" % bent)
	t.check(not fell, "and he stays on his feet")
	m.queue_free()
	await get_tree().physics_frame
