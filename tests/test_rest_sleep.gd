extends Node
## What lies still lies asleep: a chunk of gore or a weapon lying loose, for a second and a half (Chunk.REST_AFTER, Combat._rest_weapons),
## so that a heap of the dead with such things on it can rest too (one lump awake on a corpse kept the whole heap awake, every step).
## The physics wakes them the moment anything touches them; what they lay on gone from under them, they look and fall; a weapon taken up
## is awake and sleepless as a held one ever was.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _chunk(w: Node, at: Vector3) -> Chunk:
	var c := Chunk.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.1, 0.1, 0.1)
	cs.shape = bs
	c.add_child(cs)
	c.collision_layer = VoxelPart.LAYER_DEBRIS
	c.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_DEBRIS
	w.add_child(c)
	c.global_position = at
	return c

func test_a_chunk_lying_still_sleeps_and_falls_when_what_it_lay_on_is_gone() -> void:
	var w := _world()
	var c := _chunk(w, Vector3(0, 0.5, 0))
	for i in 6:
		await get_tree().physics_frame
	t.check(not c.sleeping, "a chunk still falling is awake")
	for i in 420:
		await get_tree().physics_frame
	t.check(c.sleeping, "lying still on the sand for a second and a half and more, it sleeps")
	var y0 := c.global_position.y
	# What it lay on gone from under it (a body carried off the sand): it looks under itself and falls.
	c.global_position += Vector3(0, 1.0, 0)
	for i in 120:
		await get_tree().physics_frame
	t.check(not c.sleeping or c.global_position.y < y0 + 0.9, "with nothing under it any more it wakes (%.2f m up)" % (c.global_position.y - y0))
	for i in 240:
		await get_tree().physics_frame
	t.check(absf(c.global_position.y - y0) < 0.05, "and falls back onto the sand (%.3f m off where it lay)" % (c.global_position.y - y0))
	w.queue_free()

func test_a_chunk_is_woken_by_what_lands_on_it() -> void:
	var w := _world()
	var c := _chunk(w, Vector3(0, 0.2, 0))
	for i in 360:
		await get_tree().physics_frame
	t.check(c.sleeping, "a chunk at rest sleeps")
	var d := _chunk(w, Vector3(0.0, 0.6, 0.0))
	for i in 90:
		await get_tree().physics_frame
	t.check(not c.sleeping or d.sleeping, "another dropped on it wakes it, or lies on it (the physics sees to it)")
	t.check(d.global_position.y > c.global_position.y - 0.01, "and it lies on it, not through it (%.2f over %.2f)" % [d.global_position.y, c.global_position.y])
	w.queue_free()

func test_a_loose_weapon_sleeps_and_is_awake_and_sleepless_in_a_hand_again() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -14))
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius"}, "team": 0, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "diff": 0.8})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	var sword: Weapon = f.weapons.R
	t.check(sword != null and not sword.can_sleep, "a weapon in a hand is never let sleep")
	f.release("R")
	t.check(m.combat.loose_weapons.has(sword), "let go of, it lies loose")
	for i in 420:
		await get_tree().physics_frame
	t.check(sword.sleeping, "lying loose and still, it sleeps (%s)" % ("asleep" if sword.sleeping else "awake, v %.3f" % sword.linear_velocity.length()))
	f.pick_up("R", sword, true)
	t.check(f.weapons.R == sword and not sword.sleeping and not sword.can_sleep, "taken up it is awake and sleepless again")
	for i in 240:
		await get_tree().physics_frame
	t.check(not sword.sleeping and sword.holder == f, "and stays so in his hand")
	m.queue_free()
