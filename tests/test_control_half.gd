extends Node
## The other experiment of scripts/game/match.gd: a man's control every other step, the step it runs standing for two (off in the game: `-- --control-half`).

var t

func _fight(half: bool) -> Match:
	Match.control_half = half
	seed(11)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "headless": true, "seed": 11, "autopilot": true, "autopilot_diff": 0.9,
		"loadout": {"main": "gladius", "off": "scutum", "armor": []}})
	for i in 3:
		var a := TAU * float(i) / 3.0
		m.spawn_fighter({"kind": "bot", "name": "B%d" % i, "loadout": {"main": ["axe", "gladius", "mace"][i], "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(sin(a) * 3.0, 0.1, cos(a) * 3.0), "yaw": a + PI, "diff": 0.8})
	return m

func test_it_is_off_in_the_game() -> void:
	t.check(not Match.control_half, "a man's control runs every step unless the experiment is asked for")

func test_an_order_of_the_step_left_out_is_not_lost() -> void:
	var now := {"jabR": false, "mx": 0.4, "main": {"x": 0.1, "y": 0.2}, "block": true}
	var skipped := {"jabR": true, "kick": true, "mx": 1.0, "main": {"x": 0.9, "y": 0.9}, "block": false, "useItem": 2}
	var out := Match.merge_skipped(now, skipped)
	t.check(out.jabR == true and out.get("kick") == true, "a jab and a kick asked for in the step left out are carried into the next")
	t.check(float(out.mx) == 0.4 and float(out.main.x) == 0.1 and out.block == true and not out.has("useItem"), "what is held, aimed or counted is this step's own")
	t.check(now.jabR == false and not now.has("kick"), "the orders as they came are left as they were")
	var same := {"mx": 0.2}
	t.check(is_same(Match.merge_skipped(same, {"mx": 0.9, "jabR": false}), same) and is_same(Match.merge_skipped(same, null), same), "nothing to carry: the same orders, not a copy")

func test_a_fight_at_every_other_step_is_a_fight() -> void:
	var m := await _fight(true)
	var hits := [0]
	m.combat.hit.connect(func(_h): hits[0] += 1)
	var f: Fighter = m.entities[1].f
	var start: Vector3 = f.torso.global_position
	var t_was: float = f.time
	for i in 720:
		await get_tree().physics_frame
	Match.control_half = false
	var moved: float = (f.torso.global_position - start).length()
	var standing := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.torso.global_position.y > 0.6).size()
	var flung := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.torso.linear_velocity.length() > 20.0).size()
	t.check(absf((f.time - t_was) - 6.0) < 0.05, "his own clock keeps the time: six seconds in 720 steps, 360 of them his (%.2f)" % (f.time - t_was))
	t.check(hits[0] > 0 and moved > 0.3 and standing >= 1 and flung == 0, "the men walked, stood and struck, and nobody was flung (%d hits, the first walked %.1f m, %d on their feet)" % [hits[0], moved, standing])
	m.queue_free()
