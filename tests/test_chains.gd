extends Node
## Chain weapons (weapon.js chains): the links and the head hang together from the handle,
## the head hits for the man swinging it, and a chain torn apart is laid straight again.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _step(w: TestWorld, n: int, inputs: Callable) -> void:
	for i in n:
		for f in w.fighters:
			f.control(1.0 / 120.0, inputs.call(f, i))
		await get_tree().physics_frame

func test_every_chain_weapon_hangs_together() -> void:
	var w := _world()
	var keys := ["flail", "nunchaku", "meteorHammer", "whip", "imperialFlail"]
	var men := []
	for i in keys.size():
		men.append(w.fighter(Vector3(i * 2.0 - 4.0, 0, 0), 0.0, {"main": keys[i]}, {"name": keys[i], "slot": i}))
	await _step(w, 240, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	for i in keys.size():
		var f: Fighter = men[i]
		var wp: Weapon = f.weapons.R
		t.check(wp != null and wp.chain_head != null, "%s has a chain head" % keys[i])
		if wp == null or wp.chain_head == null:
			continue
		t.eq(wp.chain_links.size(), int(wp.design.chain.links), "%s has all its links" % keys[i])
		var full := wp.chain_len * (wp.chain_links.size() + 1) + 0.4
		var d := (wp.chain_head.global_transform * wp.head_anchor).distance_to(wp.global_transform * wp.chain_anchor)
		t.check(d < full, "%s head stays on its chain (%.2f m of at most %.2f)" % [keys[i], d, full])
		t.eq(f.state, "stand", "%s still standing" % keys[i])
	w.queue_free()

func test_a_swung_flail_head_hits() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "flail"}, {"name": "a", "slot": 0})
	var b := w.fighter(Vector3(0, 0, 1.3), PI, {}, {"name": "dummy", "slot": 1})
	var head: Weapon = a.weapons.R.chain_head
	var hits := []
	w.combat.hit.connect(func(h): if h.char == b: hits.append(h))
	await _step(w, 900, func(f, i):
		if f == b:
			return {"main": {"x": 0.0, "y": 0.0}}
		var ph: float = i / 120.0 * 1.2
		return {"main": {"x": 1.4 * sin(ph * TAU), "y": 0.6 + 0.4 * cos(ph * TAU)}, "power": true})
	var by_head := hits.filter(func(h): return h.weapon == head)
	t.check(by_head.size() > 0, "the head struck (%d hits, %d by the head)" % [hits.size(), by_head.size()])
	t.check(by_head.all(func(h): return h.attacker == a), "for the man swinging it")
	w.queue_free()

func test_a_torn_chain_is_laid_straight() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "meteorHammer"}, {"name": "a", "slot": 0})
	await _step(w, 30, func(_f, _i): return {})
	var wp: Weapon = a.weapons.R
	wp.chain_head.global_position += Vector3(0, 0, 30)
	await _step(w, 2, func(_f, _i): return {})
	var d := wp.chain_head.global_position.distance_to(wp.global_position)
	t.check(d < 3.0, "the head came back to the handle (%.1f m)" % d)
	w.queue_free()
