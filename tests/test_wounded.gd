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
		s[1].blood = 100.0
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
	s[0].queue_free()
