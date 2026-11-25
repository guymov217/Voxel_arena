extends Node
## The experiment of scripts/game/match.gd: the controls of the men who are only fighting, run on the engine's worker threads (off in the game: `-- --control-threads`).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _fight(threads: bool) -> Match:
	Match.control_threads = threads
	seed(11)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "headless": true, "seed": 11, "autopilot": true, "autopilot_diff": 0.9,
		"loadout": {"main": "gladius", "off": "scutum", "armor": []}})
	for i in 3:
		var a := TAU * float(i) / 3.0
		m.spawn_fighter({"kind": "bot", "name": "B%d" % i, "loadout": {"main": ["axe", "gladius", "mace"][i], "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(sin(a) * 3.0, 0.1, cos(a) * 3.0), "yaw": a + PI, "diff": 0.8})
	return m

func test_only_the_men_who_are_only_fighting_go_to_the_threads() -> void:
	var m := await _fight(false)
	await _steps(140)   # (past a man's first second: the tables filled at a first use are filled by then)
	var f: Fighter = m.entities[1].f
	t.check(m._threadable(f, {}), "a man on his feet, armed and whole, a second into the fight: his control may go to a thread")
	t.check(not m._threadable(f, {"grip": true}) and not m._threadable(f, {"swap": true}), "not in a step he asks for a grip or a swap of hands in")
	var was_reach = f.reach.R
	f.reach.R = {"phase": "go"}
	t.check(not m._threadable(f, {}), "not while a hand of his reaches for a weapon (it ends in a joint made, a node added)")
	f.reach.R = was_reach
	var blood := f.blood
	f.blood = 10.0
	t.check(not m._threadable(f, {}), "not near his death")
	f.blood = blood
	var state := f.state
	f.state = "down"
	t.check(not m._threadable(f, {}), "not while he is down")
	f.state = state
	f.time = 0.2
	t.check(not m._threadable(f, {}), "not in his first second")
	f.time = 5.0
	t.check(m._threadable(f, {}), "and again when all of it is over")
	t.check(Match.dss(f.torso) == f.torso.get_world_3d().direct_space_state and Match.pool_space == null, "outside the threads the space's state is the world's own")
	m.queue_free()

func test_a_fight_with_the_controls_on_the_threads_is_a_fight() -> void:
	var m := await _fight(true)
	var hits := [0]
	m.combat.hit.connect(func(_h): hits[0] += 1)
	var threaded := [0]
	var start: Vector3 = m.entities[1].f.torso.global_position
	for i in 720:
		await get_tree().physics_frame
		for e in m.entities:
			if is_instance_valid(e.f) and e.kind != "beast" and m._threadable(e.f, {}):
				threaded[0] += 1
	Match.control_threads = false
	var moved: float = (m.entities[1].f.torso.global_position - start).length()
	var standing := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.torso.global_position.y > 0.6).size()
	t.check(threaded[0] > 600, "most of the men's steps were the threads' (%d of %d)" % [threaded[0], 720 * 4])
	t.check(hits[0] > 0 and moved > 0.3 and standing >= 1, "the men walked, stood and struck as they do (%d hits, the first walked %.1f m, %d on their feet)" % [hits[0], moved, standing])
	t.check(Match.pool_space == null and m._jobs.is_empty(), "nothing is left over when a step is done")
	m.queue_free()
