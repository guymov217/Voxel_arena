extends Node
## Beasts feel a blow and do not stand by (user: a wolf stood looking at him while he beat it, no
## sign it felt a thing; some beasts let a man take them apart a whole fight): every blow on a
## beast jolts it away from the blow and its head and legs flinch; one close to a man goes for
## him, again and again, and does not stand there for long.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _arena(sp: String) -> Array:
	# Each beast in a physics world of its own, as each test is (runner.gd): in the one before it,
	# the second beast's fight came out as the first one's had left the world.
	get_tree().root.world_3d = World3D.new()
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": sp, "immortal": true}, "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	m.me.drive = func(_e): return {}
	var b: Beast = null
	for e in m.entities:
		if e.f is Beast:
			b = e.f
	return [m, b]

func test_every_blow_on_a_beast_shows() -> void:
	for sp in ["wolf", "lion", "boar", "bear", "bull"]:
		var r := _arena(sp)
		var m: Match = r[0]
		var b: Beast = r[1]
		t.check(b != null, "a %s in the arena" % sp)
		if b == null:
			m.queue_free()
			continue
		await _steps(90)
		for k in 3:
			# From its side, a fair blow: the jolt is across the way it goes, not its own stride.
			var dir: Vector3 = b.torso.global_transform.basis.x
			dir.y = 0.0
			dir = dir.normalized()
			var v0: float = b.torso.linear_velocity.dot(dir)
			b.apply_hit(b.torso, {"impulse": 20.0, "type": "blunt", "hardness": 0.8, "heavy": 0.0, "point": b.torso.global_position - dir * b.torso.half_ext.x, "dir": dir})
			var head_flinch: float = b.head.flinch_t
			await _steps(2)
			var dv: float = b.torso.linear_velocity.dot(dir) - v0
			t.check(head_flinch > 0.1, "a %s struck (blow %d): its head flinches (%.2f s)" % [sp, k + 1, head_flinch])
			t.check(dv > 0.12, "a %s struck (blow %d): its body jolts away from the blow (%.2f m/s)" % [sp, k + 1, dv])
			await _steps(40)
		m.queue_free()
		await _steps(2)

func test_a_beast_close_to_a_man_keeps_going_for_him() -> void:
	for sp in ["wolf", "lion", "boar"]:
		var r := _arena(sp)
		var m: Match = r[0]
		var b: Beast = r[1]
		t.check(b != null, "a %s in the arena" % sp)
		if b == null:
			m.queue_free()
			continue
		var me: Fighter = m.me.f
		var strikes := []
		m.combat.hit.connect(func(h): if h.get("attacker") == b and h.get("char") == me: strikes.append(b.time))
		# He stands there and lets it come: 25 s.
		var close_idle := 0.0
		var worst := 0.0
		var seen := 0
		for i in 25 * 120:
			await get_tree().physics_frame
			var d: float = b.torso.global_position.distance_to(me.torso.global_position)
			if d < 2.6 * b.S and strikes.size() == seen:
				close_idle += 1.0 / 120.0
				worst = maxf(worst, close_idle)
			else:
				close_idle = 0.0
				seen = strikes.size()
		t.check(strikes.size() >= 4, "a %s goes for a man standing there again and again (%d strikes in 25 s)" % [sp, strikes.size()])
		t.check(worst < 8.0, "a %s does not stand by him long without one (%.1f s at most)" % [sp, worst])
		print("  %s: %d strikes in 25 s, %.1f s at most by him without one" % [sp, strikes.size(), worst])
		m.queue_free()
		await _steps(2)
