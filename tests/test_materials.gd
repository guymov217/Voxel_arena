extends Node
## Every odd material of the forge does what it says: explosive powder goes off (and is gone),
## a spring throws the man away, glue holds, a magnet pulls iron; a kick only now and then
## takes a man off his feet; the anvil has room for big experiments.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -12))
	return m

func _man(m: Match, pos: Vector3, drive := {}) -> Dictionary:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return drive
	return e

## A wooden haft with a head of `mat`.
func _club(mat: String) -> Dictionary:
	var d := {"name": "Test " + mat, "voxels": []}
	for y in 6:
		d.voxels.append([0, y, 0, "wood", "grip"])
	ForgeLib.box(d, -1, 1, 6, 9, -1, 1, mat, "blunt")
	return d

func _hit(m: Match, w: Weapon, f: Fighter, J: float, mat: String) -> Dictionary:
	var p: Vector3 = w.global_transform * (Vector3(0, 7.5, 0) * w.vs)
	return {"kind": "hit", "p": p, "dir": Vector3(0, 0, 1), "J": J, "type": "blunt", "mat": mat, "weapon": w, "char": f, "part": f.torso, "attacker": null, "res": {}, "killed": false}

func test_an_explosive_head_blows_up_on_a_hard_blow() -> void:
	var m := _match()
	var v: Fighter = _man(m, Vector3(0, 0, 0)).f
	await _steps(40)
	var w := m.spawn_loose_weapon(_club("explosive"), v.torso.global_position + Vector3(0, 0.3, -1.6))
	w.rotation = Vector3(PI / 2, 0, 0)   # the head first, at him
	var n0: int = w.material_count(["explosive"])
	var hp0: float = v.torso.hp
	var booms := [0]
	m.feed.connect(func(s): if String(s) == "BOOM!": booms[0] += 1)
	await _steps(2)
	w.thrown_t = 1.0   # thrown, as from a hand
	w.linear_velocity = Vector3(0, 0, 14)
	await _steps(60)
	t.check(n0 > 0 and booms[0] >= 1, "thrown head first at a man it goes off (%d booms)" % booms[0])
	t.check(w.material_count(["explosive"]) < n0, "the powder is spent (%d of %d left)" % [w.material_count(["explosive"]), n0])
	t.check(v.torso.hp < hp0 or not v.alive, "the blast hurt him (torso %.0f of %.0f)" % [v.torso.hp, hp0])
	# A tap does not set it off.
	var w2 := m.spawn_loose_weapon(_club("explosive"), Vector3(5, 1, 5))
	await _steps(2)
	var n2: int = w2.material_count(["explosive"])
	m._materials(_hit(m, w2, v, 3.0, "explosive"))
	t.eq(w2.material_count(["explosive"]), n2, "a light touch leaves it whole")
	m.queue_free()

func test_a_spring_throws_him_back() -> void:
	var m := _match()
	var v: Fighter = _man(m, Vector3(0, 0, 0)).f
	await _steps(40)
	var w := m.spawn_loose_weapon(_club("spring"), v.torso.global_position + Vector3(0, 0, -0.6))
	await _steps(2)
	var z0: float = v.torso.linear_velocity.z
	m._materials(_hit(m, w, v, 20.0, "spring"))
	await _steps(1)
	t.check(v.torso.linear_velocity.z - z0 > 2.0, "boing: he flies off along the blow (%.1f m/s)" % (v.torso.linear_velocity.z - z0))
	m.queue_free()

func test_glue_holds_then_lets_go() -> void:
	var m := _match()
	var v: Fighter = _man(m, Vector3(0, 0, 0)).f
	await _steps(40)
	var w := m.spawn_loose_weapon(_club("glue"), v.torso.global_position + Vector3(0, 0, -0.5))
	await _steps(2)
	m._materials(_hit(m, w, v, 10.0, "glue"))
	t.eq(m.glued.size(), 1, "it sticks to him")
	await _steps(120 * 6)
	t.eq(m.glued.size(), 0, "and comes loose in the end")
	m.queue_free()

