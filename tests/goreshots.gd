extends Node
## The insides on camera (`-- --probe goreshots`, needs a display): the organs and the bones in a
## cut-away trunk and head, guts spilled from an opened belly, a cut artery spurting, blood run
## down a chest, an open break, a lion opened up. PNGs go to SHOT_DIR as gore_<view>.png.

var m: Match
var cam: Camera3D

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("gore_%s.png" % name_))
	print("saved ", name_)

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _look(at: Vector3, from: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)

func _man(pos: Vector3, yaw := PI) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func _slash(v: Fighter, part: VoxelPart, local: Vector3, along: Vector3, J := 45.0) -> Dictionary:
	part.hp = 1000.0
	v.heart_t = -1.0
	var gt := part.global_transform
	var bx := gt.basis.orthonormalized()
	# Straight in through the face it lands on.
	var q := local / part.half_ext
	var face := Vector3(signf(q.x), 0, 0) if absf(q.x) >= absf(q.y) and absf(q.x) >= absf(q.z) else (Vector3(0, signf(q.y), 0) if absf(q.y) >= absf(q.z) else Vector3(0, 0, signf(q.z)))
	var into := -(bx * face)
	return v.apply_hit(part, {"impulse": J, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": gt * local, "dir": into, "axis": bx * along, "edge": into})

func _ready() -> void:
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -12))
	cam = Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	await _steps(30)
	# 1. A cut-away: the front of the trunk and the face taken off, the insides bared.
	var a := _man(Vector3(-1.2, 0.1, 0), 0.0)
	await _steps(90)
	for p in [a.torso, a.head]:
		var front := []
		for i in p.fx.size():
			if p.fz[i] >= p.grid.z - 2:
				front.append(i)
		p.remove_voxels(front, false, false)
	a.torso.bleed = 0.0
	await _steps(10)
	var tp := a.torso.global_position
	var fwd := PD.quat_of(a.torso) * Vector3(0, 0, 1)
	_look(tp + Vector3(0, 0.2, 0), tp + fwd * 1.5 + Vector3(0.25, 0.3, 0))
	await _save("cutaway")
	a.teleport(Vector3(-30, 0, 30))
	# 2. An opened belly: the guts hang out of it.
	var b := _man(Vector3(0, 0.1, 0), 0.0)
	await _steps(90)
	var k := 0
	while not b.guts_out and k < 10:
		_slash(b, b.torso, Vector3(0.0, -b.torso.half_ext.y * 0.4, b.torso.half_ext.z), Vector3(1, 0, 0))
		k += 1
		await _steps(4)
	print("man guts out: ", b.guts_out, " after ", k, " rope ", b.gut_rope != null)
	b.blood = 100.0
	await _steps(120 * 2)
	tp = b.torso.global_position
	fwd = PD.quat_of(b.torso) * Vector3(0, 0, 1)
	_look(tp + Vector3(0, -0.2, 0), tp + fwd * 1.6 + Vector3(0.7, 0.1, 0))
	await _save("guts")
	# From above, a little further on: where the length of them lies.
	await _steps(120)
	var gc := Vector3.ZERO
	var rope: GutRope = b.gut_rope
	if rope:
		for ch in rope.links:
			gc += ch.global_position
		gc /= float(maxi(1, rope.links.size()))
		print("guts links ", rope.links.size(), " centre ", gc)
	_look(gc, gc + Vector3(0.5, 1.6, 0.9))
	await _save("guts_top")
	# 3. Blood run down his chest from a cut, a few seconds on.
	_slash(b, b.torso, Vector3(b.torso.half_ext.x * 0.5, b.torso.half_ext.y * 0.55, b.torso.half_ext.z), Vector3(1, 0, 0), 22.0)
	b.torso.bleed = 2.0
	await _steps(120 * 4)
	b.blood = 100.0
	tp = b.torso.global_position
	_look(tp + Vector3(0, 0.1, 0), tp + fwd * 1.1 + Vector3(-0.3, 0.25, 0))
	await _save("blood_run")
	b.teleport(Vector3(-20, 0, 30))
	# 4. A cut throat: the artery spurts with every beat.
	var c := _man(Vector3(1.2, 0.1, 0), 0.0)
	await _steps(90)
	_slash(c, c.head, Vector3(c.head.half_ext.x, -c.head.half_ext.y * 0.75, c.head.half_ext.z * 0.3), Vector3(0, 0, 1), 30.0)
	_slash(c, c.by_name.thighR, Vector3(c.by_name.thighR.half_ext.x, c.by_name.thighR.half_ext.y * 0.5, 0), Vector3(0, 0, 1), 30.0)
	for i in 70:
		await get_tree().physics_frame
		c.blood = 100.0
	var hp := c.head.global_position
	_look(hp + Vector3(0, -0.45, 0), hp + Vector3(1.9, -0.1, 1.2))
	await _save("artery")
	c.teleport(Vector3(20, 0, 30))
	# 5. An open break: a hammer to the shin, the bone through the skin.
	var d := _man(Vector3(0, 0.1, 0), 0.0)
	await _steps(90)
	var sh: VoxelPart = d.by_name.shinR
	var j := 0
	while not sh.has_meta("open_break") and j < 8:
		sh.hp = 1000.0
		var gt := sh.global_transform
		var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
		d.apply_hit(sh, {"impulse": 50.0, "type": "blunt", "hardness": 0.9, "heavy": 1.0, "point": gt * Vector3(0, 0, sh.half_ext.z), "dir": -bz})
		j += 1
		await _steps(4)
	d.blood = 100.0
	await _steps(30)
	var sp := sh.global_position
	fwd = PD.quat_of(d.torso) * Vector3(0, 0, 1)
	_look(sp, sp + fwd * 0.9 + Vector3(0.25, 0.2, 0))
	await _save("open_break")
	d.teleport(Vector3(30, 0, 30))
	# 6. A lion opened up.
	var e = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 1.0), "yaw": PI * 0.5, "harmless": true})
	e.erase("bot")
	e.drive = func(_e): return {}
	var lion: Beast = e.f
	await _steps(90)
	var n := 0
	while not lion.guts_out and n < 14:
		_slash(lion, lion.torso, Vector3(0, -lion.torso.half_ext.y, -lion.torso.half_ext.z * 0.4), Vector3(0, 0, 1), 60.0)
		lion.blood = 100.0
		n += 1
		await _steps(4)
	print("lion guts out: ", lion.guts_out, " links ", lion.gut_rope.links.size() if lion.gut_rope else 0)
	await _steps(120 * 2)
	var lp := lion.torso.global_position
	_look(lp + Vector3(0, -0.3, 0), lp + Vector3(0.6, 0.2, 2.6))
	await _save("lion")
	get_tree().quit()
