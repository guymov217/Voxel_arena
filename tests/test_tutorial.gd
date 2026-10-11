extends Node
## The tutorial (tutorial.js): each step is done the moment the player has done it, the javelin
## and the recruit arrive on their steps, and beating the recruit ends it.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_the_tutorial_walks_through_its_steps() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "headless": true, "tutorial": true, "training": {"enemy": "none", "respawn": false}, "seed": 2, "decrees": [], "hazards": []})
	var tu: Tutorial = m.tut
	t.check(tu != null and tu.dummy != null, "a dummy to practise on")
	t.eq(String(tu.view().title), "Walk", "first, walking")
	await _steps(5)
	m.me.f.teleport(m.me.f.torso.global_position + Vector3(3, 0, 0))
	await _steps(130)
	t.eq(String(tu.view().title), "Look", "three metres: done")
	tu.s.turned = 3.0
	await _steps(130)
	tu.s.hits = 2
	await _steps(130)
	tu.s.guard_t = 1.0
	await _steps(130)
	tu.s.kicks = 1
	await _steps(130)
	t.eq(String(tu.view().title), "Throw", "on to throwing")
	var loose := m.combat.loose_weapons.size()
	tu.s.throws = 1
	await _steps(130)
	t.eq(String(tu.view().title), "Pick up", "the sword is gone")
	t.eq(m.combat.loose_weapons.size(), loose + 1, "a javelin lies on the sand")
	tu.s.armed = true
	tu.had_weapon = true
	m.me.f.weapons["R"] = m.me.f.weapons.get("R") if m.me.f.weapons.get("R") else m.combat.loose_weapons[-1]
	await _steps(130)
	t.eq(String(tu.view().title), "A real fight", "the last step")
	t.check(tu.recruit != null and tu.recruit.alive, "a recruit steps in")
	var res := []
	m.finished.connect(func(r): res.append(r))
	tu.recruit.die("wounds")
	await _steps(140)
	t.check(tu.finished and not res.is_empty() and res[0].won, "beaten: the tutorial is over")
	m.queue_free()
