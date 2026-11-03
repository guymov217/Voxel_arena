extends Node
## A gladiator with a blade in each hand fights with both (user: dual wield): his blows come from
## the left as well as the right, often one after the other, the blade not striking held up in
## guard; with a shield on the left arm, or both hands on one haft, he fights as before.

var t

func _setup(off: String) -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var e = m.spawn_fighter({"kind": "bot", "name": "Dimachaerus", "loadout": {"main": "gladius", "off": off}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": PI, "diff": 0.8, "personality": "standard"})
	return [m, man, e]

func test_a_man_with_two_blades_strikes_with_both() -> void:
	var s := _setup("dagger")
	var m: Match = s[0]
	var man: Fighter = s[1]
	var e = s[2]
	var f: Fighter = e.f
	t.check(f.weapons.L != null and not f.weapons.L.is_shield and e.bot.dual(), "a blade in each hand: he fights with both")
	var by := {"R": 0, "L": 0}
	m.combat.hit.connect(func(h):
		if h.get("char") == man and h.get("weapon") != null:
			if h.weapon == f.weapons.R:
				by.R += 1
			elif h.weapon == f.weapons.L:
				by.L += 1)
	var swung_left := 0
	var left_up := 0
	var guard_frames := 0
	for i in 120 * 25:
		# (The man he fights only has to be there to be fought.)
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 60.0)
		man.torso.hp = maxf(man.torso.hp, 60.0)
		await get_tree().physics_frame
		if e.bot.state == "attack" and e.bot.att_side == "L":
			swung_left += 1
		elif e.bot.state != "attack" and man.state == "stand":
			# (With the man down on the sand both blades go down at him.)
			guard_frames += 1
			if f.hand_input.L.get("y", 0.0) > 0.0:
				left_up += 1
		# (Not before his guard between blows has been watched a while: with blows landing
		# fast, two and two came in a second and left a frame or two of it to judge.)
		if by.R >= 2 and by.L >= 2 and guard_frames > 60:
			break
	t.check(swung_left > 0, "he struck with the left")
	t.check(by.L >= 1 and by.R >= 1, "and landed blows with both blades (%s)" % str(by))
	t.check(guard_frames > 10 and float(left_up) / guard_frames > 0.8, "between blows, the man before him on his feet, the left blade is up in guard (%d of %d)" % [left_up, guard_frames])
	m.queue_free()

## A shield on the left arm is a shield: no blows from it, held up before him as ever.
func test_a_shield_is_not_a_second_blade() -> void:
	var s := _setup("roundShield")
	var m: Match = s[0]
	var e = s[2]
	t.check(not e.bot.dual(), "sword and shield: one blade")
	for i in 120 * 6:
		s[1].blood = 100.0
		await get_tree().physics_frame
		if e.bot.att_side != "R":
			break
	t.eq(e.bot.att_side, "R", "every blow from the right")
	m.queue_free()