func test_a_magnet_pulls_a_steel_blade_in() -> void:
	var m := _match()
	var mag := m.spawn_loose_weapon(_club("magnet"), Vector3(0, 0.1, 0))
	var blade := m.spawn_loose_weapon(Data.preset("gladius"), Vector3(0.9, 0.1, 0))
	await _steps(60)
	var d0 := blade.global_position.distance_to(mag.material_centre("magnet"))
	await _steps(120)
	var d1 := blade.global_position.distance_to(mag.material_centre("magnet"))
	t.check(d1 < d0 - 0.15, "the blade slides to the magnet (%.2f → %.2f m)" % [d0, d1])
	var wood := m.spawn_loose_weapon(_club("wood"), Vector3(-0.9, 0.1, 0))
	await _steps(60)
	var w0 := wood.global_position.distance_to(mag.material_centre("magnet"))
	await _steps(120)
	var w1 := wood.global_position.distance_to(mag.material_centre("magnet"))
	t.check(w1 > w0 - 0.05, "wood is not pulled (%.2f → %.2f m)" % [w0, w1])
	m.queue_free()

func test_a_kick_rarely_fells_a_man() -> void:
	seed(11)
	var m := _match()
	var a = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {}, "team": 2, "pos": Vector3(0, 0, -0.9), "yaw": 0.0})
	a.erase("bot")
	var kick := [false]
	a.drive = func(_e): return {"kick": kick[0], "mz": 0.3}
	var v = _man(m, Vector3(0, 0, 0), {"mz": 0.6, "mx": 0.3})
	await _steps(90)
	var landed := [0]
	m.combat.hit.connect(func(h): if h.get("kick", false) and h.char == v.f: landed[0] += 1)
	var falls := 0
	for i in 10:
		v.f.teleport(Vector3(0, 0, 0))
		a.f.teleport(Vector3(0, 0, -0.85))
		a.f.yaw = 0.0
		v.f.yaw = PI
		v.f.stamina = 20.0   # out of breath: the worst case
		a.f.stamina = 100.0
		await _steps(90)
		kick[0] = true
		await _steps(3)
		kick[0] = false
		var fell := false
		for k in 120:
			await get_tree().physics_frame
			fell = fell or v.f.state != "stand"
		if fell:
			falls += 1
	t.check(landed[0] >= 3, "the kicks land (%d)" % landed[0])
	t.check(falls <= 3, "but few of them fell him (%d of 10)" % falls)
	m.queue_free()

func test_room_on_the_anvil_to_experiment() -> void:
	t.check(ForgeLib.in_grid(0, 80, 0) and ForgeLib.in_grid(14, 0, 5), "a 3 m pole and a wide head fit on the anvil")
	t.check(ForgeLib.MAX_VOXELS >= 1500, "room for %d voxels" % ForgeLib.MAX_VOXELS)
	var d := {"name": "Long pole", "voxels": []}
	for y in 80:
		d.voxels.append([0, y, 0, "wood", "grip" if y < 8 else "blunt"])
	t.eq(ForgeLib.too_heavy(d), "", "a 3 m wooden pole can be lifted")

func test_a_held_blade_never_sticks_in_the_floor() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "H", "loadout": {"main": "spear", "off": ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	await _steps(40)
	var w: Weapon = e.f.weapons.R
	t.check(w != null, "he holds a spear")
	if w == null:
		m.queue_free()
		return
	# The arm hangs and the point is pushed down into the sand: it goes through, not in.
	w.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.6, 0.4))
	w._out_of_the_floor()
	t.check(w.bodies().all(func(b): return not (b is CollisionObject3D) or (b.collision_mask & VoxelPart.LAYER_WORLD) == 0), "held under the floor, it passes through the sand")
	w.global_transform = Transform3D(Basis(), Vector3(0, 1.0, 0.4))
	w._out_of_the_floor()
	t.check(w.bodies().all(func(b): return not (b is CollisionObject3D) or (b.collision_mask & VoxelPart.LAYER_WORLD) != 0), "and meets the floor again once it is up")
	m.queue_free()
