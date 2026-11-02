extends Node
## Hurt, a man grows wary (Bot.wariness: longer distance, slower to begin, fewer blows strung
## together) and, near the end of his blood, desperate (one lunging blow with all his weight in
## it now and then). A boss has half the wariness; a Fighter's wound() is what the bots read.

var t

func _setup(blood: float):
	await get_tree().physics_frame
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": "roundShield"}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 3.0
	var e = m.spawn_fighter({"kind": "bot", "name": "Foe", "loadout": {"main": "gladius", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": PI, "diff": 0.8, "personality": "standard"})
	e.f.blood = blood
	return [m, man, e]

func test_a_wound_is_read_from_blood_and_limbs() -> void:
	var s = await _setup(100.0)
	var f: Fighter = s[2].f
	t.check(f.wound() < 0.05, "whole, a man has no wound (%.2f)" % f.wound())
	f.blood = 10.0
	t.check(f.wound() > 0.5, "near bled out he is far gone (%.2f)" % f.wound())
	t.check(s[2].bot.wariness() > 0.25, "and his bot is wary (%.2f)" % s[2].bot.wariness())
	f.boss = true
	t.check(s[2].bot.wariness() < 0.2, "a boss half as much (%.2f)" % s[2].bot.wariness())
	f.boss = false
	f.blood = 100.0
	t.check(s[2].bot.wariness() == 0.0, "and whole again, not at all")
	s[0].queue_free()

func test_a_dying_man_throws_a_desperate_blow() -> void:
	seed(4)
	var s = await _setup(15.0)
	var e = s[2]
	var seen := [false, false]
	for i in 120 * 12:
		# (The man he fights only has to be there to be fought: dead, he is no one to gather
		# oneself against.)
		s[1].blood = 100.0
		s[1].head.hp = maxf(s[1].head.hp, 60.0)
		s[1].torso.hp = maxf(s[1].torso.hp, 60.0)
		e.f.blood = maxf(e.f.blood, 15.0)
		await get_tree().physics_frame
		if e.bot.desperate:
			seen[0] = true
			if e.bot.state == "attack":
				seen[1] = true
		if seen[1]:
			break
	t.check(seen[0], "he gathered himself for a desperate blow")
	t.check(seen[1], "and threw it")
	t.check(s[1].alive and not s[1].head.severed, "and the man he fought is still there")
	s[0].queue_free()

## A hard thrust into the base of the neck goes deep and does its harm, but the head stays on:
## a channel through the top of the chest is not the neck cut through (a bot's first thrust took
## a man's head off in one: the fights ended at a stab, user). With all the flesh round the joint
## gone, it falls.
func test_a_thrust_at_the_base_of_the_neck_leaves_the_head_on() -> void:
	var s = await _setup(100.0)
	var v: Fighter = s[2].f
	s[2].erase("bot")
	s[2].drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	var tor := v.torso
	var gt := tor.global_transform
	var fwd := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	var cut := 0
	for k in 2:
		tor.hp = 1000.0
		var res: Dictionary = v.apply_hit(tor, {"impulse": 61.0, "type": "point", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(0.0, tor.half_ext.y * 0.85, tor.half_ext.z), "dir": -fwd, "axis": -fwd, "thrust": 1.0, "weapon": true})
		cut += (res.get("removed", []) as Array).size()
		t.check((res.get("severed", []) as Array).is_empty(), "thrust %d took nothing off (%s)" % [k + 1, str((res.get("severed", []) as Array).map(func(p): return p.part_name))])
		for i in 60:
			await get_tree().physics_frame
	t.check(cut > 0, "the thrusts went in")
	t.check(not v.head.severed and v.head.joint != null, "the head is on")
	# Every bit of flesh round the joint gone: nothing holds it.
	var at := tor.anchor_point(v.head)
	tor.remove_voxels(Array(tor.voxels_within(at, tor.half_ext.x * 0.9)))
	v._drop_unheld(tor, {"removed": [], "severed": []})
	t.check(v.head.severed, "cut away all round, it falls")
	s[0].queue_free()
