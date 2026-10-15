extends Node
## Firebombs and fire breath as liquids: a pot of Greek fire bursts along the way it flew, the
## pool spreads, burns what stands in it, and burns out; a dragon's breath is a stream of
## burning globs that sets alight the man it reaches, and not the man behind a wall.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _man(m: Match, pos: Vector3) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func _fuel(m: Match) -> float:
	var f := 0.0
	for k in m.throwables.wet:
		f += m.throwables.wet[k].f
	return f

func test_a_firebomb_pools_spreads_burns_and_burns_out() -> void:
	seed(9)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -8))
	var v := _man(m, Vector3(0.4, 0.1, 3.2))
	await _steps(20)
	m.items.spawn("pot_fire", Vector3(0, 1.4, -1.5), Vector3(0, 0.5, 8.0), m.me.f)
	await _steps(150)
	var cells: int = m.throwables.wet.size()
	var lo := Vector2(INF, INF)
	var hi := -Vector2(INF, INF)
	for k in m.throwables.wet:
		lo = lo.min(Vector2(k.x, k.z)); hi = hi.max(Vector2(k.x, k.z))
	t.check(cells > 40, "the pot bursts into a pool, not a spot (%d cells)" % cells)
	t.check((hi - lo).length() * Throwables.CELL > 2.0, "spread out over metres (%.1f m)" % ((hi - lo).length() * Throwables.CELL))
	t.check(Fire.is_burning(v), "the man standing in its way catches")
	var f1 := _fuel(m)
	await _steps(120 * 4)
	t.check(_fuel(m) < f1 * 0.8, "it burns its fuel away (%.2f -> %.2f)" % [f1, _fuel(m)])
	await _steps(120 * 16)
	t.check(m.throwables.wet.is_empty(), "and in the end it is out")
	m.queue_free()

func test_fire_breath_is_a_stream_a_wall_stops() -> void:
	seed(10)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -12))
	var e = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
	var b: Beast = e.f
	b.sp = b.sp.duplicate(); b.sp.speed = 0.0; b.sp.lunge = 0.0; b.sp.flies = false
	b.target = null
	var open_man := _man(m, Vector3(0.0, 0.1, 6.0))
	var hid := _man(m, Vector3(3.5, 0.1, 6.0))
	var wall := StaticBody3D.new()
	wall.collision_layer = VoxelPart.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.6, 3.0, 0.3)
	cs.shape = bx
	wall.add_child(cs)
	m.add_child(wall)
	await _steps(90)
	var mouth: Vector3 = b.breath_part().global_position
	wall.global_position = mouth.lerp(hid.torso.global_position, 0.55) + Vector3(0, -0.5, 0)
	wall.look_at(hid.torso.global_position, Vector3.UP)
	m.stream(b, "fire", open_man.torso.global_position, 7.0, 0.9, open_man)
	await _steps(180)
	t.check(Fire.is_burning(open_man), "the man in the open is set alight by the stream")
	m.stream(b, "fire", hid.torso.global_position, 7.0, 0.9, hid)
	await _steps(200)
	t.check(not Fire.is_burning(hid), "the man behind the wall is not")
	m.queue_free()
